//
//  SyncService+GmailAttributes.swift
//  MyEmail
//
//  Post-header-sync enrichment of Gmail-native attributes (X-GM-EXT-1):
//  writes the authoritative conversation id (X-GM-THRID) into `thread_id`
//  so JWZ threading groups Gmail messages the server considers one thread,
//  and records X-GM-MSGID (stable per-account message identity) for the
//  future cross-folder body-dedup. Best-effort — failures never block sync.
//

import Foundation
import GRDB
import SwiftMail

extension SyncService {

    /// Backfill Gmail attributes for messages in a folder that lack them
    /// (`gm_msgid IS NULL`). No-op on non-Gmail servers. Folder must already
    /// be SELECTed on `imap`. Bounded per pass — remaining rows are picked up
    /// by subsequent syncs.
    func enrichGmailAttributes(folderID: UUID, imap: IMAPService, limit: Int = 200) async {
        guard await imap.supportsGmailExtensions() else { return }

        let targets: [(id: UUID, uid: UInt32)] = (try? await pool.read { db in
            try Row.fetchAll(db, sql: """
                SELECT id, uid FROM messages
                WHERE folder_id = ? AND uid > 0 AND gm_msgid IS NULL
                ORDER BY date DESC LIMIT ?
                """, arguments: [folderID, limit])
            .map { (id: $0["id"] as UUID, uid: $0["uid"] as UInt32) }
        }) ?? []

        guard !targets.isEmpty else { return }

        do {
            let attrs = try await imap.fetchGmailAttributes(uids: targets.map(\.uid))
            guard !attrs.isEmpty else { return }

            try? await pool.write { db in
                for target in targets {
                    guard let attr = attrs[target.uid] else { continue }
                    // X-GM-MSGID/THRID are 64-bit unsigned — store as TEXT to
                    // dodge Int64 overflow. THRID overwrites the locally
                    // computed thread_id: it's authoritative Gmail grouping,
                    // and JWZ still prefers References links when present, so
                    // this only fills the gaps References can't.
                    try db.execute(sql: """
                        UPDATE messages SET gm_msgid = ?, thread_id = ? WHERE id = ?
                        """, arguments: [String(attr.messageID), String(attr.threadID), target.id])
                }
            }

            LogService.log(.debug, .sync,
                "Enriched \(attrs.count) Gmail attrs", detail: "folder=\(folderID)")
        } catch {
            LogService.log(.debug, .sync, "Gmail attr enrich skipped", detail: "\(error)")
        }
    }
}
