import AppKit
import SwiftUI

@main
struct NativeUIProbe {
    @MainActor static func main() {
        _ = NSApplication.shared
        let cell = MessageSummaryCellView(identifier: .init("test"))
        cell.configure(sender: "Long sender 名称", subject: "", preview: "first\nsecond", date: "Today", account: "Work", isUnread: true, isFlagged: true, hasAttachment: true, threadCount: 3)
        let label = cell.accessibilityLabel() ?? ""
        precondition(label.contains("Long sender 名称") && label.contains("Unread") && label.contains("Flagged") && label.contains("Has attachments") && label.contains("3"))
        cell.configure(sender: "Next", subject: "Updated", preview: "", date: "Yesterday", account: nil, isUnread: false, isFlagged: false, hasAttachment: false, threadCount: nil)
        let next = cell.accessibilityLabel() ?? ""
        precondition(next.contains("Read") && !next.contains("Flagged") && !next.contains("Work") && !next.contains("Long sender"))
        for dark in [false, true] {
                let view = NSHostingView(rootView: FlowLayout {
                    Text(String(repeating: "Long filename 收件人", count: 20)).lineLimit(2)
                    Button("Remove attachment") {}
                }.environment(\.colorScheme, dark ? .dark : .light)
                    .frame(width: 220).fixedSize(horizontal: false, vertical: true))
                let size = view.fittingSize
                precondition(size.width.isFinite && size.height.isFinite && size.width <= 221 && size.height > 0)
        }
        print("PASS reused native cell accessibility state; long-text FlowLayout finite sizing in light/dark environments")
    }
}
