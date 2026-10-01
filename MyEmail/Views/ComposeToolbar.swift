import AppKit
import SwiftUI

/// Window-local adapter: editing state remains in ComposeView; AppKit owns
/// toolbar layout, keyboard focus, borders and overflow. Formatting stays next
/// to the body because it operates on the active text selection.
struct ComposeToolbar: NSViewRepresentable {
    let canSend: Bool
    let isSending: Bool
    let isRichMode: Bool
    let signatures: [Signature]
    let selectedSignatureID: UUID?
    let onSend: () -> Void
    let onAttach: (NSWindow) -> Void
    let onModeChange: (Bool) -> Void
    let onSignatureChange: (UUID?) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeNSView(context: Context) -> WindowAnchor {
        let view = WindowAnchor()
        view.onWindow = { [weak coordinator = context.coordinator] window in
            coordinator?.install(in: window)
        }
        return view
    }

    func updateNSView(_ view: WindowAnchor, context: Context) {
        context.coordinator.state = self
        context.coordinator.refresh()
    }

    static func dismantleNSView(_ view: WindowAnchor, coordinator: Coordinator) {
        // Remove only this draft's toolbar, never another window's toolbar.
        if view.window?.toolbar === coordinator.toolbar {
            view.window?.toolbar = nil
        }
        view.onWindow = nil
    }

    final class WindowAnchor: NSView {
        var onWindow: ((NSWindow) -> Void)?
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            if let window { onWindow?(window) }
        }
    }

    @MainActor
    final class Coordinator: NSObject, NSToolbarDelegate {
        var state: ComposeToolbar
        private(set) var toolbar: NSToolbar?
        private weak var window: NSWindow?
        private let sendID = NSToolbarItem.Identifier("compose.send")
        private let attachID = NSToolbarItem.Identifier("compose.attach")
        private let modeID = NSToolbarItem.Identifier("compose.mode")
        private let signatureID = NSToolbarItem.Identifier("compose.signature")

        init(_ state: ComposeToolbar) { self.state = state }

        func install(in window: NSWindow) {
            guard toolbar == nil else { return }
            self.window = window
            let toolbar = NSToolbar(identifier: "ComposeToolbar")
            toolbar.delegate = self
            toolbar.displayMode = .iconOnly
            toolbar.allowsUserCustomization = false
            self.toolbar = toolbar
            window.toolbar = toolbar
            refresh()
        }

        func toolbarDefaultItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
            [sendID, .flexibleSpace, attachID, modeID, signatureID]
        }

        func toolbarAllowedItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
            toolbarDefaultItemIdentifiers(toolbar)
        }

        func toolbar(_ toolbar: NSToolbar, itemForItemIdentifier id: NSToolbarItem.Identifier,
                     willBeInsertedIntoToolbar flag: Bool) -> NSToolbarItem? {
            let item: NSToolbarItem
            switch id {
            case modeID, signatureID:
                item = NSMenuToolbarItem(itemIdentifier: id)
            case sendID, attachID:
                item = NSToolbarItem(itemIdentifier: id)
                item.target = self
                item.action = id == sendID ? #selector(send) : #selector(attach)
            default:
                return nil
            }
            item.autovalidates = false
            item.visibilityPriority = id == sendID ? .user : .standard
            item.style = id == sendID ? .prominent : .plain
            configure(item)
            return item
        }

        func refresh() {
            for item in toolbar?.items ?? [] { configure(item) }
        }

        private func configure(_ item: NSToolbarItem) {
            let label: String
            let symbol: String
            switch item.itemIdentifier {
            case sendID:
                label = String(localized: "Send")
                symbol = state.isSending ? "clock" : "paperplane"
                item.isEnabled = state.canSend
            case attachID:
                label = String(localized: "Attach files")
                symbol = "paperclip"
                item.isEnabled = !state.isSending
            case modeID:
                label = state.isRichMode ? String(localized: "Rich text") : String(localized: "Plain text")
                symbol = state.isRichMode ? "textformat" : "doc.plaintext"
                let menu = NSMenu()
                for rich in [true, false] {
                    let entry = NSMenuItem(title: rich ? String(localized: "Rich text") : String(localized: "Plain text"),
                                          action: #selector(changeMode(_:)), keyEquivalent: "")
                    entry.target = self
                    entry.tag = rich ? 1 : 0
                    entry.state = state.isRichMode == rich ? .on : .off
                    menu.addItem(entry)
                }
                (item as? NSMenuToolbarItem)?.menu = menu
                item.isEnabled = !state.isSending
            case signatureID:
                label = String(localized: "Signature")
                symbol = "signature"
                let menu = NSMenu()
                let none = NSMenuItem(title: String(localized: "No signature"),
                                      action: #selector(changeSignature(_:)), keyEquivalent: "")
                none.target = self
                none.state = state.selectedSignatureID == nil ? .on : .off
                menu.addItem(none)
                for signature in state.signatures {
                    let entry = NSMenuItem(title: signature.name, action: #selector(changeSignature(_:)), keyEquivalent: "")
                    entry.target = self
                    entry.representedObject = signature.id
                    entry.state = state.selectedSignatureID == signature.id ? .on : .off
                    menu.addItem(entry)
                }
                (item as? NSMenuToolbarItem)?.menu = menu
                item.isHidden = state.signatures.isEmpty
                item.isEnabled = !state.isSending
            default:
                return
            }
            item.label = label
            item.paletteLabel = label
            item.toolTip = label
            item.image = NSImage(systemSymbolName: symbol, accessibilityDescription: label)
        }

        @objc private func send() { if state.canSend { state.onSend() } }
        @objc private func attach() {
            guard !state.isSending, let window else { return }
            state.onAttach(window)
        }
        @objc private func changeMode(_ item: NSMenuItem) {
            if !state.isSending { state.onModeChange(item.tag == 1) }
        }
        @objc private func changeSignature(_ item: NSMenuItem) {
            if !state.isSending { state.onSignatureChange(item.representedObject as? UUID) }
        }
    }
}
