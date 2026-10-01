//
//  ComposeView.swift
//  EmailX
//
//  Compose window: new message, reply, forward.
//  Native macOS compose window.
//

import Accessibility
import AppKit
import GRDB
import SwiftMail
import SwiftUI
import UniformTypeIdentifiers

// MARK: - Compose window wrapper (resolves account from AppState)

struct ComposeWindowContent: View {
    @Environment(AppState.self) private var appState
    @Environment(AppEnvironment.self) private var env

    let mode: ComposeMode
    let dismiss: () -> Void

    @State private var resolvedMessage: Message?
    @State private var isLoading = false

    var body: some View {
        Group {
            if let account = resolveAccount() {
                // For reply/forward modes, wait for the full message before
                // instantiating ComposeView so prefill() sees non-nil message.
                if needsMessage && resolvedMessage == nil {
                    ProgressView()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    ComposeView(
                        mode: mode,
                        message: resolvedMessage,
                        account: account,
                        onDismiss: { dismiss() }
                    )
                }
            } else if isLoading {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                Text(String(localized: "No account available"))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .task { await resolveFullMessage() }
    }

    private var needsMessage: Bool {
        switch mode {
        case .newMessage, .mailto: return false
        case .reply, .replyAll, .forward: return true
        }
    }

    private func resolveFullMessage() async {
        guard let mid = mode.messageID else { return }
        isLoading = true
        defer { isLoading = false }
        resolvedMessage = try? await env.syncService.loadFullMessage(id: mid)
    }

    private func resolveAccount() -> Account? {
        if let aid = mode.accountID {
            return appState.accounts.first { $0.id == aid }
                ?? appState.accounts.first
        }
        // New message / mailto: pick the account of the current selection so
        // From matches what the user sees in the sidebar/list.
        if let aid = selectionAccountID(),
           let account = appState.accounts.first(where: { $0.id == aid }) {
            return account
        }
        return appState.accounts.first
    }

    /// Resolve the "currently visible" account from selection state.
    /// Priority: selected message → selected folder → none.
    private func selectionAccountID() -> UUID? {
        if let mid = appState.selectedMessageID {
            let pool = appState.isSearchActive
                ? appState.searchResults
                : appState.messageItems
            if let item = pool.first(where: { $0.id == mid }) {
                return item.accountID
            }
        }
        return appState.selectedFolder?.accountID
    }
}

// MARK: - ComposeView

struct ComposeView: View {
    @Environment(AppEnvironment.self) private var env
    @Environment(AppState.self) private var appState

    let mode: ComposeMode
    let message: Message?
    let initialAccount: Account
    let onDismiss: () -> Void

    // The fields below are intentionally non-private so that extensions in
    // ComposeView+Prefill.swift and ComposeView+Signature.swift can mutate
    // them. Keep private fields private unless an extension needs access.
    @State var selectedAccountID: UUID
    @State var toField: String = ""
    @State var ccField: String = ""
    @State var bccField: String = ""
    @State private var replyToField: String = ""
    @State var subjectField: String = ""
    @State var attributedBody = NSAttributedString(string: "")
    @State private var isRichMode: Bool = true
    @State private var activeTextView: NSTextView?
    @State private var showPlainConfirmAlert: Bool = false
    @State private var isSending = false
    @State private var errorMessage: String?
    @State private var showExtraFields = false
    @State private var recoveryID = UUID()
    @State var isDirty = false
    @State var attachments: [ComposeAttachment] = []
    @State var isDropTargeted = false
    @State var availableSignatures: [Signature] = []
    @State var selectedSignatureID: UUID?

    init(mode: ComposeMode, message: Message?, account: Account, onDismiss: @escaping () -> Void) {
        self.mode = mode
        self.message = message
        self.initialAccount = account
        self.onDismiss = onDismiss
        self._selectedAccountID = State(initialValue: account.id)
    }

    /// Currently selected account resolved from appState.
    var selectedAccount: Account {
        appState.accounts.first { $0.id == selectedAccountID } ?? initialAccount
    }

    var body: some View {
        VStack(spacing: 0) {
            ComposeHeaderFields(
                accounts: appState.accounts,
                selectedAccountID: $selectedAccountID,
                to: $toField, cc: $ccField,
                bcc: $bccField, replyTo: $replyToField,
                subject: $subjectField,
                showExtraFields: $showExtraFields
            )
            Divider()
            if isRichMode {
                FormattingToolbar(textView: activeTextView)
                Divider()
            }
            ComposeEditor(
                attributed: $attributedBody,
                isRichMode: isRichMode,
                onTextViewReady: { activeTextView = $0 },
                onFileURLsDropped: { urls in addAttachments(from: urls) },
                onDragTargetChanged: { isDropTargeted = $0 }
            )
            if !attachments.isEmpty {
                Divider()
                ComposeAttachmentsStripView(
                    attachments: attachments,
                    onRemove: { att in attachments.removeAll { $0.id == att.id }; isDirty = true }
                )
            }
            if let errorMessage {
                Text(errorMessage)
                    .foregroundStyle(.red)
                    .textSelection(.enabled)
                    .padding()
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .accessibilityLabel(String(localized: "Send") + ": " + errorMessage)
            }
        }
        .frame(minWidth: 560, minHeight: 400)
        .overlay(dropOverlay)
        .background {
            ComposeToolbar(
                canSend: !isSending && !Self.parseAddressList(toField).isEmpty,
                isSending: isSending,
                isRichMode: isRichMode,
                signatures: availableSignatures,
                selectedSignatureID: selectedSignatureID,
                onSend: { Task { await send() } },
                onAttach: { pickAttachments(in: $0) },
                onModeChange: { requestModeChange($0) },
                onSignatureChange: { selectedSignatureID = $0 }
            )
            // SwiftUI registers this shortcut with the hosting window; the
            // visible action lives in NSToolbar, including its overflow menu.
            Button("Send") { Task { await send() } }
                .keyboardShortcut(.return, modifiers: .command)
                .disabled(isSending || Self.parseAddressList(toField).isEmpty)
                .hidden()
                .accessibilityHidden(true)
        }
        .alert("Switching to plain text will remove formatting. Continue?",
               isPresented: $showPlainConfirmAlert) {
            Button("Cancel", role: .cancel) {}
            Button("Switch", role: .destructive) { convertToPlain() }
        }
        .onDrop(of: [.fileURL], isTargeted: $isDropTargeted, perform: handleDrop)
        .onAppear {
            prefill()
            reloadSignatures()
            selectedSignatureID = availableSignatures.first(where: \.isDefault)?.id
            applySelectedSignature()
        }
        .task { await draftAutosaveLoop() }
        .onDisappear { env.draftRecovery.remove(windowID: recoveryID) }
        .onChange(of: errorMessage) { _, message in
            if let message { AccessibilityNotification.Announcement(message).post() }
        }
        .onChange(of: toField) { _, _ in isDirty = true }
        .onChange(of: ccField) { _, _ in isDirty = true }
        .onChange(of: subjectField) { _, _ in isDirty = true }
        .onChange(of: attributedBody.string) { _, _ in isDirty = true }
        .onChange(of: selectedAccountID) { _, _ in
            isDirty = true
            reloadSignatures()
            selectedSignatureID = availableSignatures.first(where: \.isDefault)?.id
            applySelectedSignature()
        }
        .onChange(of: selectedSignatureID) { _, _ in
            applySelectedSignature()
        }
    }

    private func requestModeChange(_ newValue: Bool) {
        guard newValue != isRichMode else { return }
        if !newValue && hasFormatting {
            showPlainConfirmAlert = true
        } else {
            isRichMode = newValue
        }
    }

    /// Detects whether the body carries any formatting beyond the default
    /// typing attributes and the signature marker. Drives the rich→plain alert.
    private var hasFormatting: Bool {
        var formatted = false
        attributedBody.enumerateAttributes(
            in: NSRange(location: 0, length: attributedBody.length)
        ) { attrs, _, stop in
            for (key, value) in attrs {
                if key == RichTextSupport.signatureKey { continue }
                if key == .foregroundColor,
                   let color = value as? NSColor,
                   color == NSColor.labelColor { continue }
                if key == .font,
                   let font = value as? NSFont,
                   font == RichTextSupport.defaultFont { continue }
                formatted = true
                stop.pointee = true
                return
            }
        }
        return formatted
    }

    private func convertToPlain() {
        attributedBody = NSAttributedString(
            string: attributedBody.string,
            attributes: RichTextSupport.defaultTypingAttributes
        )
        isRichMode = false
    }

    /// Split a comma-separated recipient string into trimmed, non-empty
    /// addresses. Trailing "," from autocomplete would otherwise produce an
    /// empty entry that SMTP rejects with "Invalid recipient address".
    private static func parseAddressList(_ raw: String) -> [String] {
        raw.split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
    }

    /// Auto-save draft every 5 seconds when dirty; cancelled by SwiftUI on disappear.
    /// Rich-text formatting is dropped on autosave — recovery is plain-text only.
    private func draftAutosaveLoop() async {
        while !Task.isCancelled {
            try? await Task.sleep(for: .seconds(5))
            guard !Task.isCancelled, isDirty else { continue }
            isDirty = false
            env.draftRecovery.save(
                windowID: recoveryID,
                from: selectedAccount.email,
                to: toField, cc: ccField,
                subject: subjectField, bodyText: attributedBody.string
            )
        }
    }

    /// Build In-Reply-To and References for reply threading (RFC 2822 §3.6.4).
    private func replyThreadingHeaders() -> (inReplyTo: String?, references: [String]) {
        let isReply: Bool = switch mode {
        case .reply, .replyAll: true
        case .forward, .newMessage, .mailto: false
        }
        guard isReply, let msg = message,
              let msgID = msg.messageID, !msgID.isEmpty else {
            return (nil, [])
        }
        var refs = msg.references
        if !refs.contains(msgID) { refs.append(msgID) }
        return (msgID, refs)
    }

    // MARK: - Send

    private func send() async {
        guard !isSending, !Self.parseAddressList(toField).isEmpty else { return }
        isSending = true
        errorMessage = nil
        defer { isSending = false }

        let recipients = Self.parseAddressList(toField)
        let ccRecipients = Self.parseAddressList(ccField)
        let bccRecipients = Self.parseAddressList(bccField)
        let replyToRecipients = Self.parseAddressList(replyToField)

        // Build threading headers for replies (RFC 2822 §3.6.4)
        let (inReplyToHeader, refs) = replyThreadingHeaders()

        // Resolve original message info for \Answered / $Forwarded flags
        let origUID = message?.uid
        let origFolderPath = resolveOriginalFolderPath()
        let isForwardMode: Bool = if case .forward = mode { true } else { false }

        let plainBody = attributedBody.string
        let htmlBody: String? = isRichMode
            ? RichTextSupport.htmlFromAttributed(attributedBody)
            : nil

        let builtAttachments: [SwiftMail.Attachment]
        do {
            builtAttachments = try materializeAttachments()
        } catch {
            errorMessage = "\(error)"
            LogService.log(.error, .smtp, "Attachment read failed", detail: "\(error)")
            return
        }

        do {
            try await env.syncService.sendMessage(
                from: selectedAccount,
                to: recipients, cc: ccRecipients, bcc: bccRecipients,
                replyTo: replyToRecipients,
                subject: subjectField,
                textBody: plainBody,
                htmlBody: htmlBody,
                attachments: builtAttachments.isEmpty ? nil : builtAttachments,
                inReplyTo: inReplyToHeader,
                references: refs,
                originalMessageUID: origUID,
                originalFolderPath: origFolderPath,
                isForward: isForwardMode
            )
            onDismiss()
        } catch {
            errorMessage = "\(error)"
            LogService.log(.error, .smtp, "Send failed", detail: "\(error)")
        }
    }

    /// Resolve the IMAP folder path for the original message.
    private func resolveOriginalFolderPath() -> String? {
        guard let msg = message else { return nil }
        return appState.folders.first { $0.id == msg.folderID }?.path
    }

}

// MARK: - Editor

/// Switches between plain TextEditor and NSTextView-backed RichTextEditor.
/// Single source of truth is `attributed`; plain mode derives a String binding
/// that rewraps edits into NSAttributedString with default typing attributes.
struct ComposeEditor: View {
    @Binding var attributed: NSAttributedString
    let isRichMode: Bool
    let onTextViewReady: (NSTextView) -> Void
    var onFileURLsDropped: (([URL]) -> Void)?
    var onDragTargetChanged: ((Bool) -> Void)?

    var body: some View {
        if isRichMode {
            RichTextEditor(
                attributed: $attributed,
                onTextViewReady: onTextViewReady,
                onFileURLsDropped: onFileURLsDropped,
                onDragTargetChanged: onDragTargetChanged
            )
        } else {
            TextEditor(text: plainBinding)
                .font(.system(.body, design: .monospaced))
                .scrollContentBackground(.hidden)
                .padding(8)
        }
    }

    private var plainBinding: Binding<String> {
        Binding(
            get: { attributed.string },
            set: { newValue in
                attributed = NSAttributedString(
                    string: newValue,
                    attributes: RichTextSupport.defaultTypingAttributes
                )
            }
        )
    }
}
