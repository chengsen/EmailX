//
//  MCPTools+Actions.swift
//  MyEmail
//
//  Mutating MCP tools: archive, flags, move. They go through the same
//  services the UI uses, so IMAP batching, the optimistic-UI cooldown and
//  the offline queue all apply — and archive/move register undo, so a wrong
//  call is one ⌘Z away.
//
//  Deletion is deliberately absent: message text is untrusted input, and a
//  destructive action taken on instructions hidden in an email should not be
//  one tool call away. Archive is the reversible equivalent.
//

import Foundation
import GRDB

extension MCPServerService {

    /// Message ids shared by every action tool, validated against the store so
    /// a typo fails loudly instead of silently acting on fewer messages.
    private func messageIDs(from arguments: JSONValue) async throws -> [UUID] {
        guard let raw = arguments["message_ids"]?.stringArrayValue, !raw.isEmpty else {
            throw MCPToolError.invalidParams("message_ids must list at least one id")
        }
        let ids = try raw.map { value -> UUID in
            guard let id = UUID(uuidString: value) else {
                throw MCPToolError.invalidParams("\(value) is not a UUID")
            }
            return id
        }
        let known = try await DatabaseService.shared.pool.read { db in
            try UUID.fetchSet(db, sql: """
                SELECT id FROM messages WHERE id IN (\(databaseQuestionMarks(count: ids.count)))
                """, arguments: StatementArguments(ids))
        }
        let missing = ids.filter { !known.contains($0) }
        guard missing.isEmpty else {
            throw MCPToolError.notFound("\(missing.count) of \(ids.count) message ids")
        }
        return ids
    }

    // MARK: - Archive

    func archiveMessages(_ arguments: JSONValue) async throws -> JSONValue {
        let ids = try await messageIDs(from: arguments)
        await undo.archiveMessages(ids, undoManager: nil)
        return .object(["archived": .int(ids.count)])
    }

    // MARK: - Flags

    func setFlags(_ arguments: JSONValue) async throws -> JSONValue {
        let ids = try await messageIDs(from: arguments)
        let read = arguments["read"]?.boolValue
        let flagged = arguments["flagged"]?.boolValue
        guard read != nil || flagged != nil else {
            throw MCPToolError.invalidParams("Set read, flagged, or both")
        }

        if let read {
            if read {
                await undo.markAsRead(ids, undoManager: nil)
            } else {
                await undo.markAsUnread(ids, undoManager: nil)
            }
        }
        if let flagged {
            await undo.setFlagged(ids, flagged: flagged, undoManager: nil)
        }
        return .compactObject([
            "updated": .int(ids.count),
            "read": read.map { .bool($0) },
            "flagged": flagged.map { .bool($0) }
        ])
    }

    // MARK: - Move

    func moveMessages(_ arguments: JSONValue) async throws -> JSONValue {
        let ids = try await messageIDs(from: arguments)
        let folderID = try arguments.requiredUUID("folder_id")

        let folder = try await DatabaseService.shared.pool.read { db in
            try Folder.fetchOne(db, key: folderID)
        }
        guard let folder else {
            throw MCPToolError.notFound("folder \(folderID.uuidString)")
        }
        // A cross-account move is a copy-and-delete the sync layer does not do;
        // fail here rather than let it half-happen.
        let foreign = try await DatabaseService.shared.pool.read { db in
            try Int.fetchOne(db, sql: """
                SELECT COUNT(*) FROM messages
                WHERE id IN (\(databaseQuestionMarks(count: ids.count))) AND account_id <> ?
                """, arguments: StatementArguments(ids) + [folder.accountID]) ?? 0
        }
        guard foreign == 0 else {
            throw MCPToolError.rejected(
                "\(foreign) message(s) belong to a different account than \(folder.displayName)"
            )
        }

        await sync.moveMessages(ids, to: folderID)
        return .object([
            "moved": .int(ids.count),
            "to": .string(folder.displayName)
        ])
    }
}

/// `?,?,?` for an IN clause of `count` bound values.
nonisolated func databaseQuestionMarks(count: Int) -> String {
    Array(repeating: "?", count: count).joined(separator: ",")
}
