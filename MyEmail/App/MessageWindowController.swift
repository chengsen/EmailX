//
//  MessageWindowController.swift
//  EmailX
//
//  AppKit-owned standalone "read message" window. One controller per
//  messageID — re-front if already open.
//

import AppKit
import GRDB
import SwiftUI

@MainActor
final class MessageWindowController: NSWindowController, NSWindowDelegate {
    let messageID: UUID
    private let environment: AppEnvironment
    private let onClose: (UUID) -> Void
    private var hasMessage = false

    init(
        messageID: UUID,
        appState: AppState,
        environment: AppEnvironment,
        onClose: @escaping (UUID) -> Void
    ) {
        self.messageID = messageID
        self.environment = environment
        self.onClose = onClose

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 700, height: 600),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = String(localized: "Message")
        window.toolbarStyle = .unified
        window.autorecalculatesKeyViewLoop = true
        window.minSize = NSSize(width: 500, height: 400)
        window.setFrameAutosaveName(
            "EmailXMessageWindow-\(messageID.uuidString.prefix(8))"
        )

        let rootView = MessageDetailView(
            messageID: messageID,
            usesWindowToolbar: true,
            onMessageAvailabilityChanged: { [weak window] available in
                (window?.windowController as? MessageWindowController)?.setMessageAvailable(available)
            }
        )
            .environment(appState)
            .environment(environment)
            .environment(environment.logService)

        window.contentView = NSHostingView(rootView: rootView)

        super.init(window: window)
        window.delegate = self
        let toolbar = NSToolbar(identifier: "MessageToolbar")
        toolbar.delegate = self
        toolbar.displayMode = .iconOnly
        toolbar.allowsUserCustomization = true
        toolbar.autosavesConfiguration = true
        window.toolbar = toolbar
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    // MARK: - NSWindowDelegate

    func windowWillClose(_ notification: Notification) {
        onClose(messageID)
    }

    // MARK: - @objc actions (responder chain)

    @objc func replyToMessage(_ sender: Any?) {
        openCompose { .reply(messageID: self.messageID, accountID: $0) }
    }

    @objc func replyAllToMessage(_ sender: Any?) {
        openCompose { .replyAll(messageID: self.messageID, accountID: $0) }
    }

    @objc func forwardMessage(_ sender: Any?) {
        openCompose { .forward(messageID: self.messageID, accountID: $0) }
    }

    @objc func archiveMessage(_ sender: Any?) {
        let um = window?.undoManager
        Task { [messageID, environment] in
            await environment.undoService.archiveMessages([messageID], undoManager: um)
        }
    }

    @objc func deleteMessage(_ sender: Any?) {
        let um = window?.undoManager
        Task { [messageID, environment] in
            await environment.undoService.deleteMessages([messageID], undoManager: um)
        }
    }

    @objc func toggleReadState(_ sender: Any?) {
        let um = window?.undoManager
        Task { [messageID, environment] in
            do {
                let isRead = try await environment.database.pool.read { db in
                    try Bool.fetchOne(db, sql: "SELECT is_read FROM messages WHERE id = ?",
                                      arguments: [messageID])
                }
                guard let isRead else { return }
                if isRead {
                    await environment.undoService.markAsUnread([messageID], undoManager: um)
                } else {
                    await environment.undoService.markAsRead([messageID], undoManager: um)
                }
            } catch {
                LogService.log(.error, .db, "Failed to load message", detail: "\(error)")
            }
        }
    }

    @objc func toggleFlag(_ sender: Any?) {
        let um = window?.undoManager
        Task { [messageID, environment] in
            do {
                let isFlagged = try await environment.database.pool.read { db in
                    try Bool.fetchOne(db, sql: "SELECT is_flagged FROM messages WHERE id = ?",
                                      arguments: [messageID])
                }
                guard let isFlagged else { return }
                await environment.undoService.setFlagged(
                    [messageID], flagged: !isFlagged, undoManager: um
                )
            } catch {
                LogService.log(.error, .db, "Failed to load message", detail: "\(error)")
            }
        }
    }

