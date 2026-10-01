//
//  AppState.swift
//  MyEmail
//
//  @Observable, @MainActor. UI reads via `@Environment(AppState.self)`.
//  No ViewModels (§3.3).
//

import Foundation
import GRDB
import Observation

// MARK: - SidebarItem

enum SidebarItem: Hashable {
    case unifiedInbox
    case folder(UUID)
}

// MARK: - AppState

@Observable
@MainActor
final class AppState {
    // MARK: - Selection

    var selectedFolder: Folder?
    var selectedMessageIDs: Set<UUID> = []

    /// First selected message — used for detail pane display.
    var selectedMessageID: UUID? { selectedMessageIDs.first }

    /// Row order as actually rendered by the message table (threading + sort
    /// applied). Published by `MessageListTable`; read only by
    /// `pruneSelection` to advance the selection when rows vanish.
    var visibleOrder: [UUID] = []
    private(set) var sidebarSelectionGeneration = 0
    var selectedSidebarItem: SidebarItem? {
        didSet { sidebarSelectionChanged() }
    }

    // MARK: - Lists (MessageListItem projection — §5.4, bug 9.4)

    var messageItems: [MessageListItem] = [] {
        didSet { pruneSelection() }
    }
    var folders: [Folder] = []
    var accounts: [Account] = []

    var isUnifiedInbox: Bool { selectedSidebarItem == .unifiedInbox }

    // MARK: - Pagination

    /// Ternary has-more state derived from `Folder.moreMessages` (Thunderbird §7.4).
    /// Source of truth is the persisted folder row — ValueObservation on
    /// `folders` keeps `selectedFolder` fresh, so this recomputes on every
    /// pagination tick without mutable state.
    ///   nil  → unknown (pre-sync or no info yet)
    ///   true → server has more messages below the current UID floor
    ///   false → local already covers UID=1 / server returned empty page
    var hasMoreMessages: Bool? {
        switch selectedFolder?.moreMessages {
        case .true: return true
        case .false: return false
        case .unknown, .none: return nil
        }
    }
    /// Legacy binary accessor retained for existing call-sites. Treats `nil`
    /// as true so infinite-scroll keeps firing until we learn otherwise.
    var hasMoreOnServer: Bool { hasMoreMessages ?? true }
    var isLoadingMore = false
    private let localPageSize = 500
    private var localPageStart = 0
    private var localGroups: [[UUID]] = []
    var hasMoreLocalMessages: Bool { localGroups.count > localPageStart + localPageSize }
    var hasPreviousLocalMessages: Bool { localPageStart > 0 }
    var currentLocalPage: Int { localPageStart / localPageSize + 1 }
    func showPreviousLocalPage() {
        localPageStart = max(0, localPageStart - localPageSize)
        observeVisibleMessageDetails()
    }
    private var messageObservationGeneration = 0
    private var detailObservationGeneration = 0
    private var messageDetailsCancellable: AnyDatabaseCancellable?

    /// Loading local headers never waits for or changes incoming-mail sync.
    @discardableResult
    func loadMoreLocalMessages() -> Bool {
        guard hasMoreLocalMessages else { return false }
        localPageStart += localPageSize
        observeVisibleMessageDetails()
        return true
    }

    // MARK: - Threading

    var isThreaded: Bool = UserDefaults.standard.object(forKey: "isThreaded") as? Bool ?? true {
        didSet {
            UserDefaults.standard.set(isThreaded, forKey: "isThreaded")
            if oldValue != isThreaded { rebindMessageOrder() }
        }
    }

    // MARK: - Sort

    /// Session-scoped message list sort. Reset to `.default` on sidebar
    /// selection change (see `sidebarSelectionChanged`).
    var messageSort: MessageSort = .default {
        didSet { if oldValue != messageSort { rebindMessageOrder() } }
    }

    // MARK: - Search

    var searchText: String = ""
    var searchScope: SearchScope = .currentFolder
    var searchResults: [MessageListItem] = [] {
        didSet {
            guard !isApplyingSearchObservation else { return }
            let newIDs = Set(searchResults.map(\.id))
            let oldIDs = Set(oldValue.map(\.id))
            if newIDs != oldIDs {
                rebindSearchResultsObservation()
            }
        }
    }
    var isSearching = false
    var isSearchActive: Bool { !searchText.isEmpty }
    var serverSearchTask: Task<Void, Never>?
    /// Guards observation-driven updates from retriggering the observation.
    private var isApplyingSearchObservation = false
    var searchResultsCancellable: AnyDatabaseCancellable?
    /// Set to true by ⌘F command; the native toolbar search field observes and takes focus.
    var focusSearchField = false

