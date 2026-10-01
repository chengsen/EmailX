import Foundation

@MainActor final class SyncService {}
enum LogLevel: Sendable { case debug }
enum LogCategory: Sendable { case sync }
enum LogService {
    nonisolated static func log(_ level: LogLevel, _ category: LogCategory, _ message: String, detail: String? = nil) {}
}

@main struct Probe {
    @MainActor static func main() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("EmailX-mime-probe-\(UUID())")
        defer { try? FileManager.default.removeItem(at: root) }
        let payload = Data(repeating: 0xAB, count: 16 * 1024 * 1024)
        let encoded = payload.base64EncodedString(options: [.lineLength76Characters, .endLineWithCarriageReturn, .endLineWithLineFeed])
        let raw = Data(("From: Sender <sender@example.com>\r\nTo: recipient@example.com\r\nSubject: =?UTF-8?B?5rWL6K+V?=\r\nX-Mailer: Fixture Mail\r\nMIME-Version: 1.0\r\nContent-Type: multipart/mixed; boundary=test\r\n\r\n--test\r\nContent-Type: text/plain; charset=utf-8\r\n\r\nhello\r\n" + (1...2).map { index in "--test\r\nContent-Type: application/octet-stream; name=\"../same.bin\"\r\nContent-ID: <fixture-\(index)>\r\nContent-Disposition: \(index == 2 ? "inline" : "attachment"); filename=\"../same.bin\"\r\nContent-Transfer-Encoding: base64\r\n\r\n\(encoded)\r\n" }.joined() + "--test--\r\n").utf8)
        var ticks = 0
        let heartbeat = Task { @MainActor in
            while !Task.isCancelled {
                ticks += 1
                try? await Task.sleep(for: .milliseconds(1))
            }
        }
        defer { heartbeat.cancel() }
        let start = ContinuousClock.now
        let body = try await SyncService.parseBody(raw)
        let parseTicks = ticks
        precondition(parseTicks > 0, "MIME parser blocked MainActor")
        precondition(body.headers.subject == "测试")
        precondition(body.headers.from?.address == "sender@example.com")
        precondition(body.text?.trimmingCharacters(in: .whitespacesAndNewlines) == "hello")
        precondition(body.userAgent == "Fixture Mail")
        precondition(body.attachments.count == 2)
        precondition(body.attachments[0].isInline == false && body.attachments[1].isInline)
        precondition(body.attachments[1].contentId == "fixture-2")
        let records = try await SyncService.writeAttachments(body.attachments, directory: root, messageID: UUID())
        precondition(ticks > parseTicks, "Attachment IO blocked MainActor")
        precondition(Set(records.map(\.filename)).count == 2)
        for record in records {
            precondition(!record.filename.contains("/") && !record.filename.contains(".."))
            let path = record.localPath!
            let stored = try Data(contentsOf: URL(fileURLWithPath: path))
            precondition(stored == payload)
            let xattrSize = path.withCString { getxattr($0, "com.apple.quarantine", nil, 0, 0, 0) }
            precondition(xattrSize > 0, "quarantine missing")
        }
        let refetched = try await SyncService.writeAttachment(payload, filename: records[0].filename, directory: root)
        let storedAgain = try Data(contentsOf: refetched)
        precondition(storedAgain == payload)
        let blocker = root.appendingPathComponent("blocked")
        try Data().write(to: blocker)
        do {
            _ = try await SyncService.writeAttachment(payload, filename: "should-not-exist", directory: blocker)
            preconditionFailure("File IO error was swallowed")
        } catch {}
        let headers = try await SyncService.parseHeaders(raw)
        precondition(headers.subject == body.headers.subject)
        await SyncService.removeAttachmentDirectories([root])
        precondition(!FileManager.default.fileExists(atPath: root.path))
        print("PASS: 32 MiB binary MIME; subject/header/body; distinct sanitized filenames; exact bytes; CID/inline; quarantine; refetch; IO error; directory purge; MainActor heartbeat parse=\(parseTicks), total=\(ticks), elapsed=\(start.duration(to: .now))")
    }
}
