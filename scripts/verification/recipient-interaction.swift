import AppKit
import SwiftUI
import Observation

struct Account: Identifiable {
    let id = UUID()
    let name = "Isolated account"
    let email = "fixture@example.invalid"
    let senderName: String? = nil
    let isEnabled = true
}
struct RecipientSuggestion: Identifiable {
    let email: String
    let name: String?
    var id: String { email }
}
final class ContactsService {
    static let shared = ContactsService()
    func suggestions(for token: String, limit: Int) -> [RecipientSuggestion] {
        guard token.lowercased().hasPrefix("al") else { return [] }
        return [RecipientSuggestion(email: "alice@example.invalid", name: "Alice"),
                RecipientSuggestion(email: "albert@example.invalid", name: "Albert")]
    }
}
@Observable @MainActor final class Fields {
    let account = Account()
    var accountID = UUID()
    var to = ""
    var cc = ""
    var bcc = ""
    var replyTo = ""
    var subject = ""
    var extra = false
}
struct HeaderFixture: View {
    let model: Fields
    var body: some View {
        @Bindable var fields = model
        ComposeHeaderFields(accounts: [fields.account], selectedAccountID: $fields.accountID,
                            to: $fields.to, cc: $fields.cc, bcc: $fields.bcc,
                            replyTo: $fields.replyTo, subject: $fields.subject,
                            showExtraFields: $fields.extra, maximumHeight: 500)
    }
}
@main struct RecipientInteractionProbe {
    @MainActor static func settle() async { try? await Task.sleep(for: .milliseconds(150)) }
    @MainActor static func main() {
        _ = NSApplication.shared
        NSApp.setActivationPolicy(.regular)
        Task { @MainActor in await run() }
        NSApp.run()
    }
    @MainActor static func run() async {
        let model = Fields()
        let window = NSWindow(contentRect: NSRect(x: 100, y: 100, width: 700, height: 600),
                              styleMask: [.titled, .closable, .resizable], backing: .buffered, defer: false)
        window.title = "Isolated recipient interaction probe"
        window.contentView = NSHostingView(rootView: HeaderFixture(model: model))
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        await settle()
        func descendants(_ view: NSView) -> [NSView] {
            [view] + view.subviews.flatMap(descendants)
        }
        func field(_ placeholder: String) -> NSTextField {
            let matches = descendants(window.contentView!).compactMap { $0 as? NSTextField }
            guard let found = matches.first(where: { $0.placeholderString == placeholder }) else {
                fatalError("missing native field \(placeholder); found \(matches.map { $0.placeholderString ?? $0.stringValue })")
            }
            return found
        }
        func isFocused(_ placeholder: String) -> Bool {
            field(placeholder).currentEditor() === window.firstResponder
        }
        func key(_ characters: String, code: UInt16, modifiers: NSEvent.ModifierFlags = []) {
            let event = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: modifiers,
                                         timestamp: ProcessInfo.processInfo.systemUptime,
                                         windowNumber: window.windowNumber, context: nil,
                                         characters: characters, charactersIgnoringModifiers: characters,
                                         isARepeat: false, keyCode: code)!
            window.sendEvent(event)
        }
        window.makeFirstResponder(field("To"))
        await settle()
        precondition(isFocused("To"), "native To field did not acquire focus")
        (window.firstResponder as! NSTextView).insertText("al", replacementRange: NSRange(location: NSNotFound, length: 0))
        await settle()
        precondition(model.to == "al", "native field input did not update binding")
        key("\u{F701}", code: 125, modifiers: [.function, .numericPad])
        await settle()
        precondition(!isFocused("To"), "Down did not move to first suggestion")
        key("\u{F701}", code: 125, modifiers: [.function, .numericPad])
        await settle()
        key("\u{F700}", code: 126, modifiers: [.function, .numericPad])
        await settle()
        key("\r", code: 36)
        await settle()
        precondition(model.to == "alice@example.invalid, ", "Down/Down/Up/Return chose incorrect suggestion: \(model.to)")
        precondition(isFocused("To"), "Return did not restore To focus")
        let editor = window.firstResponder as! NSTextView
        precondition(editor.selectedRange() == NSRange(location: model.to.utf16.count, length: 0), "recipient continuation selected old address")
        editor.insertText("al", replacementRange: NSRange(location: NSNotFound, length: 0))
        await settle()
        precondition(model.to == "alice@example.invalid, al", "typing continuation overwrote old recipient")
        key("\u{1B}", code: 53)
        await settle()
        precondition(isFocused("To") && model.to == "alice@example.invalid, al", "Escape changed recipient or lost focus")
        // Re-enter suggestions and confirm Tab bypasses them to the real next field.
        (window.firstResponder as! NSTextView).insertText("b", replacementRange: NSRange(location: NSNotFound, length: 0))
        await settle()
        key("\t", code: 48)
        await settle()
        precondition(isFocused("Subject"), "Tab with suggestions did not advance To→Subject")
        model.extra = true
        await settle()
        window.makeFirstResponder(field("To"))
        await settle()
        for next in ["Cc", "Bcc", "Reply-To"] {
            let input = window.firstResponder as! NSTextView
            input.setSelectedRange(NSRange(location: input.string.utf16.count, length: 0))
            input.insertText("al", replacementRange: NSRange(location: NSNotFound, length: 0))
            await settle()
            key("\t", code: 48)
            await settle()
            precondition(isFocused(next), "expanded recipient Tab did not focus \(next)")
        }
        print("PASS: production recipient shared focus, native Down/Up/Return, continuation, Escape, To→Subject Tab with suggestions, expanded To→Cc→Bcc→Reply-To Tab")
        window.orderOut(nil)
        NSApp.terminate(nil)
    }
}
