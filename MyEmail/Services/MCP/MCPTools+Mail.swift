//
//  MCPTools+Mail.swift
//  MyEmail
//
//  Mail-facing MCP tools: accounts, folders, search, message read, send.
//  Reads go straight to the local store — the agent sees exactly what is
//  synced, no IMAP round-trip. Sending is the one outbound action and it
//  always asks the user first.
//

import AppKit
import Foundation
import GRDB

extension MCPServerService {

    // MARK: - Accounts

    func listAccounts() async throws -> JSONValue {
        let accounts = try await DatabaseService.shared.pool.read { db in
            try Account.order(Column("sort_order")).fetchAll(db)
        }
        return .object(["accounts": .array(accounts.map { account in
            JSONValue.compactObject([
                "id": .string(account.id.uuidString),
                "name": .string(account.name),
                "email": .string(account.email),
                "enabled": .bool(account.isEnabled),
                "auth_type": .string(account.authType.rawValue),
                "auth_state": .string(String(describing: account.authState)),
                "imap_host": .string(account.imapHost),
                "smtp_host": .string(account.smtpHost)
            ])
        })])
    }

    // MARK: - Folders

    func listFolders(_ arguments: JSONValue) async throws -> JSONValue {
        let accountID = arguments["account_id"]?.uuidValue
        let folders = try await DatabaseService.shared.pool.read { db in
            var request = Folder.all()
            if let accountID {
                request = request.filter(Column("account_id") == accountID)
            }
            return try request.order(Column("path")).fetchAll(db)
        }
        return .object(["folders": .array(folders.map { folder in
            JSONValue.compactObject([
                "id": .string(folder.id.uuidString),
                "account_id": .string(folder.accountID.uuidString),
                "path": .string(folder.path),
                "name": .string(folder.name),
                "special_use": folder.specialUse.map { .string($0.rawValue) },
                "total": .int(folder.totalCount),
                "unread": .int(folder.unreadCount),
                "uid_validity": folder.uidValidity.map { .int(Int($0)) },
                "uid_next": folder.uidNext.map { .int(Int($0)) }
            ])
        })])
    }

    // MARK: - Search

    func searchMessages(_ arguments: JSONValue) async throws -> JSONValue {
        let limit = min(max(arguments["limit"]?.intValue ?? 50, 1), 500)
        let folderID = arguments["folder_id"]?.uuidValue
        let accountID = arguments["account_id"]?.uuidValue

        let query = SearchQuery(
            freetext: arguments["text"]?.stringValue.map { [$0] } ?? [],
            from: arguments["from"]?.stringValue.map { [$0] } ?? [],
            to: arguments["to"]?.stringValue.map { [$0] } ?? [],
            subject: arguments["subject"]?.stringValue,
            before: arguments["before"]?.dateValue,
            after: arguments["since"]?.dateValue,
            isFilter: isFilter(from: arguments),
            hasFilter: arguments["has_attachments"]?.boolValue == true ? .attachment : nil
        )
        guard !query.isEmpty else {
            throw MCPToolError.invalidParams("Give at least one filter")
        }

        let scope: SearchScope = folderID != nil ? .currentFolder
            : (accountID != nil ? .currentAccount : .allAccounts)
        let results = try await sync.searchLocal(
            query: query, scope: scope, folderID: folderID, accountID: accountID
        )

        return .object([
            "count": .int(min(results.count, limit)),
            "truncated": .bool(results.count > limit),
            "messages": .array(results.prefix(limit).map(Self.summary))
        ])
    }

    /// `unread` and `flagged` map onto the same single-slot filter the UI uses,
    /// so only one of them can apply per query — unread wins.
    private func isFilter(from arguments: JSONValue) -> SearchQuery.IsFilter? {
        if let unread = arguments["unread"]?.boolValue {
            return unread ? .unread : .read
        }
        if let flagged = arguments["flagged"]?.boolValue {
            return flagged ? .flagged : nil
        }
        return nil
    }

    nonisolated static func summary(_ item: MessageListItem) -> JSONValue {
        .compactObject([
            "id": .string(item.id.uuidString),
            "uid": .int(Int(item.uid)),
            "subject": .string(item.subject),
            "from": .string(item.fromName.map { "\($0) <\(item.fromAddress)>" }
                ?? item.fromAddress),
            "to": .strings(item.toAddresses),
            "date": .string(ISO8601DateFormatter().string(from: item.date)),
            "preview": .string(item.preview),
            "unread": .bool(!item.isRead),
            "flagged": .bool(item.isFlagged),
            "has_attachments": .bool(item.hasAttachments),
            "size": .int(item.size),
            "folder_id": .string(item.folderID.uuidString),
            "account_id": .string(item.accountID.uuidString)
        ])
    }

    // MARK: - Single message