    /// Pre-built lookup for O(1) account name by ID (used in MessageListTable).
    var accountNameByID: [UUID: String] = [:]

    // MARK: - Error surface

    var errors: [AppError] = []

    func surfaceError(_ title: String, detail: String? = nil) {
        errors.append(AppError(title: title, detail: detail))
    }

    // MARK: - Cancellables

    var messagesCancellable: AnyDatabaseCancellable?
    var foldersCancellable: AnyDatabaseCancellable?
    var accountsCancellable: AnyDatabaseCancellable?

    private var pool: DatabasePool { DatabaseService.shared.pool }

    init() {}

    /// Drop selected IDs that are no longer visible in the list.
    /// When search is active the visible list is `searchResults` — pruning
    /// against `messageItems` would drop cross-folder/cross-account hits and
    /// collapse the reading pane mid-open (CancellationError in loadBody).
    private func pruneSelection() {
        guard !selectedMessageIDs.isEmpty else { return }
        if isSearchActive { return }
        let visibleIDs = Set(messageItems.map(\.id))
        let survivors = selectedMessageIDs.intersection(visibleIDs)
        guard survivors.isEmpty else {
            selectedMessageIDs = survivors
            return
        }
        // Everything selected is gone (archive/delete/move) — step to the next
        // row instead of emptying the reading pane. `visibleOrder` is still the
        // pre-update order here, so it knows where the vanished rows sat.
        selectedMessageIDs = nextRowAfterVanishedSelection(alive: visibleIDs).map { [$0] } ?? []
    }

    /// Next still-present row after the vanished selection, falling back to the
    /// preceding one when the selection was at the end of the list.
    private func nextRowAfterVanishedSelection(alive: Set<UUID>) -> UUID? {
        guard let anchor = visibleOrder.lastIndex(where: selectedMessageIDs.contains)
        else { return nil }
        return visibleOrder[(anchor + 1)...].first(where: alive.contains)
            ?? visibleOrder[..<anchor].last(where: alive.contains)
    }

    // MARK: - Sidebar selection → observation switch

    private func sidebarSelectionChanged() {
        sidebarSelectionGeneration += 1
        guard let item = selectedSidebarItem else {
            stopObservingMessages()
            selectedFolder = nil
            return
        }

        selectedMessageIDs = []
        isLoadingMore = false
        // Folder switch clears session-scoped sort so each folder opens
        // in its natural date-DESC order (MailMate behavior).
        messageSort = .default
        localPageStart = 0
        localGroups = []
        // Clear synchronously so the Table remount (.id switch) does not
        // flash stale rows before the new observation delivers.
        messageItems = []

        switch item {
        case .unifiedInbox:
            selectedFolder = nil
            // Resolve inbox IDs first so SQLite can use its folder/date index.
            // The shared observation pages details for both folder and unified lists.
            observeMessages(
                whereClause: """
                WHERE m.folder_id IN (
                    SELECT f.id FROM folders f
                    JOIN accounts a ON a.id = f.account_id
                    WHERE f.special_use = 'inbox' AND a.is_enabled = 1
                )
                """
            )

        case .folder(let id):
            selectedFolder = folders.first { $0.id == id }
            observeMessages(
                whereClause: "WHERE m.folder_id = ?",
                arguments: [id]
            )
        }
    }

    // MARK: - Shared message observation (§5.4 projection)

    private static let messageListColumns = """
        m.id, m.uid, m.subject, m.from_name, m.from_address,
        m.to_addresses, m.date, m.preview,
        m.is_read, m.is_flagged, m.is_answered,
        m.has_attachments,
        m.thread_id, m.folder_id, m.account_id, m.size, 0 AS interaction_score,
        m.message_id, m.in_reply_to, m."references"
        """

    private func rebindMessageOrder() {
        guard let selectedSidebarItem else { return }
        localPageStart = 0
        switch selectedSidebarItem {
        case .unifiedInbox:
            observeMessages(whereClause: """
                WHERE m.folder_id IN (SELECT f.id FROM folders f
                JOIN accounts a ON a.id = f.account_id
                WHERE f.special_use = 'inbox' AND a.is_enabled = 1)
                """)
        case .folder(let id):
            observeMessages(whereClause: "WHERE m.folder_id = ?", arguments: [id])
        }
    }

