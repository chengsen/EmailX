//
//  MessageListNSTable.swift
//  EmailX
//
//  AppKit NSTableView wrapped in NSViewRepresentable. Replaces SwiftUI
//  Table, which pushed NSHostingView into every header/row cell and
//  re-rendered on every @Observable tick — producing persistent visual
//  jiggle in the header row that KVO/CA-action suppression could not
//  fully eliminate.
//
//  Contract: same external API as the previous SwiftUI Table —
//  `items`, `selectedMessageIDs` binding, context menu, double-click,
//  pagination trigger, drag. A single summary column follows window width.
//

import AppKit
import SwiftUI

// MARK: - Column identifiers

private extension NSUserInterfaceItemIdentifier {
    static let summary = NSUserInterfaceItemIdentifier("summary")
}

// MARK: - Representable

struct MessageListNSTable: NSViewRepresentable {
    let items: [MessageListItem]
    let threadCounts: [UUID: Int]
    @Binding var selectedMessageIDs: Set<UUID>
    let showAccountColumn: Bool
    let isSentOrDrafts: Bool
    let rowHeight: CGFloat
    let accountName: (UUID) -> String
    let sort: MessageSort

    // Actions
    let onDoubleClick: (UUID) -> Void
    let onPaginateIfLast: (UUID) -> Void
    let onToggleRead: ([UUID]) -> Void
    let onToggleFlag: ([UUID]) -> Void
    let onArchive: ([UUID]) -> Void
    let onDelete: ([UUID]) -> Void
    let onOpenInWindow: (UUID) -> Void
    let onViewSource: (UUID) -> Void
    let onSaveAs: (UUID) -> Void
    let onResync: (UUID) -> Void
    let onRunRules: ([UUID]) -> Void
    let onSortChange: (MessageSort) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeNSView(context: Context) -> NSScrollView {
        let coordinator = context.coordinator

        let scroll = NSScrollView()
        scroll.hasVerticalScroller = true
        scroll.hasHorizontalScroller = false
        scroll.autohidesScrollers = true
        scroll.borderType = .noBorder
        scroll.drawsBackground = false

        let table = NSTableView()
        table.style = .fullWidth
        table.selectionHighlightStyle = .regular
        table.allowsMultipleSelection = true
        table.allowsColumnReordering = false
        table.allowsColumnResizing = false
        table.columnAutoresizingStyle = .uniformColumnAutoresizingStyle
        // Let macOS provide the surface; avoid legacy zebra-striping chrome.
        table.backgroundColor = .clear
        table.usesAlternatingRowBackgroundColors = false
        table.gridStyleMask = []
        table.rowHeight = rowHeight
        table.intercellSpacing = NSSize(width: 8, height: 0)
        table.doubleAction = #selector(Coordinator.tableDoubleClicked(_:))
        table.target = coordinator
        table.registerForDraggedTypes([.string])

        buildColumns(on: table)
        table.headerView = nil

        table.dataSource = coordinator
        table.delegate = coordinator

        let menu = NSMenu()
        menu.delegate = coordinator
        table.menu = menu

        scroll.documentView = table
        coordinator.tableView = table
        coordinator.items = items
        table.reloadData()

        return scroll
    }

    func updateNSView(_ scroll: NSScrollView, context: Context) {
        let coordinator = context.coordinator
        coordinator.parent = self

        guard let table = coordinator.tableView else { return }

        // Row height / density
        if table.rowHeight != rowHeight {
            table.rowHeight = rowHeight
        }

        // Diff items: structural change (ids differ) → reloadData.
        // Value-only change (same ids) → reloadData on visible rows
        // without destroying NSTableRowView instances → no header reflow.
        let previousItems = coordinator.items
        let structureChanged = previousItems.count != items.count
            || zip(previousItems, items).contains { $0.id != $1.id }
        coordinator.items = items

        if structureChanged {
            table.reloadData()
        } else if !items.isEmpty && previousItems != items {
            let visible = table.rows(in: scroll.contentView.bounds)
            if visible.length > 0 {
                let rowIndexes = IndexSet(integersIn: visible.location..<visible.location + visible.length)
                let colIndexes = IndexSet(integersIn: 0..<table.tableColumns.count)
                table.reloadData(forRowIndexes: rowIndexes, columnIndexes: colIndexes)
            }
        }

        // Sync selection (external → AppKit)
        let desiredRows = IndexSet(
            items.enumerated()
                .filter { selectedMessageIDs.contains($0.element.id) }
                .map(\.offset)
        )
        if table.selectedRowIndexes != desiredRows {
            coordinator.isApplyingExternalSelection = true
            table.selectRowIndexes(desiredRows, byExtendingSelection: false)
            coordinator.isApplyingExternalSelection = false
        }
    }

