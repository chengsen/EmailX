import AppKit
import SwiftUI
import Observation
struct Signature { let id: UUID; let name: String }
@Observable @MainActor final class DraftFixture {
    var canSend = true
    var isSending = false
    var isRichMode = true
    var selectedSignatureID: UUID?
    var sends = 0
    var attachmentWindow: NSWindow?
    let signatures = [Signature(id: UUID(), name: "Draft signature")]
}
struct HostedDraftFixture: View {
    let draft: DraftFixture
    var body: some View {
        Text("Isolated draft fixture").background {
            ComposeToolbar(canSend: draft.canSend, isSending: draft.isSending,
                           isRichMode: draft.isRichMode, signatures: draft.signatures,
                           selectedSignatureID: draft.selectedSignatureID,
                           onSend: { draft.sends += 1 }, onAttach: { draft.attachmentWindow = $0 },
                           onModeChange: { draft.isRichMode = $0 },
                           onSignatureChange: { draft.selectedSignatureID = $0 })
            Button("Send") { draft.sends += 1 }
                .keyboardShortcut(.return, modifiers: .command)
                .disabled(!draft.canSend).hidden().accessibilityHidden(true)
        }
    }
}
@main struct Probe {
    @MainActor static func main() {
        _ = NSApplication.shared
        var sent = 0
        var attached = 0
        var attachmentWindow: NSWindow?
        var modes: [Bool] = []
        var chosen: UUID?
        let signature = Signature(id: UUID(), name: "Fixture signature")
        func state(canSend: Bool = true, sending: Bool = false, rich: Bool = true) -> ComposeToolbar {
            ComposeToolbar(canSend: canSend, isSending: sending, isRichMode: rich,
                           signatures: [signature], selectedSignatureID: chosen,
                           onSend: { sent += 1 }, onAttach: { attached += 1; attachmentWindow = $0 },
                           onModeChange: { modes.append($0) }, onSignatureChange: { chosen = $0 })
        }
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 560, height: 400),
                              styleMask: [.titled, .resizable], backing: .buffered, defer: false)
        let coordinator = ComposeToolbar.Coordinator(state())
        coordinator.install(in: window)
        guard let toolbar = window.toolbar else { fatalError("missing toolbar") }
        precondition(toolbar.items.count == 5)
        func item(_ id: String) -> NSToolbarItem { toolbar.items.first { $0.itemIdentifier.rawValue == "compose." + id }! }
        let send = item("send")
        NSApp.sendAction(send.action!, to: send.target, from: send)
        let attach = item("attach")
        NSApp.sendAction(attach.action!, to: attach.target, from: attach)
        precondition(sent == 1 && attached == 1)
        precondition(attachmentWindow === window)
        let plain = (item("mode") as! NSMenuToolbarItem).menu.items[1]
        NSApp.sendAction(plain.action!, to: plain.target, from: plain)
        precondition(modes == [false])
        let sig = (item("signature") as! NSMenuToolbarItem).menu.items[1]
        NSApp.sendAction(sig.action!, to: sig.target, from: sig)
        precondition(chosen == signature.id)
        coordinator.state = state(canSend: false, sending: true, rich: false)
        coordinator.refresh()
        precondition(!send.isEnabled && !attach.isEnabled)
        NSApp.sendAction(send.action!, to: send.target, from: send)
        NSApp.sendAction(attach.action!, to: attach.target, from: attach)
        precondition(sent == 1 && attached == 1)
        precondition((item("mode") as! NSMenuToolbarItem).menu.items[1].state == .on)
        let other = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 700, height: 600),
                             styleMask: [.titled], backing: .buffered, defer: false)
        let otherCoordinator = ComposeToolbar.Coordinator(state())
        otherCoordinator.install(in: other)
        precondition(other.toolbar !== toolbar)
        precondition(other.toolbar!.items.first!.isEnabled)
        func hostedWindow(_ model: DraftFixture) -> NSWindow {
            let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 700, height: 600),
                                  styleMask: [.titled, .resizable], backing: .buffered, defer: false)
            window.contentView = NSHostingView(rootView: HostedDraftFixture(draft: model))
            window.contentView?.layoutSubtreeIfNeeded()
            return window
        }
        func settle() { RunLoop.main.run(until: Date().addingTimeInterval(0.1)) }
        let draftA = DraftFixture(), draftB = DraftFixture()
        let hosted = hostedWindow(draftA), hostedB = hostedWindow(draftB)
        settle()
        precondition(hosted.toolbar != nil && hostedB.toolbar != nil, "hosting bridge did not install toolbar")
        precondition(hosted.toolbar !== hostedB.toolbar)
        func hostedItem(_ window: NSWindow, _ id: String) -> NSToolbarItem {
            window.toolbar!.items.first { $0.itemIdentifier.rawValue == "compose." + id }!
        }
        // Neither fixture needs to be the application's key window. Attach
        // must always receive its toolbar's draft, including background clicks.
        for (host, draft) in [(hosted, draftA), (hostedB, draftB)] {
            let attachItem = hostedItem(host, "attach")
            NSApp.sendAction(attachItem.action!, to: attachItem.target, from: attachItem)
            precondition(draft.attachmentWindow === host)
        }
        draftA.canSend = false
        draftA.isSending = true
        draftA.isRichMode = false
        draftA.selectedSignatureID = draftA.signatures[0].id
        settle()
        precondition(!hostedItem(hosted, "send").isEnabled)
        precondition(hostedItem(hostedB, "send").isEnabled)
        precondition((hostedItem(hosted, "mode") as! NSMenuToolbarItem).menu.items[1].state == .on)
        precondition((hostedItem(hostedB, "mode") as! NSMenuToolbarItem).menu.items[0].state == .on)
        precondition((hostedItem(hosted, "signature") as! NSMenuToolbarItem).menu.items[1].state == .on)
        precondition((hostedItem(hostedB, "signature") as! NSMenuToolbarItem).menu.items[0].state == .on)
        let key = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: .command,
                                  timestamp: 0, windowNumber: hostedB.windowNumber, context: nil,
                                  characters: "\r", charactersIgnoringModifiers: "\r", isARepeat: false, keyCode: 36)!
        precondition(hostedB.performKeyEquivalent(with: key))
        precondition(draftB.sends == 1 && draftA.sends == 0)
        _ = hosted.performKeyEquivalent(with: key)
        precondition(draftA.sends == 0, "disabled shortcut sent mail")
        // Native items retain label/action or menu for AppKit overflow; no
        // hosted custom views replace the system's overflow representation.
        for id in ["send", "attach", "mode", "signature"] {
            let entry = hostedItem(hostedB, id)
            precondition(entry.view == nil && !entry.label.isEmpty)
            precondition(entry.action != nil || entry is NSMenuToolbarItem)
        }
        print("PASS: native install/actions/menus, reactive state, two hosted windows, enabled/disabled Cmd+Return, native overflow items")
    }
}
