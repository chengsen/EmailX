//
//  SyncService+Move.swift
//  MyEmail
//
//  Message move operations: same-account IMAP MOVE (applying the RFC 4315
//  COPYUID target UIDs) and cross-account FETCH raw → APPEND → DELETE.
//  Extracted from SyncService+MessageOps.swift to stay inside the file-length
//  limit — behaviour is unchanged.
//

import Foundation
import GRDB
import SwiftMail

extension SyncService {

    // MARK: - Move context

    struct MoveContext: Sendable {
        let targetFolder: Folder
        let targetAccount: Account
        let sourceFolder: Folder
        let sourceAccount: Account
        let messages: [Message]
        var isCrossAccount: Bool { sourceAccount.id != targetAccount.id }
    }

    // MARK: - Move (batched, §9.1)

    func moveMessages(_ messageIDs: [UUID], to targetFolderID: UUID) async {
        guard !messageIDs.isEmpty else { return }

        let ctx: MoveContext? = try? await pool.read { db in
            guard let targetFolder = try Folder.fetchOne(db, key: targetFolderID),
                  let targetAccount = try Account.fetchOne(db, key: targetFolder.accountID) else { return nil }
            let messages = try Message
                .filter(messageIDs.contains(Column("id")))
                .fetchAll(db)
            guard let first = messages.first,
                  let sourceFolder = try Folder.fetchOne(db, key: first.folderID),
                  let sourceAccount = try Account.fetchOne(db, key: first.accountID) else { return nil }
            return MoveContext(
                targetFolder: targetFolder, targetAccount: targetAccount,
                sourceFolder: sourceFolder, sourceAccount: sourceAccount,
                messages: messages
            )
        }
        guard let ctx else { return }

        if ctx.isCrossAccount {
            await crossAccountMove(ctx: ctx, targetFolderID: targetFolderID)
        } else {
            await sameAccountMove(ctx: ctx, targetFolderID: targetFolderID)
        }
        // User-initiated move (drag/menu) is a notability signal.
        await incrementInteractionScore(messageIDs, delta: 1)
    }

    // MARK: - Same-account IMAP MOVE

    /// One source-folder's worth of messages moving to the same target.
    private struct MoveSourceGroup: Sendable {
        let sourceFolderID: UUID
        let sourceFolderPath: String
        let sourceUidValidity: UInt32?
        let messageIDs: [UUID]
        let uids: [UInt32]
    }

