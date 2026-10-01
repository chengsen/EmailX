import AppKit
import SwiftUI

private final class ProbeRows: NSObject, NSTableViewDataSource {
    func numberOfRows(in tableView: NSTableView) -> Int { 3 }
}

@main
struct NativeUIProbe {
    @MainActor static func main() {
        _ = NSApplication.shared
        let cell = MessageSummaryCellView(identifier: .init("test"))
        cell.configure(sender: "Long sender 名称", subject: "", preview: "first\nsecond", date: "Today", account: "Work", isUnread: true, isFlagged: true, hasAttachment: true, threadCount: 3)
        precondition(cell.accessibilityRole() == .cell)
        precondition(cell.accessibilityChildren()?.isEmpty == true,
                     "The native summary cell must not expose repeated text, Circle or flag descendants")
        let label = cell.accessibilityLabel() ?? ""
        precondition(label.contains("Long sender 名称") && label.contains("Unread") && label.contains("Flagged") && label.contains("Has attachments") && label.contains("3"))
        cell.configure(sender: "Next", subject: "Updated", preview: "", date: "Yesterday", account: nil, isUnread: false, isFlagged: false, hasAttachment: false, threadCount: nil)
        precondition(cell.accessibilityChildren()?.isEmpty == true,
                     "Reusing a cell must retain its single accessibility summary")
        let next = cell.accessibilityLabel() ?? ""
        precondition(next.contains("Read") && !next.contains("Flagged") && !next.contains("Work") && !next.contains("Long sender"))
        let longSubject = String(repeating: "Long subject 主题", count: 60)
        cell.configure(sender: "Sender", subject: longSubject, preview: "Preview", date: "Today", account: "Work", isUnread: false, isFlagged: false, hasAttachment: false, threadCount: nil)
        let cellWindow = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 280, height: 64),
                                  styleMask: .borderless, backing: .buffered, defer: false)
        let container = NSView(frame: NSRect(x: 0, y: 0, width: 280, height: 64))
        cellWindow.contentView = container
        container.addSubview(cell)
        cell.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            container.widthAnchor.constraint(equalToConstant: 280),
            cell.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            cell.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            cell.topAnchor.constraint(equalTo: container.topAnchor),
            cell.heightAnchor.constraint(equalToConstant: 64),
        ])
        cell.layoutSubtreeIfNeeded()
        func textFields(in view: NSView) -> [NSTextField] {
            view.subviews.flatMap { child in
                (child as? NSTextField).map { [$0] } ?? textFields(in: child)
            }
        }
        let subjectField = textFields(in: cell).first { $0.stringValue == longSubject }!
        let subjectBounds = cell.convert(subjectField.bounds, from: subjectField)
        precondition(cell.bounds.width <= 281 && subjectBounds.minX >= 0 && subjectBounds.maxX <= cell.bounds.maxX + 1,
                     "Long subjects must stay inside a minimum-width summary cell")
        precondition((cell.accessibilityLabel() ?? "").contains(longSubject))

        let rows = ProbeRows()
        let table = MessageListTableView()
        table.addTableColumn(NSTableColumn(identifier: .init("summary")))
        table.dataSource = rows
        table.reloadData()
        table.selectRowIndexes(IndexSet(integer: 1), byExtendingSelection: false)
        var activations: [Int] = []
        table.onActivateSelection = { activations.append(table.selectedRow) }
        for code: UInt16 in [36, 76] {
            let event = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [],
                                        timestamp: 0, windowNumber: 0, context: nil,
                                        characters: "\r", charactersIgnoringModifiers: "\r",
                                        isARepeat: false, keyCode: code)!
            table.keyDown(with: event)
        }
        precondition(activations == [1, 1], "Return and keypad Enter must activate the keyboard-selected row")
        precondition(table.selectedRow == 1, "Activation must preserve native table selection")

        for dark in [false, true] {
                let view = NSHostingView(rootView: FlowLayout {
                    Text(String(repeating: "Long filename 收件人", count: 20)).lineLimit(2)
                    Button("Remove attachment") {}
                }.environment(\.colorScheme, dark ? .dark : .light)
                    .frame(width: 220).fixedSize(horizontal: false, vertical: true))
                let size = view.fittingSize
                precondition(size.width.isFinite && size.height.isFinite && size.width <= 221 && size.height > 0)
        }
        print("PASS single native cell accessibility summary after reuse; bounded long subject; Return/Enter selected-row activation; long-text FlowLayout finite sizing in light/dark environments")
    }
}
