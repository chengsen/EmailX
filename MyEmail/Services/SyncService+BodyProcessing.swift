// MIME decoding and attachment filesystem work run on the concurrent executor.
// The caller retains its per-account command lock and owns database commits.

import Foundation
import SwiftEmailParser

extension SyncService {
    struct ParsedBody: Sendable {
        let headers: ParsedHeaders
        let text: String?
        let html: String?
        let userAgent: String?
        let isEncrypted: Bool
        let attachments: [SwiftEmailParser.Attachment]
    }

    struct ParsedHeaders: Sendable {
        let subject: String?
        let from: EmailAddress?
        let to: [String]
        let cc: [String]
        let bcc: [String]
        let date: Date?
        let messageID: String?
        let inReplyTo: String?
        let references: [String]
    }

    nonisolated private static func extractHeaders(_ email: EmailMessage) -> ParsedHeaders {
        ParsedHeaders(subject: email.subject, from: email.from.first,
                      to: email.to.map(\.formatted), cc: email.cc.map(\.formatted),
                      bcc: email.bcc.map(\.formatted), date: email.date,
                      messageID: email.messageId, inReplyTo: email.inReplyTo,
                      references: email.references)
    }

    @concurrent nonisolated static func parseHeaders(_ rawData: Data) async throws -> ParsedHeaders {
        extractHeaders(try EmailMessage(data: rawData))
    }

    // Ponytail: decoding stays whole-message for server compatibility; a bounded
    // streaming parser is warranted only if measured large-message peaks require it.
    @concurrent nonisolated static func parseBody(_ rawData: Data, includeEncryptedAttachments: Bool = true) async throws -> ParsedBody {
        let email = try EmailMessage(data: rawData)
        let text = email.textBody
        let userAgent = ["User-Agent", "X-Mailer", "X-Mail-Agent", "X-Newsreader"]
            .lazy.compactMap { email.header($0)?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .first { !$0.isEmpty }
        let encrypted = email.isEncrypted
            || (text ?? "").contains("-----BEGIN PGP MESSAGE-----")
        return ParsedBody(headers: extractHeaders(email), text: text, html: email.htmlBody,
                          userAgent: userAgent, isEncrypted: encrypted,
                          attachments: encrypted && !includeEncryptedAttachments ? [] : email.attachments)
    }

    @concurrent nonisolated static func writeAttachments(
        _ attachments: [SwiftEmailParser.Attachment], directory: URL, messageID: UUID
    ) async throws -> [MyEmail.Attachment] {
        let base = directory
        try FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)

        var records: [MyEmail.Attachment] = []
        var usedFilenames: Set<String> = []
        for att in attachments {
            let rawFilename = att.filename ?? (att.contentId ?? "attachment-\(UUID().uuidString.prefix(8))")
            var filename = sanitizeFilename(rawFilename)
            // Avoid collisions within same message
            if usedFilenames.contains(filename) {
                filename = "\(UUID().uuidString.prefix(8))-\(filename)"
            }
            usedFilenames.insert(filename)

            let fileURL = base.appendingPathComponent(filename)
            try att.data.write(to: fileURL)
            setQuarantine(on: fileURL)

            LogService.log(.debug, .sync, "Saved attachment",
                           detail: "file=\(filename) inline=\(att.isInline) cid=\(att.contentId ?? "nil") size=\(att.data.count) path=\(fileURL.path)")

            records.append(MyEmail.Attachment(
                id: UUID(), partID: att.contentId ?? "",
                filename: filename, mimeType: att.mimeType,
                size: att.size, contentID: att.contentId,
                isInline: att.isInline, localPath: fileURL.path,
                messageID: messageID
            ))
        }

        return records
    }

    @concurrent nonisolated static func writeAttachment(
        _ data: Data, filename: String, directory: URL
    ) async throws -> URL {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let fileURL = directory.appendingPathComponent(filename)
        try data.write(to: fileURL)
        setQuarantine(on: fileURL)
        return fileURL
    }

    @concurrent nonisolated static func removeAttachmentDirectories(_ directories: [URL]) async {
        for directory in directories {
            try? FileManager.default.removeItem(at: directory)
        }
    }

    /// Strip path separators, .., control chars; limit length.
    nonisolated static func sanitizeFilename(_ raw: String) -> String {
        var name = raw
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "\\", with: "_")
            .replacingOccurrences(of: "..", with: "_")
            .replacingOccurrences(of: "\0", with: "")
        name = String(name.unicodeScalars.filter { $0.value >= 0x20 })
        if name.count > 255 { name = String(name.prefix(255)) }
        if name.isEmpty { name = UUID().uuidString }
        return name
    }

    /// §21: tag a freshly-written attachment with `com.apple.quarantine` so
    /// Gatekeeper / LaunchServices treat it like a downloaded file — the user
    /// gets the standard "downloaded from the Internet" warning before opening
    /// an executable or document macro. Best-effort: failures are logged, not
    /// fatal (a missing xattr only loses the warning, never blocks the save).
    nonisolated static func setQuarantine(on url: URL) {
        // Format: flags;hexTimestamp;agentName;UUID  (LSQuarantine).
        let flags = "0083"
        let ts = String(format: "%x", UInt32(Date().timeIntervalSince1970))
        let value = "\(flags);\(ts);MyEmail;\(UUID().uuidString)"
        let name = "com.apple.quarantine"
        url.withUnsafeFileSystemRepresentation { path in
            guard let path else { return }
            value.withCString { cStr in
                if setxattr(path, name, cStr, strlen(cStr), 0, 0) != 0 {
                    LogService.log(.debug, .sync, "Quarantine xattr failed",
                                   detail: "\(url.lastPathComponent) errno=\(errno)")
                }
            }
        }
    }
}
