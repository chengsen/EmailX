import AppKit
import SwiftUI

enum ProbeLogLevel { case error }
enum ProbeLogCategory { case smtp }
enum LogService {
    static func log(_ level: ProbeLogLevel, _ category: ProbeLogCategory,
                    _ message: String, detail: String) {}
}

@MainActor final class EditorFixture {
    var attributed = NSAttributedString(string: "prefix selected suffix",
                                         attributes: RichTextSupport.defaultTypingAttributes)
    var editor: NSTextView?
    var window: NSWindow!
    func install(title: String) {
        window = NSWindow(contentRect: NSRect(x: 120, y: 120, width: 560, height: 240),
                          styleMask: [.titled, .closable, .resizable], backing: .buffered, defer: false)
        window.title = title
        window.contentView = NSHostingView(rootView: RichTextEditor(
            attributed: Binding(get: { self.attributed }, set: { self.attributed = $0 }),
            onTextViewReady: { self.editor = $0 }
        ))
        window.contentView?.layoutSubtreeIfNeeded()
        window.orderFront(nil)
    }
}

@MainActor final class RejectEdit: NSObject, NSTextViewDelegate {
    var validations = 0
    func textView(_ textView: NSTextView, shouldChangeTextIn affectedCharRange: NSRange,
                  replacementString: String?) -> Bool {
        validations += 1
        return false
    }
}

@main struct EditorInteractionProbe {
    @MainActor static func settle() async { try? await Task.sleep(for: .milliseconds(150)) }
    @MainActor static func main() {
        _ = NSApplication.shared
        NSApp.setActivationPolicy(.regular)
        Task { @MainActor in await run() }
        NSApp.run()
    }

    @MainActor static func run() async {
        let first = EditorFixture(), second = EditorFixture()
        first.install(title: "EmailX Editor Probe A")
        second.install(title: "EmailX Editor Probe B")
        await settle()
        guard let a = first.editor, let b = second.editor else { fatalError("production editor bridge missing") }
        precondition(a.accessibilityLabel() == String(localized: "Message body"))
        precondition(b.accessibilityLabel() == String(localized: "Message body"))
        for invalid in ["", "abc", "   ", "mailto:", "https://"] {
            precondition(RichTextSupport.validatedLinkURL(invalid) == nil)
        }
        precondition(RichTextSupport.validatedLinkURL("HTTP://") == nil)
        precondition(RichTextSupport.validatedLinkURL("https://?a=b") == nil)
        for valid in ["https://example.com/path?q=1", "http://example.com", "mailto:user@example.com", "file:///tmp/example.txt", "customscheme:value"] {
            precondition(RichTextSupport.validatedLinkURL(valid) != nil, "valid scheme rejected: \(valid)")
        }
        let original = NSAttributedString(attributedString: a.textStorage!)
        let originalB = NSAttributedString(attributedString: b.textStorage!)
        let selection = NSRange(location: 7, length: 8)
        a.setSelectedRange(selection)
        let originalTyping = a.typingAttributes as NSDictionary
        let url = URL(string: "https://example.com")!
        let manager = a.undoManager!
        manager.removeAllActions()
        manager.beginUndoGrouping()
        RichTextSupport.insertLink(url, label: "new linked label", in: a, replacing: selection)
        manager.endUndoGrouping()
        precondition(a.string == "prefix new linked label suffix")
        precondition(a.textStorage!.attribute(.link, at: 7, effectiveRange: nil) as? URL == url)
        precondition(a.selectedRange() == NSRange(location: 23, length: 0))
        precondition((a.typingAttributes as NSDictionary).isEqual(originalTyping))
        precondition(b.textStorage!.isEqual(to: originalB))
        manager.undo()
        precondition(a.textStorage!.isEqual(to: original), "one Undo must restore original text and attributes")
        precondition(a.selectedRange() == selection, "Undo must restore original selection")
        manager.redo()
        precondition(a.string == "prefix new linked label suffix")
        precondition(a.textStorage!.attribute(.link, at: 7, effectiveRange: nil) as? URL == url)
        precondition(a.selectedRange() == NSRange(location: 23, length: 0), "Redo must restore insertion caret")
        let reject = RejectEdit()
        a.delegate = reject
        let beforeRejected = NSAttributedString(attributedString: a.textStorage!)
        RichTextSupport.insertLink(url, label: "vetoed", in: a, replacing: NSRange(location: 0, length: 6))
        precondition(reject.validations == 1 && a.textStorage!.isEqual(to: beforeRejected), "native delegate veto was bypassed")
        a.delegate = nil
        print("PASS: production editor AX label, web-host URL validation and other schemes, native link selection/typing attributes/Undo/Redo/delegate veto, other draft unchanged")

        first.window.makeKeyAndOrderFront(nil)
        first.window.makeFirstResponder(a)
        NSApp.activate(ignoringOtherApps: true)
        await settle()
        let panel = NSColorPanel.shared
        panel.setTarget(nil)
        panel.setAction(#selector(NSTextView.changeColor(_:)))
        if NSApp.keyWindow === first.window || NSApp.mainWindow === first.window {
            a.setSelectedRange(NSRange(location: 0, length: 6))
            let beforeA = NSAttributedString(attributedString: a.textStorage!)
            let beforeB = NSAttributedString(attributedString: b.textStorage!)
            panel.color = .red
            precondition(NSApp.sendAction(#selector(NSTextView.changeColor(_:)), to: nil, from: panel))
            precondition(a.textStorage!.attribute(.foregroundColor, at: 0, effectiveRange: nil) as? NSColor == .red)
            precondition(b.textStorage!.isEqual(to: beforeB))
            precondition(a.textStorage!.attributedSubstring(from: NSRange(location: 6, length: a.textStorage!.length - 6)).isEqual(to: beforeA.attributedSubstring(from: NSRange(location: 6, length: beforeA.length - 6))))
            second.window.makeKeyAndOrderFront(nil)
            second.window.makeFirstResponder(b)
            await settle()
            guard NSApp.keyWindow === second.window || NSApp.mainWindow === second.window else { fatalError("cannot switch probe's active draft") }
            b.setSelectedRange(NSRange(location: 7, length: 8))
            let afterA = NSAttributedString(attributedString: a.textStorage!)
            panel.color = .blue
            precondition(NSApp.sendAction(#selector(NSTextView.changeColor(_:)), to: nil, from: panel))
            precondition(b.textStorage!.attribute(.foregroundColor, at: 7, effectiveRange: nil) as? NSColor == .blue)
            precondition(a.textStorage!.isEqual(to: afterA))
            print("PASS: shared nil-target color panel follows current draft responder chain and edits only its selection")
        } else {
            print("SKIP: this launch did not acquire a key/main window; active-window color routing requires foreground CUA activation")
        }
        first.window.orderOut(nil)
        second.window.orderOut(nil)
        panel.orderOut(nil)
        NSApp.terminate(nil)
    }
}
