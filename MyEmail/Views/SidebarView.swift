//
//  SidebarView.swift
//  MyEmail
//
//  Sidebar with Unified Inbox + per-account folder trees.
//  Native sidebar list with system disclosure controls and badges.
//

import SwiftUI

struct SidebarView: View {
    @Environment(AppState.self) private var appState
    @Environment(AppEnvironment.self) private var env
    @AppStorage("showUnifiedInbox") private var showUnifiedInbox = true
    @State private var cachedTrees: [(account: Account, tree: [FolderNode])] = []
    @State private var folderToEmpty: Folder?
    @State private var folderToName: Folder?
    @State private var folderName = ""
    @State private var isRenamingFolder = false
    @State private var collapsedFolderIDs: Set<UUID> = SidebarView.loadCollapsedIDs()
    @State private var collapsedAccountIDs: Set<UUID> = SidebarView.loadCollapsedAccountIDs()

    var body: some View {
        @Bindable var appState = appState

        List(selection: $appState.selectedSidebarItem) {
            if showUnifiedInbox {
                Label("Unified Inbox", systemImage: "tray.fill")
                    .badge(unifiedUnreadCount)
                .tag(SidebarItem.unifiedInbox)
            }

            ForEach(cachedTrees, id: \.account.id) { entry in
                Section(isExpanded: accountExpandedBinding(for: entry.account.id)) {
                    folderNodes(entry.tree)
                } header: {
                    accountHeader(for: entry.account)
                }
            }
        }
        .listStyle(.sidebar)
        .alert(isRenamingFolder ? String(localized: "Rename Folder") : String(localized: "New Subfolder"),
               isPresented: Binding(get: { folderToName != nil }, set: { if !$0 { folderToName = nil } })) {
            TextField(String(localized: "Folder name"), text: $folderName)
            Button(String(localized: "Cancel"), role: .cancel) { folderToName = nil }
            Button(isRenamingFolder ? String(localized: "Rename") : String(localized: "Create")) {
                guard let folder = folderToName else { return }
                let name = folderName.trimmingCharacters(in: .whitespacesAndNewlines)
                let rename = isRenamingFolder
                folderToName = nil
                guard !name.isEmpty else { return }
                Task {
                    if rename {
                        guard name != folder.displayName else { return }
                        await env.syncService.renameFolder(folderID: folder.id, newName: name)
                    } else if let account = appState.accounts.first(where: { $0.id == folder.accountID }) {
                        await env.syncService.createSubfolder(name: name, parentPath: folder.path, account: account)
                    }
                }
            }
            .disabled(folderName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
        .onAppear { rebuildTrees() }
        .onChange(of: appState.folders) { _, _ in rebuildTrees() }
        .onChange(of: appState.accounts) { _, _ in rebuildTrees() }
        .alert(
            String(localized: "Permanently delete all messages?"),
            isPresented: Binding(
                get: { folderToEmpty != nil },
                set: { if !$0 { folderToEmpty = nil } }
            )
        ) {
            Button(String(localized: "Cancel"), role: .cancel) { folderToEmpty = nil }
            Button(String(localized: "Empty"), role: .destructive) {
                if let folder = folderToEmpty {
                    Task { await env.syncService.emptyFolder(folderID: folder.id) }
                }
                folderToEmpty = nil
            }
        } message: {
            if let folder = folderToEmpty {
                Text("All messages in \"\(folder.localizedName)\" will be permanently deleted. This cannot be undone.")
            }
        }
    }

    // MARK: - Recursive folder tree with persistent expand/collapse

    @ViewBuilder
    private func folderNodes(_ nodes: [FolderNode]) -> some View {
        ForEach(nodes) { node in
            if let children = node.children {
                DisclosureGroup(isExpanded: expandedBinding(for: node.folder.id)) {
                    AnyView(folderNodes(children))
                } label: {
                    folderRow(node.folder)
                }
            } else {
                folderRow(node.folder)
            }
        }
    }

    @ViewBuilder
    private func folderRow(_ folder: Folder) -> some View {
        FolderRowView(folder: folder)
            .tag(SidebarItem.folder(folder.id))
            .contextMenu { folderContextMenu(folder) }
            .dropDestination(for: String.self) { items, _ in
                let ids = items.compactMap { UUID(uuidString: $0) }
                guard !ids.isEmpty else { return false }
                Task { await env.syncService.moveMessages(ids, to: folder.id) }
                return true
            }
    }

    private func accountExpandedBinding(for id: UUID) -> Binding<Bool> {
        Binding(
            get: { !collapsedAccountIDs.contains(id) },
            set: { isExpanded in
                if isExpanded {
                    collapsedAccountIDs.remove(id)
                } else {
                    collapsedAccountIDs.insert(id)
                }
                Self.saveCollapsedAccountIDs(collapsedAccountIDs)
            }
        )
    }

    private func expandedBinding(for id: UUID) -> Binding<Bool> {
        Binding(
            get: { !collapsedFolderIDs.contains(id) },
            set: { isExpanded in
                if isExpanded {
                    collapsedFolderIDs.remove(id)
                } else {
                    collapsedFolderIDs.insert(id)
                }
                Self.saveCollapsedIDs(collapsedFolderIDs)
            }
        )
    }

    // MARK: - Persistence

    private static let collapsedKey = "sidebarCollapsedFolderIDs"

    private static func loadCollapsedIDs() -> Set<UUID> {
        guard let strings = UserDefaults.standard.stringArray(forKey: collapsedKey) else {
            return []
        }
        return Set(strings.compactMap { UUID(uuidString: $0) })
    }

    private static func saveCollapsedIDs(_ ids: Set<UUID>) {
        UserDefaults.standard.set(ids.map(\.uuidString), forKey: collapsedKey)
    }

    private static let collapsedAccountKey = "sidebarCollapsedAccountIDs"

    private static func loadCollapsedAccountIDs() -> Set<UUID> {
        guard let strings = UserDefaults.standard.stringArray(forKey: collapsedAccountKey) else {
            return []
        }
        return Set(strings.compactMap { UUID(uuidString: $0) })
    }

    private static func saveCollapsedAccountIDs(_ ids: Set<UUID>) {
        UserDefaults.standard.set(ids.map(\.uuidString), forKey: collapsedAccountKey)
    }

    // MARK: - Tree building

    private func rebuildTrees() {
        cachedTrees = appState.accounts.map { account in
            let folders = appState.folders
                .filter { $0.accountID == account.id }
            return (account, FolderTreeBuilder.build(from: folders))
        }
    }

    private var unifiedUnreadCount: Int {
        appState.folders
            .filter { $0.specialUse == .inbox }
            .reduce(0) { $0 + $1.unreadCount }
    }

    /// Aggregate unread for an account's inbox — surfaced in the section
    /// header only when the account is collapsed (otherwise the Inbox row
    /// itself shows the same number).
    private func inboxUnreadCount(for accountID: UUID) -> Int {
        appState.folders
            .filter { $0.accountID == accountID && $0.specialUse == .inbox }
            .reduce(0) { $0 + $1.unreadCount }
    }

    @ViewBuilder
    private func accountHeader(for account: Account) -> some View {
        HStack {
            Text(account.name)
            Spacer()
            if collapsedAccountIDs.contains(account.id) {
                let count = inboxUnreadCount(for: account.id)
                if count > 0 {
                    UnreadBadge(count: count)
                }
            }
        }
    }

    // MARK: - Context menu (DESIGN.md §4.3)

    @ViewBuilder
    private func folderContextMenu(_ folder: Folder) -> some View {
        Button(String(localized: "Mark All Read")) {
            Task { await env.syncService.markAllReadWithSync(folderID: folder.id) }
        }

        switch emptyFolderRole(folder) {
        case .trash:
            Button(String(localized: "Empty Trash"), role: .destructive) {
                folderToEmpty = folder
            }
        case .junk:
            Button(String(localized: "Empty Junk"), role: .destructive) {
                folderToEmpty = folder
            }
        case .none:
            EmptyView()
        }

        Divider()

        Button(String(localized: "New Subfolder…")) {
            promptNewSubfolder(parent: folder)
        }

        if folder.specialUse == nil {
            Button(String(localized: "Rename…")) {
                promptRenameFolder(folder)
            }
            Button(String(localized: "Delete"), role: .destructive) {
                Task { await env.syncService.deleteFolder(folderID: folder.id) }
            }
        }

        Divider()

        Button(String(localized: "Run filters on folder")) {
            Task {
                await env.syncService.runRulesManually(
                    in: folder.id,
                    accountID: folder.accountID,
                    messageIDs: nil
                )
            }
        }

        Divider()

        Button(String(localized: "Resync Folder")) {
            Task { await env.syncService.forceResyncFolder(folderID: folder.id) }
        }
    }

    private enum EmptyRole { case trash, junk }

    /// Check if folder is Trash/Junk by specialUse OR account settings.
    private func emptyFolderRole(_ folder: Folder) -> EmptyRole? {
        if folder.specialUse == .trash { return .trash }
        if folder.specialUse == .junk { return .junk }
        guard let account = appState.accounts.first(where: { $0.id == folder.accountID }) else {
            return nil
        }
        if account.trashFolderPath == folder.path { return .trash }
        if account.junkFolderPath == folder.path { return .junk }
        return nil
    }

    private func promptNewSubfolder(parent: Folder) {
        guard appState.accounts.contains(where: { $0.id == parent.accountID }) else { return }
        isRenamingFolder = false
        folderName = ""
        folderToName = parent
    }

    private func promptRenameFolder(_ folder: Folder) {
        isRenamingFolder = true
        folderName = folder.displayName
        folderToName = folder
    }

}

// MARK: - FolderRowView

struct FolderRowView: View {
    let folder: Folder

    var body: some View {
        Label(folder.localizedName, systemImage: iconName)
            .badge(folder.unreadCount)
    }

    private var iconName: String {
        switch folder.specialUse {
        case .inbox:   return "tray"
        case .sent:    return "paperplane"
        case .drafts:  return "doc"
        case .trash:   return "trash"
        case .junk:    return "xmark.bin"
        case .archive: return "archivebox"
        case .all:     return "tray.2"
        case nil:      return "folder"
        }
    }
}

// MARK: - Unread count

struct UnreadBadge: View {
    let count: Int
    var muted: Bool = false

    var body: some View {
        Text("\(count)")
            .font(.caption.monospacedDigit())
            .foregroundStyle(muted ? .tertiary : .secondary)
    }
}