    private func observeMessages(
        whereClause: String,
        arguments: StatementArguments = StatementArguments()
    ) {
        messagesCancellable?.cancel()
        messageDetailsCancellable?.cancel()
        messageObservationGeneration += 1
        detailObservationGeneration += 1
        let generation = messageObservationGeneration
        let sort = messageSort
        let threaded = isThreaded
        let sent = selectedFolder?.specialUse == .sent || selectedFolder?.specialUse == .drafts
        // Only fields affecting grouping/order belong in the global projection.
        // Flags, previews, fetched bodies and open scores update the visible page only.
        let subject = sort.column == .subject ? "m.subject" : "''"
        let fromName = sort.column == .fromTo && !sent ? "m.from_name" : "NULL"
        let fromAddress = sort.column == .fromTo && !sent ? "m.from_address" : "''"
        let recipients = sort.column == .fromTo && sent ? "m.to_addresses" : "'[]'"
        let size = sort.column == .size ? "m.size" : "0"
        let threadColumns = threaded
            ? "m.thread_id, m.message_id, m.in_reply_to, m.\"references\""
            : "NULL AS thread_id, NULL AS message_id, NULL AS in_reply_to, '[]' AS \"references\""
        let sql = """
            SELECT m.id, m.uid, m.folder_id, m.account_id, m.date,
                \(subject) AS subject, \(fromName) AS from_name,
                \(fromAddress) AS from_address, \(recipients) AS to_addresses,
                \(size) AS size, '' AS preview, 0 AS is_read, 0 AS is_flagged,
                0 AS is_answered, 0 AS has_attachments, 0 AS interaction_score,
                \(threadColumns)
            FROM messages m \(whereClause) ORDER BY m.date DESC, m.id ASC
            """
        messagesCancellable = ValueObservation
            .tracking { db -> [[UUID]] in
                let lightweight = try MessageListItem.fetchAll(db, sql: sql, arguments: arguments)
                if !threaded {
                    return lightweight.sorted(by: sort, isSentOrDrafts: sent).map { [$0.id] }
                }
                let groups = ThreadingService.group(lightweight)
                let groupByLatest = Dictionary(uniqueKeysWithValues: groups.map { ($0.latest.id, $0) })
                return groups.map(\.latest).sorted(by: sort, isSentOrDrafts: sent)
                    .compactMap { groupByLatest[$0.id]?.messages.map(\.id) }
            }
            .removeDuplicates()
            .start(in: pool, scheduling: .async(onQueue: .global(qos: .userInitiated))) { error in
                LogService.log(.error, .db, "Message order observation error", detail: "\(error)")
            } onChange: { [weak self] groups in
                Task { @MainActor [weak self] in
                    guard let self, self.messageObservationGeneration == generation else { return }
                    self.localGroups = groups
                    self.localPageStart = min(self.localPageStart,
                        max(0, (groups.count - 1) / self.localPageSize * self.localPageSize))
                    self.observeVisibleMessageDetails()
                }
            }
    }

    private func observeVisibleMessageDetails() {
        messageDetailsCancellable?.cancel()
        detailObservationGeneration += 1
        let generation = detailObservationGeneration
        // Preserve the selected thread when new mail pushes the page boundary down.
        let ids = localGroups.enumerated().filter { index, group in
            (localPageStart..<localPageStart + localPageSize).contains(index) || group.contains(where: selectedMessageIDs.contains)
        }.flatMap(\.element)
        guard !ids.isEmpty else { messageItems = []; return }
        let columns = Self.messageListColumns
        // Ponytail limit: an exceptionally large single thread loads all its headers
        // to preserve JWZ root/count/expansion. Add member paging if real threads
        // become large enough to dominate memory; never silently truncate a thread.
        messageDetailsCancellable = ValueObservation.tracking { db in
            var items: [MessageListItem] = []
            // Stay below SQLite's bind limit even for unusually large threads.
            for start in stride(from: 0, to: ids.count, by: 500) {
                let chunk = Array(ids[start..<Swift.min(start + 500, ids.count)])
                let placeholders = Array(repeating: "?", count: chunk.count).joined(separator: ",")
                items += try MessageListItem.fetchAll(db, sql: """
                    SELECT \(columns) FROM messages m WHERE m.id IN (\(placeholders))
                    ORDER BY m.date DESC, m.id ASC
                    """, arguments: StatementArguments(chunk))
            }
            return items.sorted { $0.date == $1.date ? $0.id.uuidString < $1.id.uuidString : $0.date > $1.date }
        }
        .removeDuplicates()
        .start(in: pool, scheduling: .async(onQueue: .global(qos: .userInitiated))) { error in
            LogService.log(.error, .db, "Message details observation error", detail: "\(error)")
        } onChange: { [weak self] items in
            Task { @MainActor [weak self] in
                guard let self, self.detailObservationGeneration == generation else { return }
                self.messageItems = items
            }
        }
    }

