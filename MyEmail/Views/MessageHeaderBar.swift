//
//  MessageHeaderBar.swift
//  EmailX
//
//  Message header: sender, recipients, subject, date, action buttons.
//

import AppKit
import SwiftUI
import SwiftMail

struct MessageHeaderBar: View {
    let message: Message
    var gravatarImage: NSImage?
    var onReply: (() -> Void)?
    var onReplyAll: (() -> Void)?
    var onForward: (() -> Void)?
    var onViewSource: (() -> Void)?
    var onArchive: (() -> Void)?
    var onDelete: (() -> Void)?
    var onMarkSpam: (() -> Void)?
    var maximumHeight: CGFloat = 220

    @AppStorage("showMailUserAgent") private var showMUA: Bool = false

    private static let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .long
        f.timeStyle = .short
        return f
    }()

    var body: some View {
        // Keep one content tree mounted when its height changes so expanded
        // recipients and native keyboard focus survive viewport resizing.
        ScrollView(.vertical) { headerContent }
            .scrollBounceBehavior(.basedOnSize)
            .frame(maxHeight: maximumHeight)
            .fixedSize(horizontal: false, vertical: true)
    }

    private var headerContent: some View {
        // Parse once — avoid re-parsing the same address 3× per body re-eval.
        let fromEmail = EmailAddress.emailOnly(from: message.fromAddress)
        let fromDisplayName = (message.fromName?.isEmpty == false ? message.fromName : nil)
            ?? EmailAddress.displayName(from: message.fromAddress)

        return VStack(alignment: .leading, spacing: 8) {
            // Sender row: avatar + name/email + action buttons
            HStack(alignment: .top, spacing: 10) {
                senderAvatar(email: fromEmail)

                VStack(alignment: .leading, spacing: 2) {
                    AddressTokenView(
                        displayName: fromDisplayName,
                        email: fromEmail,
                        font: .headline
                    )

                    Text(fromEmail)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                        // Line up with the sender name above — Menu's
                        // borderlessButton label has a hidden ~3pt leading
                        // inset that plain Text doesn't.
                        .padding(.leading, 3)
                }

                Spacer()

                actionButtons
            }

            // Recipients
            if !message.toAddresses.isEmpty {
                AddressListRow(label: "To:", addresses: message.toAddresses)
            }
            if !message.ccAddresses.isEmpty {
                AddressListRow(label: "Cc:", addresses: message.ccAddresses)
            }
            if !message.replyToAddresses.isEmpty {
                AddressListRow(
                    label: String(localized: "Reply-To:"),
                    addresses: message.replyToAddresses
                )
            }

            // Subject
            Text(message.subject)
                .font(.title2.weight(.semibold))
                .textSelection(.enabled)

            HStack {
                Text(Self.dateFormatter.string(from: message.date))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer(minLength: 0)
                if showMUA, let ua = message.userAgent, !ua.isEmpty {
                    MUAIconSlot(userAgent: ua)
                }
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private func senderAvatar(email: String) -> some View {
        if let image = gravatarImage {
            Image(nsImage: image)
                .resizable()
                .frame(width: 36, height: 36)
                .clipShape(Circle())
                .accessibilityHidden(true)
        } else {
            InitialsAvatarView(
                name: message.fromName ?? EmailAddress(message.fromAddress)?.name,
                email: email,
                size: 36
            )
        }
    }

    private var actionButtons: some View {
        HStack(spacing: 8) {
            if let onReply {
                Button(action: onReply) {
                    Image(systemName: "arrowshape.turn.up.left")
                }
                .buttonStyle(.bordered)
                .controlSize(.regular)
                .help("Reply")
                .accessibilityLabel(Text("Reply"))
            }

            if onReplyAll != nil || onForward != nil || onArchive != nil
                || onDelete != nil || onMarkSpam != nil || onViewSource != nil {
                Menu {
                    if let onReplyAll {
                        Button("Reply All", systemImage: "arrowshape.turn.up.left.2",
                               action: onReplyAll)
                    }
                    if let onForward {
                        Button("Forward", systemImage: "arrowshape.turn.up.right",
                               action: onForward)
                    }

                    if (onReplyAll != nil || onForward != nil)
                        && (onArchive != nil || onDelete != nil || onMarkSpam != nil) {
                        Divider()
                    }

                    if let onArchive {
                        Button("Archive", systemImage: "archivebox", action: onArchive)
                    }
                    if let onDelete {
                        Button("Delete", systemImage: "trash", role: .destructive,
                               action: onDelete)
                    }
                    if let onMarkSpam {
                        Button("Mark as Spam", systemImage: "exclamationmark.octagon",
                               action: onMarkSpam)
                    }

                    if let onViewSource {
                        Divider()
                        Button("View Source", systemImage: "doc.plaintext",
                               action: onViewSource)
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
                .buttonStyle(.bordered)
                .controlSize(.regular)
                .fixedSize()
                .help("More")
                .accessibilityLabel(Text("More"))
            }
        }
    }
}

// MARK: - MUA icon slot

/// Small mail-client icon rendered next to the date. Delegates detection to
/// the GPL-isolated MUAResolver XPC service; keeps a stable image frame so
/// the surrounding layout never shifts while the async resolve is in flight.
private struct MUAIconSlot: View {
    let userAgent: String
    @State private var resolved: MUAResolverClient.Resolved?

    var body: some View {
        Group {
            if let data = resolved?.pngData, let image = NSImage(data: data) {
                Image(nsImage: image)
                    .resizable()
                    .interpolation(.high)
            } else {
                Color.clear
            }
        }
        .frame(width: 32, height: 32)
        .help(userAgent)
        .accessibilityLabel(Text(resolved?.displayName ?? userAgent))
        .task(id: userAgent) {
            resolved = await MUAResolverClient.shared.resolve(userAgent: userAgent)
        }
    }
}

// MARK: - Interactive address token

struct AddressTokenView: View {
    let displayName: String
    let email: String
    var font: Font = .subheadline

    @Environment(AppEnvironment.self) private var env
    @Environment(AppState.self) private var appState

    var body: some View {
        Menu {
            Text(email)
                .font(.callout)

            Divider()

            Button(String(localized: "Copy address")) {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(email, forType: .string)
            }

            Button(String(localized: "Add to trusted senders")) {
                env.trustedSenderService.addTrusted(email)
            }

            Button(String(localized: "Compose message")) {
                (NSApp.delegate as? AppDelegate)?.openCompose(mode: .newMessage)
            }

            Divider()

            Button(String(localized: "Search messages") + ": \(displayName)") {
                appState.searchText = "from:\(email)"
            }
        } label: {
            Text(displayName)
                .font(font)
                .lineLimit(1)
                .truncationMode(.middle)
        }
        .menuStyle(.borderlessButton)
        .accessibilityLabel(Text(verbatim: "\(displayName), \(email)"))
    }
}

// MARK: - Address list row (To:/Cc:)

struct AddressListRow: View {
    let label: String
    let addresses: [String]
    @State private var isExpanded = false

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(label)
                .font(.subheadline)
                .foregroundStyle(.secondary)

            if isExpanded {
                VStack(alignment: .leading, spacing: 6) {
                    Text(addresses.joined(separator: ", "))
                        .font(.subheadline)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)

                    Button("Show less") {
                        isExpanded = false
                    }
                    .buttonStyle(.link)
                    .controlSize(.small)
                }
            } else {
                FlowLayout(spacing: 6) {
                    ForEach(Array(addresses.prefix(3).enumerated()), id: \.offset) { _, raw in
                        token(for: raw)
                    }

                    if addresses.count > 3 {
                        Button("\(addresses.count - 3) more") {
                            isExpanded = true
                        }
                        .buttonStyle(.link)
                        .controlSize(.small)
                    }

                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .font(.subheadline)
    }

    @ViewBuilder
    private func token(for raw: String) -> some View {
        let parsed = SwiftMail.EmailAddress(raw)
        let addr = parsed?.address ?? raw
        let name = parsed?.name ?? ""
        AddressTokenView(
            displayName: name.isEmpty ? addr : name,
            email: addr
        )
    }
}