    private func buildColumns(on table: NSTableView) {
        let column = NSTableColumn(identifier: .summary)
        column.title = ""
        column.minWidth = 260
        column.width = 360
        column.resizingMask = [.autoresizingMask]
        table.addTableColumn(column)
    }

    // MARK: - Coordinator

    final class Coordinator: NSObject, NSTableViewDataSource, NSTableViewDelegate, NSMenuDelegate {
        var parent: MessageListNSTable
        var items: [MessageListItem] = []
        weak var tableView: NSTableView?
        var isApplyingExternalSelection = false
        private var lastPaginationRowID: UUID?

        init(_ parent: MessageListNSTable) {
            self.parent = parent
        }

        private static let timeFormatter: DateFormatter = {
            let f = DateFormatter()
            f.dateStyle = .none
            f.timeStyle = .short
            return f
        }()

        private static let dateFormatter: DateFormatter = {
            let f = DateFormatter()
            f.doesRelativeDateFormatting = true
            f.dateStyle = .short
            f.timeStyle = .none
            return f
        }()

        private static func displayDate(_ date: Date) -> String {
            Calendar.current.isDateInToday(date)
                ? timeFormatter.string(from: date)
                : dateFormatter.string(from: date)
        }

        // MARK: Data source

        func numberOfRows(in tableView: NSTableView) -> Int { items.count }

        func tableView(_ tableView: NSTableView,
                       viewFor tableColumn: NSTableColumn?,
                       row: Int) -> NSView? {
            guard let col = tableColumn, row >= 0, row < items.count else { return nil }
            let item = items[row]

            guard col.identifier == .summary else { return nil }
            let id = NSUserInterfaceItemIdentifier("summaryCell")
            let view = (tableView.makeView(withIdentifier: id, owner: nil) as? MessageSummaryCellView)
                ?? MessageSummaryCellView(identifier: id)

            view.configure(
                sender: parent.isSentOrDrafts ? item.displayTo : item.displayFrom,
                subject: item.subject,
                preview: item.preview,
                date: Self.displayDate(item.date),
                account: parent.showAccountColumn ? parent.accountName(item.accountID) : nil,
                isUnread: !item.isRead,
                isFlagged: item.isFlagged,
                hasAttachment: item.hasAttachments,
                threadCount: parent.threadCounts[item.id]
            )
            return view
        }

        func tableView(_ tableView: NSTableView,
                       pasteboardWriterForRow row: Int) -> NSPasteboardWriting? {
            guard row >= 0, row < items.count else { return nil }
            let pb = NSPasteboardItem()
            pb.setString(items[row].id.uuidString, forType: .string)
            return pb
        }

        // MARK: Delegate

        func tableView(_ tableView: NSTableView,
                       didAdd rowView: NSTableRowView, forRow row: Int) {
            guard row >= 0, row < items.count else { return }
            if row == items.count - 1 {
                let last = items[row].id
                guard lastPaginationRowID != last else { return }
                lastPaginationRowID = last
                parent.onPaginateIfLast(last)
            }
        }

        func tableViewSelectionDidChange(_ notification: Notification) {
            guard !isApplyingExternalSelection, let table = tableView else { return }
            let rows = table.selectedRowIndexes
            let ids = Set(rows.compactMap { idx -> UUID? in
                guard items.indices.contains(idx) else { return nil }
                return items[idx].id
            })
            if ids != parent.selectedMessageIDs {
                let parentRef = parent
                DispatchQueue.main.async {
                    parentRef.selectedMessageIDs = ids
                }
            }
        }

        @objc func tableDoubleClicked(_ sender: Any?) {
            guard let table = tableView,
                  table.clickedRow >= 0,
                  table.clickedRow < items.count else { return }
            parent.onDoubleClick(items[table.clickedRow].id)
        }