    func stopObservingMessages() {
        messageObservationGeneration += 1
        detailObservationGeneration += 1
        messagesCancellable?.cancel()
        messagesCancellable = nil
        messageDetailsCancellable?.cancel()
        messageDetailsCancellable = nil
        localGroups = []
        messageItems = []
    }

    // MARK: - Search results observation

    /// (Re)bind DB observation to the current `searchResults` id set so
    /// in-DB mutations (body fetch updates size / has_attachments, flag
    /// changes, etc.) reflect in the list immediately — matching the
    /// reactive behaviour of the main `messageItems` observation.
    private func rebindSearchResultsObservation() {
        searchResultsCancellable?.cancel()
        searchResultsCancellable = nil

        let ids = searchResults.map(\.id)
        guard !ids.isEmpty else { return }

        let placeholders = Array(repeating: "?", count: ids.count).joined(separator: ",")
        let sql = """
            SELECT \(Self.messageListColumns)
            FROM messages m
            WHERE m.id IN (\(placeholders))
            """
        let args = StatementArguments(ids)

        searchResultsCancellable = ValueObservation
            .tracking { db in
                try MessageListItem.fetchAll(db, sql: sql, arguments: args)
            }
            .start(in: pool, scheduling: .immediate) { error in
                LogService.log(.error, .db, "Search observation error", detail: "\(error)")
            } onChange: { [weak self] items in
                MainActor.assumeIsolated {
                    self?.applySearchObservationUpdate(items)
                }
            }
    }

    /// Re-key fresh rows into the current `searchResults` order so ranking
    /// from the search pipeline is preserved; drop any id no longer in DB.
    private func applySearchObservationUpdate(_ items: [MessageListItem]) {
        let byID = Dictionary(uniqueKeysWithValues: items.map { ($0.id, $0) })
        let reordered = searchResults.compactMap { byID[$0.id] }
        isApplyingSearchObservation = true
        searchResults = reordered
        isApplyingSearchObservation = false
    }

    // MARK: - Observe folders

    func observeFolders() {
        foldersCancellable = ValueObservation
            .tracking { db in
                try Folder
                    .order(Column("account_id").asc, Column("path").asc)
                    .fetchAll(db)
            }
            .start(in: pool, scheduling: .immediate) { error in
                LogService.log(.error, .db, "Folders observation error", detail: "\(error)")
            } onChange: { [weak self] folders in
                Task { @MainActor [weak self] in
                    guard let self else { return }
                    self.folders = folders
                    if self.selectedSidebarItem == nil,
                       let inbox = folders.first(where: { $0.specialUse == .inbox }) {
                        self.selectedSidebarItem = .folder(inbox.id)
                    }
                    // Keep selectedFolder in sync with DB state (moreMessages, unreadCount, etc.)
                    if let sf = self.selectedFolder {
                        self.selectedFolder = folders.first { $0.id == sf.id }
                    }
                }
            }
    }

    // MARK: - Observe accounts

    /// Track accounts table changes so `auth_state` flips (→ needsReauth)
    /// surface in the orange Reconnect banner without an app restart.
    func observeAccounts() {
        accountsCancellable = ValueObservation
            .tracking { db in
                // Match AccountRepository.all() so sidebar order == Settings order.
                try Account
                    .order(Column("sort_order").asc, Column("name").asc)
                    .fetchAll(db)
            }
            .start(in: pool, scheduling: .immediate) { error in
                LogService.log(.error, .db, "Accounts observation error", detail: "\(error)")
            } onChange: { [weak self] accounts in
                Task { @MainActor [weak self] in
                    guard let self else { return }
                    self.accounts = accounts
                    self.rebuildAccountLookup()
                }
            }
    }

    // MARK: - Rebuild account lookup

    func rebuildAccountLookup() {
        accountNameByID = Dictionary(
            uniqueKeysWithValues: accounts.map { ($0.id, $0.name) }
        )
    }
}

// MARK: - AppError

struct AppError: Identifiable, Hashable, Sendable {
    let id: UUID
    let date: Date
    let title: String
    let detail: String?

    init(title: String, detail: String? = nil) {
        self.id = UUID()
        self.date = Date()
        self.title = title
        self.detail = detail
    }
}