    private func sameAccountMove(ctx: MoveContext, targetFolderID: UUID) async {
        // §9.1: messages in a single move may originate from different source
        // folders (multi-select across a search result or the Unified Inbox).
        // Group by source folder so each MOVE SELECTs the right mailbox and
        // applies only that folder's UIDs — never the first folder's UIDs to
        // everyone (which would MOVE/lose foreign UIDs on the server).
        let groups: [MoveSourceGroup] = (try? await pool.read { db -> [MoveSourceGroup] in
            let bySource = Dictionary(grouping: ctx.messages, by: \.folderID)
            return try bySource.compactMap { folderID, msgs -> MoveSourceGroup? in
                guard let folder = try Folder.fetchOne(db, key: folderID) else { return nil }
                return MoveSourceGroup(
                    sourceFolderID: folderID,
                    sourceFolderPath: folder.path,
                    sourceUidValidity: folder.uidValidity,
                    messageIDs: msgs.map(\.id),
                    uids: msgs.map(\.uid)
                )
            }
        }) ?? []
        guard !groups.isEmpty else { return }

        // IDLE gate (§9.14): cover every source folder + target during bulk move
        let gatedFolderIDs = Set(groups.map(\.sourceFolderID)).union([targetFolderID])
        for fid in gatedFolderIDs { bulkOpFolderIDs.insert(fid) }
        defer {
            for fid in gatedFolderIDs { bulkOpFolderIDs.remove(fid) }
            Task { [weak self] in
                for fid in gatedFolderIDs { await self?.drainPendingIdleEvents(for: fid) }
            }
        }

        // Optimistic local update — all selected rows point at the target now.
        let allIDs = groups.flatMap(\.messageIDs)
        try? await pool.write { db in
            let placeholders = allIDs.map { _ in "?" }.joined(separator: ",")
            try db.execute(
                sql: "UPDATE messages SET folder_id = ? WHERE id IN (\(placeholders))",
                arguments: StatementArguments([targetFolderID] + allIDs)
            )
        }

        let account = ctx.sourceAccount
        let targetPath = ctx.targetFolder.path
        // §9.5: serialize the whole IMAP section on the per-account socket so a
        // concurrent sync/IDLE flow can't interleave SELECT A → SELECT B →
        // MOVE-in-B. NOT reentrant — only top-level entry points wrap.
        try? await runSerializedPerAccount(account.id) { [weak self] in
            guard let self else { return }
            let imap = self.getOrCreateIMAPService(for: account)
            for group in groups {
                do {
                    if await !imap.isConnected { try await imap.connect() }
                    _ = try await imap.selectFolder(group.sourceFolderPath)
                    let uidMap = try await imap.moveMessages(uids: group.uids, to: targetPath)
                    // RFC 4315 COPYUID: the server told us each message's real UID
                    // in the target. Write it now instead of leaving the row under
                    // the target folder_id carrying its source UID — that window
                    // let a flag change address the wrong message by UID, and could
                    // collide with an existing target row on UNIQUE(folder_id, uid).
                    // Servers without UIDPLUS return nil; those still rely on the
                    // Message-ID pseudo-key rewrite during the resync below.
                    await self.applyMovedUIDs(
                        uidMap, group: group, targetFolderID: targetFolderID
                    )
                } catch {
                    for uid in group.uids {
                        let action = PendingAction(
                            id: UUID(), type: .move, accountID: account.id,
                            sourceFolderPath: group.sourceFolderPath,
                            targetFolderPath: targetPath,
                            messageUID: uid, sourceUidValidity: group.sourceUidValidity,
                            payload: nil, status: .pending,
                            attemptCount: 0, lastError: nil, createdAt: Date()
                        )
                        try? await self.offlineQueue?.enqueue(action)
                    }
                    LogService.log(.warning, .sync, "Move queued for retry", detail: "\(error)")
                }
            }
        }

        // Thunderbird parity (nsImapUndoTxn.cpp:349-410): optimistic rows still
        // carry source UIDs under the target folder_id; resync target so server-
        // assigned UIDs arrive via QRESYNC/CONDSTORE and persistHeaders matches
        // them in place by Message-ID.
        Task { [weak self] in
            await self?.syncFolderIfNeeded(folderID: targetFolderID)
        }
    }

    /// Write the server-assigned target UIDs onto the optimistically moved rows.
    /// One transaction (§12: never a write per row), but each statement is
    /// tolerated individually — a UNIQUE(folder_id, uid) collision, where the
    /// target already holds a row at that UID from an earlier sync, must not
    /// sink the remaining messages in the batch.
    private func applyMovedUIDs(
        _ uidMap: [UInt32: UInt32]?,
        group: MoveSourceGroup,
        targetFolderID: UUID
    ) async {
        guard let uidMap else { return }
        var applied = 0
        do {
            try await pool.write { db in
                for (messageID, sourceUID) in zip(group.messageIDs, group.uids) {
                    guard let destUID = uidMap[sourceUID] else { continue }
                    do {
                        try db.execute(
                            sql: "UPDATE messages SET uid = ? WHERE id = ?",
                            arguments: [destUID, messageID]
                        )
                        applied += 1
                    } catch {
                        LogService.log(.debug, .sync, "COPYUID row skipped",
                                       detail: "uid \(sourceUID)→\(destUID): \(error)")
                    }
                }
            }
        } catch {
            LogService.log(.warning, .sync, "COPYUID apply failed", detail: "\(error)")
            return
        }
        LogService.log(.debug, .sync, "Applied COPYUID mapping",
                       detail: "\(applied)/\(group.uids.count) rows folder=\(targetFolderID)")
    }