    func getMessage(_ arguments: JSONValue) async throws -> JSONValue {
        guard let id = arguments["message_id"]?.uuidValue else {
            throw MCPToolError.invalidParams("message_id must be a UUID")
        }
        guard let message = try await sync.loadFullMessage(id: id) else {
            throw MCPToolError.notFound("message \(id.uuidString)")
        }
        let attachments = try await DatabaseService.shared.pool.read { db in
            try Attachment.filter(Column("message_id") == id).fetchAll(db)
        }

        var payload: [String: JSONValue?] = [
            "id": .string(message.id.uuidString),
            "uid": .int(Int(message.uid)),
            "message_id_header": message.messageID.map { .string($0) },
            "in_reply_to": message.inReplyTo.map { .string($0) },
            "references": .strings(message.references),
            "subject": .string(message.subject),
            "from": .string(message.fromName.map { "\($0) <\(message.fromAddress)>" }
                ?? message.fromAddress),
            "to": .strings(message.toAddresses),
            "cc": .strings(message.ccAddresses),
            "date": .string(ISO8601DateFormatter().string(from: message.date)),
            "unread": .bool(!message.isRead),
            "flagged": .bool(message.isFlagged),
            "size": .int(message.size),
            "folder_id": .string(message.folderID.uuidString),
            "account_id": .string(message.accountID.uuidString),
            "body_text": message.bodyText.map { .string($0) },
            "attachments": .array(attachments.map { attachment in
                JSONValue.compactObject([
                    "filename": .string(attachment.filename),
                    "mime_type": .string(attachment.mimeType),
                    "size": .int(attachment.size),
                    "inline": .bool(attachment.isInline),
                    "local_path": attachment.localPath.map { .string($0) }
                ])
            })
        ]
        if arguments["include_html"]?.boolValue == true {
            payload["body_html"] = message.bodyHTML.map { .string($0) }
        }
        return .compactObject(payload)
    }

    // MARK: - Send

    func sendMessage(_ arguments: JSONValue) async throws -> JSONValue {
        guard let to = arguments["to"]?.stringArrayValue, !to.isEmpty else {
            throw MCPToolError.invalidParams("to must list at least one address")
        }
        guard let subject = arguments["subject"]?.stringValue else {
            throw MCPToolError.invalidParams("subject is required")
        }
        guard let body = arguments["body"]?.stringValue else {
            throw MCPToolError.invalidParams("body is required")
        }
        let cc = arguments["cc"]?.stringArrayValue ?? []
        let bcc = arguments["bcc"]?.stringArrayValue ?? []

        let requestedID = arguments["account_id"]?.uuidValue
        let account = try await DatabaseService.shared.pool.read { db -> Account? in
            if let requestedID {
                return try Account.filter(Column("id") == requestedID).fetchOne(db)
            }
            return try Account.filter(Column("is_enabled") == true)
                .order(Column("sort_order")).fetchOne(db)
        }
        guard let account else {
            throw MCPToolError.notFound("account to send from")
        }

        guard confirmSend(
            account: account, to: to, cc: cc, bcc: bcc, subject: subject, body: body
        ) else {
            throw MCPToolError.rejected("The user declined to send this message.")
        }

        do {
            try await sync.sendMessage(
                from: account, to: to, cc: cc, bcc: bcc,
                subject: subject, textBody: body
            )
        } catch {
            throw MCPToolError.failed("Send failed: \(error.localizedDescription)")
        }
        return .object([
            "sent": .bool(true),
            "from": .string(account.email),
            "to": .strings(to)
        ])
    }

    /// Blocking approval prompt. The agent may be acting on instructions it
    /// read inside a message, so the user sees the actual recipients and text
    /// before anything is handed to SMTP.
    private func confirmSend(
        account: Account, to: [String], cc: [String], bcc: [String],
        subject: String, body: String
    ) -> Bool {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = String(localized: "Send this message on your behalf?")

        var lines = [
            String(format: String(localized: "From: %@"), account.email),
            String(format: String(localized: "To: %@"), to.joined(separator: ", "))
        ]
        if !cc.isEmpty {
            lines.append(String(format: String(localized: "Cc: %@"), cc.joined(separator: ", ")))
        }
        if !bcc.isEmpty {
            lines.append(String(format: String(localized: "Bcc: %@"), bcc.joined(separator: ", ")))
        }
        lines.append(String(format: String(localized: "Subject: %@"), subject))
        lines.append("")
        lines.append(body.count > 800 ? String(body.prefix(800)) + "…" : body)
        alert.informativeText = lines.joined(separator: "\n")

        alert.addButton(withTitle: String(localized: "Send"))
        alert.addButton(withTitle: String(localized: "Don't Send"))
        NSApp.activate(ignoringOtherApps: true)
        return alert.runModal() == .alertFirstButtonReturn
    }
}