    @objc func markAsJunk(_ sender: Any?) {
        Task { [messageID, environment] in
            await environment.syncService.markAsJunk([messageID])
        }
    }

    private func setMessageAvailable(_ available: Bool) {
        hasMessage = available
        for item in window?.toolbar?.items ?? [] {
            item.isEnabled = available
        }
    }

    // MARK: - Helpers

    private func openCompose(mode: @escaping (UUID) -> ComposeMode) {
        // Standalone windows survive folder/page changes; resolve their own
        // message instead of depending on the currently visible list metadata.
        Task { [environment, messageID] in
            do {
                let accountID = try await environment.database.pool.read { db in
                    try UUID.fetchOne(db,
                        sql: "SELECT account_id FROM messages WHERE id = ?",
                        arguments: [messageID])
                }
                guard let accountID else { return }
                (NSApp.delegate as? AppDelegate)?.openCompose(mode: mode(accountID))
            } catch {
                LogService.log(.error, .db, "Failed to load message", detail: "\(error)")
            }
        }
    }

}

// MARK: - NSUserInterfaceValidations

extension MessageWindowController: NSUserInterfaceValidations {
    nonisolated func validateUserInterfaceItem(
        _ item: any NSValidatedUserInterfaceItem
    ) -> Bool {
        MainActor.assumeIsolated {
            guard let action = item.action else { return true }
            switch action {
            case #selector(replyToMessage(_:)), #selector(replyAllToMessage(_:)),
                 #selector(forwardMessage(_:)), #selector(archiveMessage(_:)),
                 #selector(deleteMessage(_:)), #selector(toggleReadState(_:)),
                 #selector(toggleFlag(_:)), #selector(markAsJunk(_:)):
                return hasMessage
            default:
                return true
            }
        }
    }
}

// MARK: - Native reading-window toolbar

extension MessageWindowController: NSToolbarDelegate {
    func toolbarDefaultItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        [.reply, .flexibleSpace, .archive, .tbDelete]
    }

    func toolbarAllowedItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        [.reply, .replyAll, .forward, .archive, .tbDelete, .junk, .space, .flexibleSpace]
    }

    func toolbar(_ toolbar: NSToolbar,
                 itemForItemIdentifier id: NSToolbarItem.Identifier,
                 willBeInsertedIntoToolbar flag: Bool) -> NSToolbarItem? {
        let label: String
        let symbol: String
        let action: Selector
        switch id {
        case .reply:
            label = String(localized: "Reply")
            symbol = "arrowshape.turn.up.left"
            action = #selector(replyToMessage(_:))
        case .replyAll:
            label = String(localized: "Reply All")
            symbol = "arrowshape.turn.up.left.2"
            action = #selector(replyAllToMessage(_:))
        case .forward:
            label = String(localized: "Forward")
            symbol = "arrowshape.turn.up.right"
            action = #selector(forwardMessage(_:))
        case .archive:
            label = String(localized: "Archive")
            symbol = "archivebox"
            action = #selector(archiveMessage(_:))
        case .tbDelete:
            label = String(localized: "Delete")
            symbol = "trash"
            action = #selector(deleteMessage(_:))
        case .junk:
            label = String(localized: "Mark as Spam")
            symbol = "exclamationmark.octagon"
            action = #selector(markAsJunk(_:))
        default:
            return nil
        }
        let item = NSToolbarItem(itemIdentifier: id)
        item.label = label
        item.paletteLabel = label
        item.toolTip = label
        item.image = NSImage(systemSymbolName: symbol, accessibilityDescription: label)
        item.target = self
        item.action = action
        item.autovalidates = false
        item.isEnabled = hasMessage
        item.visibilityPriority = id == .reply ? .high : .standard
        return item
    }
}