    // MARK: - Cross-account move (FETCH raw → APPEND → DELETE)

    private func crossAccountMove(ctx: MoveContext, targetFolderID: UUID) async {
        let sourceAccount = ctx.sourceAccount
        let targetAccount = ctx.targetAccount
        let sourcePath = ctx.sourceFolder.path
        let targetPath = ctx.targetFolder.path
        let sourceUidValidity = ctx.sourceFolder.uidValidity
        let messages = ctx.messages

        // §9.5: serialize source-account IMAP work on its socket so a concurrent
        // sync/IDLE flow can't interleave SELECT/DELETE on the source.
        try? await runSerializedPerAccount(sourceAccount.id) { [weak self] in
            guard let self else { return }
            let srcImap = self.getOrCreateIMAPService(for: sourceAccount)
            let dstImap = self.getOrCreateIMAPService(for: targetAccount)
            do {
                if await !srcImap.isConnected {
                    await self.wireTokenProvider(for: sourceAccount, imap: srcImap)
                    try await srcImap.connect()
                }
                if await !dstImap.isConnected {
                    await self.wireTokenProvider(for: targetAccount, imap: dstImap)
                    try await dstImap.connect()
                }
                _ = try await srcImap.selectFolder(sourcePath)

                for msg in messages {
                    // Phase 1 — copy to target (FETCH + APPEND). On failure
                    // nothing reached the target: leave the source untouched and
                    // skip (queuing `.move` would replay as a same-account MOVE
                    // on the source into a foreign path).
                    do {
                        let rawData = try await srcImap.fetchRawMessage(uid: msg.uid)
                        var flags: [Flag] = []  // preserve all RFC 3501 + keyword flags
                        if msg.isRead { flags.append(.seen) }
                        if msg.isFlagged { flags.append(.flagged) }
                        if msg.isAnswered { flags.append(.answered) }
                        if msg.isDraft { flags.append(.draft) }
                        if msg.isForwarded { flags.append(.custom("$Forwarded")) }

                        // APPEND to destination as exact bytes (8-bit safe).
                        try await dstImap.appendRawData(
                            rawData, to: targetPath, flags: flags, date: msg.date
                        )
                    } catch {
                        LogService.log(.warning, .sync,
                            "Cross-account move: copy failed, left in place",
                            detail: "uid=\(msg.uid) \(error)")
                        continue
                    }

                    // Phase 2 — APPEND confirmed; only the source delete remains.
                    // Queue `.delete` (NOT `.move`: re-APPEND would duplicate the
                    // target). Idempotent on the source; local row dropped
                    // optimistically, reconcile missing-recovery covers a
                    // permanent delete failure.
                    do {
                        try await srcImap.deleteMessages(uids: [msg.uid])
                    } catch {
                        let action = PendingAction(
                            id: UUID(), type: .delete, accountID: sourceAccount.id,
                            sourceFolderPath: sourcePath, targetFolderPath: nil,
                            messageUID: msg.uid, sourceUidValidity: sourceUidValidity,
                            payload: nil, status: .pending,
                            attemptCount: 0, lastError: nil, createdAt: Date()
                        )
                        try? await self.offlineQueue?.enqueue(action)
                        LogService.log(.warning, .sync,
                            "Cross-account move: source delete queued",
                            detail: "uid=\(msg.uid) \(error)")
                    }

                    // Local cleanup (optimistic — the copy is in target).
                    try? await self.pool.write { db in
                        try db.execute(sql: "DELETE FROM messages WHERE id = ?", arguments: [msg.id])
                    }
                }

                LogService.log(.info, .sync, "Cross-account move: \(messages.count) messages",
                               detail: "\(sourceAccount.email) → \(targetAccount.email)")
            } catch {
                LogService.log(.error, .sync, "Cross-account move failed", detail: "\(error)")
            }
        }
    }
}
