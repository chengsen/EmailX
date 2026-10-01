//
//  MessageListNSCells.swift
//  EmailX
//
//  High-performance native AppKit cell used by the modern message summary list.
//

import AppKit

final class MessageSummaryCellView: NSTableCellView {
    private let unreadDot = NSImageView()
    private let sender = NSTextField(labelWithString: "")
    private let date = NSTextField(labelWithString: "")
    private let subject = NSTextField(labelWithString: "")
    private let preview = NSTextField(labelWithString: "")
    private let account = NSTextField(labelWithString: "")
    private let flag = NSImageView()
    private let attachment = NSImageView()
    private let threadCount = NSTextField(labelWithString: "")

    init(identifier: NSUserInterfaceItemIdentifier) {
        super.init(frame: .zero)
        self.identifier = identifier
        setup()
    }

    required init?(coder: NSCoder) { fatalError("not implemented") }

    private func setup() {
        unreadDot.translatesAutoresizingMaskIntoConstraints = false
        unreadDot.isHidden = true
        unreadDot.image = NSImage(systemSymbolName: "circle.fill", accessibilityDescription: nil)
        unreadDot.contentTintColor = .controlAccentColor
        unreadDot.imageScaling = .scaleProportionallyDown

        sender.translatesAutoresizingMaskIntoConstraints = false
        sender.lineBreakMode = .byTruncatingTail
        sender.maximumNumberOfLines = 1
        sender.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        date.translatesAutoresizingMaskIntoConstraints = false
        date.font = .preferredFont(forTextStyle: .caption1, options: [:])
        date.textColor = .secondaryLabelColor
        date.alignment = .right

        subject.translatesAutoresizingMaskIntoConstraints = false
        subject.lineBreakMode = .byTruncatingTail
        subject.maximumNumberOfLines = 1
        subject.textColor = .labelColor

        preview.translatesAutoresizingMaskIntoConstraints = false
        preview.font = .preferredFont(forTextStyle: .caption1, options: [:])
        preview.textColor = .secondaryLabelColor
        preview.lineBreakMode = .byTruncatingTail
        preview.maximumNumberOfLines = 1

        account.translatesAutoresizingMaskIntoConstraints = false
        account.font = .preferredFont(forTextStyle: .caption1, options: [:])
        account.textColor = .tertiaryLabelColor
        account.lineBreakMode = .byTruncatingTail
        account.maximumNumberOfLines = 1

        configureSymbol(flag, name: "flag.fill", tint: .systemOrange)
        configureSymbol(attachment, name: "paperclip", tint: .secondaryLabelColor)

        threadCount.translatesAutoresizingMaskIntoConstraints = false
        threadCount.font = .monospacedDigitSystemFont(
            ofSize: NSFont.preferredFont(forTextStyle: .caption1, options: [:]).pointSize,
            weight: .medium
        )
        threadCount.textColor = .secondaryLabelColor
        threadCount.alignment = .center
        threadCount.isHidden = true

        let iconStack = NSStackView(views: [attachment, flag, threadCount])
        iconStack.orientation = .horizontal
        iconStack.alignment = .centerY
        iconStack.spacing = 5
        iconStack.translatesAutoresizingMaskIntoConstraints = false

        let topSpacer = NSView()
        topSpacer.setContentHuggingPriority(.defaultLow, for: .horizontal)
        topSpacer.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        let topRow = NSStackView(views: [sender, topSpacer, iconStack, date])
        topRow.orientation = .horizontal
        topRow.alignment = .firstBaseline
        topRow.spacing = 6
        topRow.translatesAutoresizingMaskIntoConstraints = false

        let bottomSpacer = NSView()
        bottomSpacer.setContentHuggingPriority(.defaultLow, for: .horizontal)
        bottomSpacer.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        let bottomRow = NSStackView(views: [preview, bottomSpacer, account])
        bottomRow.orientation = .horizontal
        bottomRow.alignment = .firstBaseline
        bottomRow.spacing = 8
        bottomRow.translatesAutoresizingMaskIntoConstraints = false

        let textStack = NSStackView(views: [topRow, subject, bottomRow])
        textStack.orientation = .vertical
        textStack.alignment = .leading
        textStack.spacing = 2
        textStack.translatesAutoresizingMaskIntoConstraints = false

        addSubview(unreadDot)
        addSubview(textStack)

        // This cell exposes one complete summary. AppKit otherwise promotes
        // the underlying NSCell/image descendants even when their NSViews are
        // marked ignored, repeating text and decorative status symbols.
        setAccessibilityElement(true)
        setAccessibilityRole(.cell)
        setAccessibilityChildren([])

        NSLayoutConstraint.activate([
            unreadDot.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 10),
            unreadDot.centerYAnchor.constraint(equalTo: centerYAnchor),
            unreadDot.widthAnchor.constraint(equalToConstant: 7),
            unreadDot.heightAnchor.constraint(equalToConstant: 7),

            textStack.leadingAnchor.constraint(equalTo: unreadDot.trailingAnchor, constant: 9),
            textStack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -12),
            textStack.centerYAnchor.constraint(equalTo: centerYAnchor),

            subject.widthAnchor.constraint(equalTo: textStack.widthAnchor),
            topRow.widthAnchor.constraint(equalTo: textStack.widthAnchor),
            bottomRow.widthAnchor.constraint(equalTo: textStack.widthAnchor),

            flag.widthAnchor.constraint(equalToConstant: 12),
            flag.heightAnchor.constraint(equalToConstant: 12),
            attachment.widthAnchor.constraint(equalToConstant: 12),
            attachment.heightAnchor.constraint(equalToConstant: 12),
            threadCount.widthAnchor.constraint(greaterThanOrEqualToConstant: 14),
        ])
    }

    private func configureSymbol(_ imageView: NSImageView, name: String, tint: NSColor) {
        imageView.translatesAutoresizingMaskIntoConstraints = false
        imageView.image = NSImage(systemSymbolName: name, accessibilityDescription: nil)
        imageView.contentTintColor = tint
        imageView.imageScaling = .scaleProportionallyDown
        imageView.isHidden = true
    }

    func configure(
        sender senderText: String,
        subject subjectText: String,
        preview previewText: String,
        date dateText: String,
        account accountText: String?,
        isUnread: Bool,
        isFlagged: Bool,
        hasAttachment: Bool,
        threadCount count: Int?
    ) {
        unreadDot.isHidden = !isUnread

        sender.stringValue = senderText
        let bodyFont = NSFont.preferredFont(forTextStyle: .body, options: [:])
        sender.font = isUnread ? NSFontManager.shared.convert(bodyFont, toHaveTrait: .boldFontMask) : bodyFont

        subject.stringValue = subjectText.isEmpty
            ? String(localized: "(No Subject)")
            : subjectText
        subject.font = isUnread ? NSFontManager.shared.convert(bodyFont, toHaveTrait: .boldFontMask) : bodyFont

        preview.stringValue = previewText.replacingOccurrences(of: "\n", with: " ")
        preview.isHidden = preview.stringValue.isEmpty

        date.stringValue = dateText
        flag.isHidden = !isFlagged
        attachment.isHidden = !hasAttachment

        if let count, count > 1 {
            threadCount.stringValue = "\(count)"
            threadCount.isHidden = false
        } else {
            threadCount.isHidden = true
        }

        let accountValue = accountText?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        account.stringValue = accountValue
        account.isHidden = accountValue.isEmpty

        let status = [
            isUnread ? String(localized: "Unread") : String(localized: "Read"),
            isFlagged ? String(localized: "Flagged") : nil,
            hasAttachment ? String(localized: "Has attachments") : nil,
        ].compactMap { $0 }
        var description = [senderText, subject.stringValue, preview.stringValue, dateText, accountValue]
            .filter { !$0.isEmpty } + status
        if let count, count > 1 { description.append(String(localized: "(\(count) messages)")) }
        setAccessibilityLabel(description.joined(separator: ", "))

        toolTip = [senderText, subjectText, previewText]
            .filter { !$0.isEmpty }
            .joined(separator: "\n")
    }
}

/// Preserve NSTableView selection, arrow navigation and type selection; Return
/// activates the selected message instead of attempting to edit a summary cell.
final class MessageListTableView: NSTableView {
    var onActivateSelection: (() -> Void)?

    override func keyDown(with event: NSEvent) {
        if [36, 76].contains(event.keyCode),
           event.modifierFlags.intersection([.command, .option, .control, .shift]).isEmpty,
           selectedRow >= 0,
           let onActivateSelection {
            onActivateSelection()
            return
        }
        super.keyDown(with: event)
    }
}
