import Foundation
import GRDB
import Observation

// Only the app dependencies are isolated; AppState, queries, threading and
// sort implementations below are compiled unchanged from production sources.
enum SearchScope { case currentFolder }
enum SpecialUse: String, Decodable { case inbox, sent, drafts }
enum MoreMessages: String, Decodable { case `true`, `false`, unknown }
struct Folder: FetchableRecord, TableRecord, Decodable, Sendable {
    static let databaseTableName = "folders"
    var id: UUID
    var specialUse: SpecialUse?
    var moreMessages: MoreMessages
    enum CodingKeys: String, CodingKey { case id; case specialUse = "special_use"; case moreMessages = "more_messages" }
}
struct Account: FetchableRecord, TableRecord, Decodable, Sendable { static let databaseTableName = "accounts"; var id: UUID; var name: String }
enum LogService {
    enum Level { case debug, error }
    enum Category { case db }
    static func log(_ level: Level, _ category: Category, _ title: String, detail: String) { }
}
final class DatabaseService: @unchecked Sendable {
    static let shared = DatabaseService()
    let path = FileManager.default.temporaryDirectory.appendingPathComponent("emailx-list-\(UUID()).sqlite").path
    lazy var pool = try! DatabasePool(path: path)
}

final class ChangeCounter: @unchecked Sendable {
    private let lock = NSLock()
    private var value = 0
    func changed() { lock.lock(); value += 1; lock.unlock() }
    var count: Int { lock.lock(); defer { lock.unlock() }; return value }
}