        // MARK: Context menu

        func menuNeedsUpdate(_ menu: NSMenu) {
            populateRowMenu(menu)
        }

        private func populateRowMenu(_ menu: NSMenu) {
            menu.removeAllItems()
            guard let table = tableView else { return }

            let targets: [Int] = {
                if table.clickedRow >= 0,
                   !table.selectedRowIndexes.contains(table.clickedRow) {
                    return [table.clickedRow]
                }
                return Array(table.selectedRowIndexes)
            }()

            let ids = targets.compactMap { idx -> UUID? in
                guard items.indices.contains(idx) else { return nil }
                return items[idx].id
            }
            guard !ids.isEmpty else { return }

            let anyUnread = ids.contains(where: { id in
                items.first(where: { $0.id == id })?.isRead == false
            })
            let anyUnflagged = ids.contains(where: { id in
                items.first(where: { $0.id == id })?.isFlagged == false
            })

            let readTitle = anyUnread
                ? String(localized: "Mark as Read")
                : String(localized: "Mark as Unread")
            menu.addMenuItem(readTitle) {
                [weak self] in self?.parent.onToggleRead(ids)
            }
            let flagTitle = anyUnflagged
                ? String(localized: "Flag")
                : String(localized: "Unflag")
            menu.addMenuItem(flagTitle) {
                [weak self] in self?.parent.onToggleFlag(ids)
            }
            menu.addMenuItem(String(localized: "Archive")) {
                [weak self] in self?.parent.onArchive(ids)
            }

            let sortItem = NSMenuItem(
                title: String(localized: "Sort By"),
                action: nil,
                keyEquivalent: ""
            )
            let sortMenu = NSMenu(title: String(localized: "Sort By"))
            for (title, column) in [
                (String(localized: "Date"), MessageSort.Column.date),
                (String(localized: "Sender"), MessageSort.Column.fromTo),
                (String(localized: "Subject"), MessageSort.Column.subject),
                (String(localized: "Size"), MessageSort.Column.size),
            ] {
                let current = parent.sort.column == column
                let ascending = current ? parent.sort.order.ascending : (column != .date)
                let item = ClosureMenuItem(title: title) { [weak self] in
                    guard let self else { return }
                    let nextAscending = current ? !ascending : (column != .date)
                    self.parent.onSortChange(
                        MessageSort(
                            column: column,
                            order: nextAscending ? .asc : .desc
                        )
                    )
                }
                if current {
                    item.state = .on
                }
                sortMenu.addItem(item)
            }
            sortItem.submenu = sortMenu
            menu.addItem(sortItem)

            menu.addItem(.separator())
            menu.addMenuItem(String(localized: "Run filters on selected messages")) {
                [weak self] in self?.parent.onRunRules(ids)
            }
            menu.addItem(.separator())
            menu.addMenuItem(String(localized: "Delete")) {
                [weak self] in self?.parent.onDelete(ids)
            }
            if ids.count == 1, let first = ids.first {
                menu.addItem(.separator())
                menu.addMenuItem(String(localized: "Open in New Window")) {
                    [weak self] in self?.parent.onOpenInWindow(first)
                }
                menu.addMenuItem(String(localized: "View Source")) {
                    [weak self] in self?.parent.onViewSource(first)
                }
                menu.addMenuItem(String(localized: "Save to Downloads")) {
                    [weak self] in self?.parent.onSaveAs(first)
                }
                menu.addItem(.separator())
                menu.addMenuItem(String(localized: "Re-sync message")) {
                    [weak self] in self?.parent.onResync(first)
                }
            }
        }

    }
}

// MARK: - NSMenu closure helper

private final class ClosureMenuItem: NSMenuItem {
    let handler: () -> Void
    init(title: String, handler: @escaping () -> Void) {
        self.handler = handler
        super.init(title: title, action: #selector(invoke), keyEquivalent: "")
        target = self
    }
    required init(coder: NSCoder) { fatalError() }
    @objc private func invoke() { handler() }
}

private extension NSMenu {
    func addMenuItem(_ title: String, handler: @escaping () -> Void) {
        addItem(ClosureMenuItem(title: title, handler: handler))
    }
}
