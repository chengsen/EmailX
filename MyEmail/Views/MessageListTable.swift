//
//  MessageListTable.swift
//  MyEmail
//
//  Thin SwiftUI wrapper around `MessageListNSTable` (AppKit). Owns
//  threading cache + context actions; delegates rendering entirely
//  to an `NSTableView`-backed representable so @Observable data
//  ticks can't cause header/cell jiggle.
//

import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct MessageListTable: View {
    // MARK: - Environment
    @Environment(AppState.self) private var appState
    @Environment(AppEnvironment.self) private var env
    @Environment(\.undoManager) private var undoManager
    @AppStorage("messageDensity") private var density: String = "compact"

    // MARK: - Inputs
    let items: [MessageListItem]
    let folderID: UUID?
    @Binding var selectedMessageIDs: Set<UUID>
    var showAccountColumn: Bool = false
    var isSentOrDrafts: Bool = false

    // MARK: - State
    @State private var expandedThreadIDs: Set<UUID> = []
    @State private var sourceSheet: SourceSheet?

    // Materialize threading/order and the ID lookup once per metadata update,
    // rather than rebuilding them for selection or environment redraws.
    @State private var cachedOrder: [UUID] = []
    @State private var cachedItems: [MessageListItem] = []
    @State private var cachedLookup: [UUID: MessageListItem] = [:]
    @State private var cachedCounts: [UUID: Int] = [:]

    private struct DisplaySignature: Equatable {
        let isThreaded: Bool
        let expanded: Set<UUID>
        let sortColumn: MessageSort.Column
        let sortAscending: Bool
    }

    private var currentSignature: DisplaySignature {
        DisplaySignature(
            isThreaded: appState.isThreaded,
            expanded: expandedThreadIDs,
            sortColumn: appState.messageSort.column,
            sortAscending: appState.messageSort.order.ascending
        )
    }

    /// Row height mapped from density setting (DESIGN.md §4.4).
    private var rowHeight: CGFloat {
        let body = NSFont.preferredFont(forTextStyle: .body, options: [:])
        let caption = NSFont.preferredFont(forTextStyle: .caption1, options: [:])
        let minimum = ceil(body.ascender - body.descender + body.leading) * 2
            + ceil(caption.ascender - caption.descender + caption.leading) + 8
        let preferred: CGFloat = switch density {
        case "compact": 54
        case "wide": 76
        default: 64
        }
        return max(preferred, minimum)
    }

    private var itemByID: [UUID: MessageListItem] {
        cachedLookup
    }

    private func recomputeDisplayOrder() {
        cachedLookup = Dictionary(uniqueKeysWithValues: items.map { ($0.id, $0) })
        // Step 1: threading collapse → flat UUID order.
        let threadedItems: [MessageListItem]
        if appState.isThreaded {
            let groups = ThreadingService.group(items)
            var collected: [MessageListItem] = []
            collected.reserveCapacity(items.count)
            var counts: [UUID: Int] = [:]
            for group in groups {
                if group.count == 1 {
                    collected.append(group.latest)
                } else {
                    counts[group.latest.id] = group.count
                    if expandedThreadIDs.contains(group.id) {
                        collected.append(contentsOf: group.messages)
                    } else {
                        collected.append(group.latest)
                    }
                }
            }
            threadedItems = collected
            cachedCounts = counts
        } else {
            threadedItems = items
            cachedCounts = [:]
        }
        // Step 2: sort once here (was previously per-body render — the hot
        // path on 135k-row folders). Trade-off: in threaded mode with a
        // non-date sort, expanded-thread children may interleave with
        // unrelated rows — same as before, just materialized once.
        let sorted = threadedItems.sorted(
            by: appState.messageSort, isSentOrDrafts: isSentOrDrafts
        )
        cachedItems = sorted
        cachedOrder = sorted.map(\.id)
        // Publish for AppState.pruneSelection — it advances the selection to
        // the next row when the selected one is archived/deleted/moved.
        appState.visibleOrder = cachedOrder
    }

    var body: some View {
        // Reuse rows materialized when metadata or display configuration changes.
        // Selection and unrelated environment updates do not rebuild the lookup.
        let displayItems = cachedItems
        let threadCounts = cachedCounts

        return MessageListNSTable(
            items: displayItems,
            threadCounts: threadCounts,
            selectedMessageIDs: $selectedMessageIDs,
            showAccountColumn: showAccountColumn,
            isSentOrDrafts: isSentOrDrafts,
            rowHeight: rowHeight,
            accountName: { appState.accountNameByID[$0] ?? "" },
            sort: appState.messageSort,
            onDoubleClick: openMessageWindow,
            onPaginateIfLast: { id in
                // Pagination trigger matches previous SwiftUI behaviour:
                // only fire when we're at the last row AND state is not
                // "known no more" AND we're not already loading.
                guard id == displayItems.last?.id,
                      (appState.hasMoreLocalMessages || appState.hasMoreMessages != false),
                      !appState.isLoadingMore else { return }
                triggerLoadMore()
            },
            onToggleRead: toggleReadState,
            onToggleFlag: toggleFlagged,
            onArchive: archiveMessages,
            onDelete: deleteMessages,
            onOpenInWindow: openMessageWindow,
            onViewSource: { id in Task { await fetchAndShowSource(id) } },
            onSaveAs: { id in Task { await saveMessageToDownloads(id) } },
            onResync: { id in Task { await env.syncService.resyncMessage(id: id) } },
            onRunRules: runRulesOnSelection,
            onSortChange: { appState.messageSort = $0 }
        )
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if !appState.isSearchActive && (appState.hasPreviousLocalMessages || appState.hasMoreLocalMessages) {
                HStack {
                    Button("Previous page", systemImage: "chevron.left") { appState.showPreviousLocalPage() }
                        .disabled(!appState.hasPreviousLocalMessages)
                    Spacer()
                    Text("Page \(appState.currentLocalPage)").foregroundStyle(.secondary)
                    Spacer()
                    Button("Next page", systemImage: "chevron.right") { appState.loadMoreLocalMessages() }
                        .disabled(!appState.hasMoreLocalMessages)
                }
                .buttonStyle(.bordered)
                .padding(8)
            }
        }
        .overlay {
            if appState.isSearchActive
                && !appState.isSearching
                && displayItems.isEmpty {
                EmptyStateView(
                    icon: "magnifyingglass",
                    message: String(localized: "No results")
                )
            }
        }
        .sheet(item: $sourceSheet) { sheet in
            RawSourceView(source: sheet.source, onDismiss: { sourceSheet = nil })
        }
        .onAppear {
            recomputeDisplayOrder()
        }
        .onChange(of: currentSignature) { _, _ in recomputeDisplayOrder() }
        .onChange(of: items) { old, new in
            cachedLookup = Dictionary(uniqueKeysWithValues: new.map { ($0.id, $0) })
            // Re-sort only when actual ordering/thread fields change. Flags,
            // sizes outside size-sort and previews refresh existing rows only.
            let structureChanged = old.count != new.count || zip(old, new).contains { a, b in
                a.id != b.id || a.date != b.date || a.threadID != b.threadID
                || a.messageID != b.messageID || a.inReplyTo != b.inReplyTo || a.references != b.references
                || (appState.messageSort.column == .subject && a.subject != b.subject)
                || (appState.messageSort.column == .size && a.size != b.size)
                || (appState.messageSort.column == .fromTo &&
                    (a.fromName != b.fromName || a.fromAddress != b.fromAddress || a.toAddresses != b.toAddresses))
            }
            if structureChanged { recomputeDisplayOrder() }
            else { cachedItems = cachedOrder.compactMap { cachedLookup[$0] } }
        }
    }

    private func openMessageWindow(_ id: UUID) {
        (NSApp.delegate as? AppDelegate)?.openMessage(id: id)
    }

    // MARK: - Actions

    private func toggleReadState(_ ids: [UUID]) {
        Task {
            if anyUnread(in: ids) {
                await env.undoService.markAsRead(ids, undoManager: undoManager)
            } else {
                await env.undoService.markAsUnread(ids, undoManager: undoManager)
            }
        }
    }

    private func toggleFlagged(_ ids: [UUID]) {
        Task {
            await env.undoService.setFlagged(ids, flagged: anyUnflagged(in: ids),
                                             undoManager: undoManager)
        }
    }

    private func deleteMessages(_ ids: [UUID]) {
        Task { await env.undoService.deleteMessages(ids, undoManager: undoManager) }
    }

    private func archiveMessages(_ ids: [UUID]) {
        Task { await env.undoService.archiveMessages(ids, undoManager: undoManager) }
    }

    /// Run manual rules on the selected messages. When the list spans folders
    /// (Unified Inbox), group IDs by their source folder so each batch uses
    /// the correct accountID + scope. `accountID` is resolved from the
    /// message's folder (Folder.accountID).
    private func runRulesOnSelection(_ ids: [UUID]) {
        guard !ids.isEmpty else { return }
        let byFolder = Dictionary(grouping: ids) { id in
            itemByID[id]?.folderID
        }
        for (maybeFolderID, group) in byFolder {
            guard let fid = maybeFolderID,
                  let folder = appState.folders.first(where: { $0.id == fid }) else { continue }
            let accountID = folder.accountID
            Task {
                await env.syncService.runRulesManually(
                    in: fid, accountID: accountID, messageIDs: group
                )
            }
        }
    }

    private func anyUnread(in ids: [UUID]) -> Bool {
        ids.contains { itemByID[$0]?.isRead == false }
    }

    private func anyUnflagged(in ids: [UUID]) -> Bool {
        ids.contains { itemByID[$0]?.isFlagged == false }
    }

    private func fetchAndShowSource(_ messageID: UUID) async {
        do {
            let src = try await env.syncService.fetchRawSource(messageID: messageID)
            sourceSheet = SourceSheet(source: src)
        } catch {
            sourceSheet = SourceSheet(source: nil)
            LogService.log(.error, .sync, "View Source failed", detail: "\(error)")
        }
    }

    /// Save raw RFC822 source to disk. Streams bytes directly, avoiding the
    /// String conversion / large-window UI cost of View Source.
    /// Synchronous path mirrors `AttachmentStripView.saveAs` — `runModal()`
    /// must be on the main thread, NOT inside an awaited Task started from
    /// an NSMenu handler (where the panel is silently swallowed).
    /// Save raw RFC822 source straight to ~/Downloads + reveal in Finder.
    /// The app writes directly to Downloads from this context because a modal save panel
    /// silently swallows the panel), so we skip the dialog entirely.
    private func saveMessageToDownloads(_ messageID: UUID) async {
        do {
            guard let data = try await env.syncService
                .fetchRawSourceData(messageID: messageID) else { return }
            let dest = uniqueDownloadURL(for: messageID)
            try data.write(to: dest, options: .atomic)
            LogService.log(.info, .sync, "Saved message to Downloads",
                           detail: "\(dest.path) (\(data.count) bytes)")
            NSWorkspace.shared.activateFileViewerSelecting([dest])
        } catch {
            LogService.log(.error, .sync, "Save failed", detail: "\(error)")
        }
    }

    /// `~/Downloads/{subject}.eml` — appends ` (2)`, ` (3)`… on collision.
    private func uniqueDownloadURL(for messageID: UUID) -> URL {
        let downloads = FileManager.default
            .urls(for: .downloadsDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory() + "/Downloads")
        let base = suggestedFilename(for: messageID)
            .replacingOccurrences(of: ".eml", with: "")
        var url = downloads.appendingPathComponent("\(base).eml")
        var counter = 2
        while FileManager.default.fileExists(atPath: url.path) {
            url = downloads.appendingPathComponent("\(base) (\(counter)).eml")
            counter += 1
        }
        return url
    }

    private func suggestedFilename(for messageID: UUID) -> String {
        let raw = itemByID[messageID]?.subject.trimmingCharacters(in: .whitespacesAndNewlines)
        let base = (raw?.isEmpty == false ? raw! : "Untitled")
        let illegal: Set<Character> = ["/", ":", "\\", "?", "*", "|", "\"", "<", ">"]
        var sanitized = String(base.map { illegal.contains($0) ? "_" : $0 })
        if sanitized.count > 120 { sanitized = String(sanitized.prefix(120)) }
        return "\(sanitized).eml"
    }

    // MARK: - Pagination

    private func triggerLoadMore() {
        guard !appState.isSearchActive, !appState.isLoadingMore else { return }
        guard !appState.hasMoreLocalMessages else { return }
        guard let fid = folderID else { return }
        let generation = appState.sidebarSelectionGeneration
        appState.isLoadingMore = true
        Task {
            _ = await env.syncService.loadOlderMessages(folderID: fid)
            if appState.sidebarSelectionGeneration == generation { appState.isLoadingMore = false }
        }
    }
}
