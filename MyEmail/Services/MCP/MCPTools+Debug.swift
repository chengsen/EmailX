//
//  MCPTools+Debug.swift
//  MyEmail
//
//  Diagnostic MCP tools. This is the half that makes the endpoint worth
//  having: an agent can read the live log buffer, take a state snapshot,
//  poke the database read-only and force a sync pass to reproduce a bug —
//  without the user relaying screenshots of the Debug Log panel.
//

import Foundation
import GRDB

extension MCPServerService {

    // MARK: - Logs

    func getLogs(_ arguments: JSONValue) -> JSONValue {
        let limit = min(max(arguments["limit"]?.intValue ?? 100, 1), 1000)
        let minLevel = arguments["level"]?.stringValue
            .flatMap(LogLevel.init(rawValue:)) ?? .debug
        let category = arguments["category"]?.stringValue
            .flatMap(LogCategory.init(rawValue:))
        let needle = arguments["contains"]?.stringValue?.lowercased()
        let cutoff = arguments["since_seconds"]?.intValue
            .map { Date().addingTimeInterval(-Double($0)) }

        let matched = LogService.shared.entries.reversed().lazy.filter { entry in
            guard entry.level >= minLevel else { return false }
            if let category, entry.category != category { return false }
            if let cutoff, entry.timestamp < cutoff { return false }
            if let needle {
                let haystack = (entry.message + " " + (entry.detail ?? "")).lowercased()
                guard haystack.contains(needle) else { return false }
            }
            return true
        }

        let entries = Array(matched.prefix(limit))
        let formatter = ISO8601DateFormatter()
        return .object([
            "count": .int(entries.count),
            "entries": .array(entries.map { entry in
                JSONValue.compactObject([
                    "time": .string(formatter.string(from: entry.timestamp)),
                    "level": .string(entry.level.rawValue),
                    "category": .string(entry.category.rawValue),
                    "message": .string(entry.message),
                    "detail": entry.detail.map { .string($0) }
                ])
            })
        ])
    }

    // MARK: - Status snapshot

    func getStatus() async throws -> JSONValue {
        let pool = DatabaseService.shared.pool
        let counts = try await pool.read { db -> [String: Int] in
            [
                "accounts": try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM accounts") ?? 0,
                "folders": try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM folders") ?? 0,
                "messages": try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM messages") ?? 0,
                "unread": try Int.fetchOne(
                    db, sql: "SELECT COUNT(*) FROM messages WHERE is_read = 0"
                ) ?? 0,
                "pending_actions": try Int.fetchOne(
                    db, sql: "SELECT COUNT(*) FROM pending_actions"
                ) ?? 0
            ]
        }
        let accounts = try await pool.read { db in
            try Account.order(Column("sort_order")).fetchAll(db)
        }
        let errorCount = LogService.shared.entries.count { $0.level == .error }

        return .object([
            "app_version": .string(Bundle.main.appVersionString),
            "is_syncing": .bool(sync.isSyncing),
            "is_online": .bool(sync.isOnline),
            "counts": .object(counts.mapValues { .int($0) }),
            "log_errors_in_buffer": .int(errorCount),
            "database_bytes": .int(databaseSizeBytes()),
            "accounts": .array(accounts.map { account in
                JSONValue.object([
                    "id": .string(account.id.uuidString),
                    "email": .string(account.email),
                    "enabled": .bool(account.isEnabled),
                    "auth_state": .string(String(describing: account.authState))
                ])
            })
        ])
    }

    private func databaseSizeBytes() -> Int {
        let url = URL.applicationSupportDirectory
            .appending(path: "MyEmail/db.sqlite")
        let size = try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize
        return size ?? 0
    }

    // MARK: - Read-only SQL

    func queryDatabase(_ arguments: JSONValue) async throws -> JSONValue {
        guard let rawSQL = arguments["sql"]?.stringValue else {
            throw MCPToolError.invalidParams("sql is required")
        }
        let sql = rawSQL.trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: ";"))
        let lowered = sql.lowercased()

        // GRDB's read connections are already read-only, so this only has to
        // stop the confusing cases: multiple statements, or a write that would
        // fail deep inside SQLite with an opaque message.
        guard lowered.hasPrefix("select") || lowered.hasPrefix("with") else {
            throw MCPToolError.rejected("Only SELECT statements are allowed")
        }
        guard !sql.contains(";") else {
            throw MCPToolError.rejected("Send a single statement")
        }

        let limit = min(max(arguments["limit"]?.intValue ?? 100, 1), 1000)
        let rows: [Row]
        do {
            rows = try await DatabaseService.shared.pool.read { db in
                try Row.fetchAll(db, sql: sql)
            }
        } catch {
            throw MCPToolError.failed("SQL error: \(error.localizedDescription)")
        }

        return .object([
            "row_count": .int(min(rows.count, limit)),
            "truncated": .bool(rows.count > limit),
            "rows": .array(rows.prefix(limit).map(Self.jsonRow))
        ])
    }

    nonisolated private static func jsonRow(_ row: Row) -> JSONValue {
        var object: [String: JSONValue] = [:]
        for name in row.columnNames {
            object[name] = jsonValue(row[name] as DatabaseValue)
        }
        return .object(object)
    }

    nonisolated private static func jsonValue(_ value: DatabaseValue) -> JSONValue {
        switch value.storage {
        case .null:            return .null
        case .int64(let raw):  return .number(Double(raw))
        case .double(let raw): return .number(raw)
        case .string(let raw): return .string(raw)
        case .blob(let data):
            // GRDB stores UUIDs as 16-byte blobs; without this every id
            // column comes back opaque and can't be fed to another tool.
            guard data.count == 16 else { return .string("<blob \(data.count) bytes>") }
            let raw = data.withUnsafeBytes { $0.loadUnaligned(as: uuid_t.self) }
            return .string(UUID(uuid: raw).uuidString)
        }
    }

    // MARK: - Forced sync

    func syncFolder(_ arguments: JSONValue) async throws -> JSONValue {
        if let folderID = try arguments.optionalUUID("folder_id") {
            await sync.syncFolderIfNeeded(folderID: folderID)
            return .object(["synced": .string(folderID.uuidString)])
        }

        let accountID = try arguments.optionalUUID("account_id")
        let account = try await DatabaseService.shared.pool.read { db -> Account? in
            if let accountID {
                return try Account.fetchOne(db, key: accountID)
            }
            return try Account.filter(Column("is_enabled") == true)
                .order(Column("sort_order")).fetchOne(db)
        }
        guard let account else { throw MCPToolError.notFound("account to sync") }

        let inbox = await sync.syncAccount(account)
        return .compactObject([
            "synced_account": .string(account.email),
            "inbox_folder_id": inbox.map { .string($0.id.uuidString) },
            "inbox_total": inbox.map { .int($0.totalCount) },
            "inbox_unread": inbox.map { .int($0.unreadCount) }
        ])
    }
}