@main struct Probe {
    @MainActor static func wait(_ condition: () -> Bool) async throws {
        for _ in 0..<300 {
            if condition() { return }
            try await Task.sleep(for: .milliseconds(20))
        }
        fatalError("Observation did not deliver expected state")
    }
    @MainActor static func main() async throws {
        let db = DatabaseService.shared.pool
        let folder = UUID(), other = UUID(), account = UUID()
        defer { for suffix in ["", "-shm", "-wal"] { try? FileManager.default.removeItem(atPath: DatabaseService.shared.path + suffix) } }
        try await db.write { db in
            try db.execute(sql: "CREATE TABLE messages (id BLOB PRIMARY KEY, uid INTEGER, folder_id BLOB, account_id BLOB, date REAL, subject TEXT, from_name TEXT, from_address TEXT, to_addresses TEXT, size INTEGER, preview TEXT, is_read INTEGER, is_flagged INTEGER, is_answered INTEGER, has_attachments INTEGER, interaction_score INTEGER, thread_id TEXT, message_id TEXT, in_reply_to TEXT, \"references\" TEXT)")
            for n in 0..<2400 {
                try db.execute(sql: "INSERT INTO messages VALUES (?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?)", arguments: [UUID(), n + 1, folder, account, Double(n), "Subject \(2400 - n)", "Sender \(n)", "sender@test", "[\"Recipient \(2400 - n) <target@test>\"]", n, String(repeating: "p", count: 500), 0, 0, 0, 0, 0, n < 900 ? "long-thread" : "single-\(n)", "message-\(n)", nil, "[]"])
            }
            try db.execute(sql: "INSERT INTO messages VALUES (?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?)", arguments: [UUID(), 1, other, account, 9000.0, "Other folder", "Other", "other@test", "[]", 1, "other", 0, 0, 0, 0, 0, "other-thread", "other-message", nil, "[]"])
        }
        let state = AppState()
        state.isThreaded = true
        state.selectedSidebarItem = .folder(folder)
        try await wait { state.messageItems.count == 500 }
        let all = try await db.read { try MessageListItem.fetchAll($0, sql: MessageListItem.listSQL + " WHERE m.folder_id = ? ORDER BY m.date DESC, m.id ASC", arguments: [folder]) }
        let groups = ThreadingService.group(all)
        let expectedFirst = Set(groups.prefix(500).flatMap { $0.messages.map(\.id) })
        precondition(Set(state.messageItems.map(\.id)) == expectedFirst)
        precondition(state.hasMoreLocalMessages)
        let changed = state.messageItems[0].id
        try await db.write { try $0.execute(sql: "UPDATE messages SET is_read=1, interaction_score=7 WHERE id=?", arguments: [changed]) }
        try await wait { state.messageItems.first(where: { $0.id == changed })?.isRead == true }
        precondition(state.messageItems.first(where: { $0.id == changed })?.interactionScore == 0)
        let scoreChanges = ChangeCounter()
        withObservationTracking { _ = state.messageItems } onChange: { scoreChanges.changed() }
        try await db.write { try $0.execute(sql: "UPDATE messages SET interaction_score=8 WHERE id=?", arguments: [changed]) }
        try await Task.sleep(for: .milliseconds(250))
        precondition(scoreChanges.count == 0, "Score-only update refreshed metadata")
        precondition(state.loadMoreLocalMessages())
        try await wait { state.currentLocalPage == 2 && Set(state.messageItems.map(\.id)) == Set(groups.dropFirst(500).prefix(500).flatMap { $0.messages.map(\.id) }) }
        state.showPreviousLocalPage()
        try await wait { state.currentLocalPage == 1 && Set(state.messageItems.map(\.id)) == expectedFirst }
        while state.hasMoreLocalMessages { state.loadMoreLocalMessages(); try await Task.sleep(for: .milliseconds(150)) }
        precondition(state.messageItems.contains(where: { $0.uid == 1 }))
        precondition(ThreadingService.group(state.messageItems).contains(where: { $0.count == 900 }))
        print("PASS complete thread count, older reachability, fixed pages, flag updates, score excluded")
        state.isThreaded = false
        state.messageSort = MessageSort(column: .date, order: .asc)
        try await wait { state.messageItems.count == 500 && state.messageItems.contains(where: { $0.uid == 1 }) }
        state.messageSort = MessageSort(column: .subject, order: .asc)
        let sortedFirst = Set(all.sorted(by: state.messageSort, isSentOrDrafts: false).prefix(500).map(\.id))
        try await wait { Set(state.messageItems.map(\.id)) == sortedFirst }
        state.messageSort = MessageSort(column: .size, order: .desc)
        let sizeFirst = Set(all.sorted(by: state.messageSort, isSentOrDrafts: false).prefix(500).map(\.id))
        try await wait { Set(state.messageItems.map(\.id)) == sizeFirst }
        state.messageSort = MessageSort(column: .fromTo, order: .asc)
        let senderFirst = Set(all.sorted(by: state.messageSort, isSentOrDrafts: false).prefix(500).map(\.id))
        try await wait { Set(state.messageItems.map(\.id)) == senderFirst }
        state.selectedFolder = Folder(id: folder, specialUse: .sent, moreMessages: .unknown)
        state.messageSort = MessageSort(column: .fromTo, order: .desc)
        let recipientFirst = Set(all.sorted(by: state.messageSort, isSentOrDrafts: true).prefix(500).map(\.id))
        try await wait { Set(state.messageItems.map(\.id)) == recipientFirst }
        state.messageSort = .default
        try await wait { Set(state.messageItems.map(\.id)) == expectedFirst }
        let pinned = state.messageItems.last!.id
        state.selectedMessageIDs = [pinned]
        let incoming = UUID()
        try await db.write { try $0.execute(sql: "INSERT INTO messages VALUES (?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?)", arguments: [incoming, 10000, folder, account, 10000.0, "Incoming", "New", "new@test", "[]", 1, "new", 0, 0, 0, 0, 0, "incoming-thread", "incoming-message", nil, "[]"]) }
        try await wait { state.messageItems.contains(where: { $0.id == incoming }) && state.messageItems.count == 501 }
        precondition(state.selectedMessageIDs == [pinned])
        state.selectedMessageIDs = []
        print("PASS sender/recipient sorts, incoming mail immediate, selected boundary row retained")
        state.selectedSidebarItem = .folder(other)
        state.selectedSidebarItem = .folder(folder)
        state.selectedSidebarItem = .folder(other)
        try await wait { state.messageItems.count == 1 && state.messageItems[0].folderID == other }
        try await Task.sleep(for: .milliseconds(300))
        precondition(state.messageItems.allSatisfy { $0.folderID == other })
        state.stopObservingMessages()
        print("PASS global date/subject/size sorting, rapid folder switch excludes stale callbacks")
    }
}
