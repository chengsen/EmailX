//
//  ComposeHeaderFields.swift
//  EmailX
//

import AppKit
import SwiftUI

enum ComposeFieldFocus: Hashable {
    case field(String), suggestion(String)
}

struct ComposeHeaderFields: View {
    @FocusState private var focus: ComposeFieldFocus?
    let accounts: [Account]
    @Binding var selectedAccountID: UUID
    @Binding var to: String
    @Binding var cc: String
    @Binding var bcc: String
    @Binding var replyTo: String
    @Binding var subject: String
    @Binding var showExtraFields: Bool
    var maximumHeight: CGFloat = 220

    var body: some View {
        // Keep one form mounted: changing autocomplete height must not swap
        // its controls and discard the active field's focus/state.
        ScrollView(.vertical) { fields }
            .scrollBounceBehavior(.basedOnSize)
            .frame(maxHeight: maximumHeight)
            .fixedSize(horizontal: false, vertical: true)
    }

    private var fields: some View {
        Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 8) {
            GridRow {
                fieldLabel("From")
                fromPicker
            }

            GridRow {
                fieldLabel("To")
                HStack(spacing: 8) {
                    RecipientTextField(text: $to, placeholder: String(localized: "To"),
                                       focus: $focus, field: "to",
                                       nextField: showExtraFields ? "cc" : "subject", previousField: nil)
                    Button {
                        showExtraFields.toggle()
                    } label: {
                        Label(
                            showExtraFields ? "Hide Cc/Bcc" : "Add Cc/Bcc",
                            systemImage: showExtraFields ? "minus.circle" : "plus.circle"
                        )
                        .labelStyle(.iconOnly)
                        .frame(minWidth: 20, minHeight: 20)
                    }
                    .buttonStyle(.bordered)
                    .help(showExtraFields ? "Hide Cc/Bcc" : "Show Cc/Bcc")
                }
            }

            if showExtraFields {
                GridRow {
                    fieldLabel("Cc")
                    RecipientTextField(text: $cc, placeholder: String(localized: "Cc"),
                                       focus: $focus, field: "cc", nextField: "bcc", previousField: "to")
                }
                GridRow {
                    fieldLabel("Bcc")
                    RecipientTextField(text: $bcc, placeholder: String(localized: "Bcc"),
                                       focus: $focus, field: "bcc", nextField: "replyTo", previousField: "cc")
                }
                GridRow {
                    fieldLabel("Reply-To")
                    TextField("Reply-To", text: $replyTo)
                        .focused($focus, equals: .field("replyTo"))
                }
            }

            GridRow {
                fieldLabel("Subject")
                TextField("Subject", text: $subject)
                    .focused($focus, equals: .field("subject"))
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    private func fieldLabel(_ title: LocalizedStringKey) -> some View {
        Text(title)
            .font(.subheadline)
            .foregroundStyle(.secondary)
            .gridColumnAlignment(.trailing)
    }

    @ViewBuilder
    private var fromPicker: some View {
        let enabled = accounts.filter(\.isEnabled)
        if enabled.count <= 1 {
            Text(displayName(for: enabled.first))
                .foregroundStyle(.primary)
        } else {
            Picker("From", selection: $selectedAccountID) {
                ForEach(enabled) { account in
                    Text(displayName(for: account)).tag(account.id)
                }
            }
            .labelsHidden()
            .pickerStyle(.menu)
        }
    }

    private func displayName(for account: Account?) -> String {
        guard let account else { return "—" }
        let sender = account.senderName ?? account.name
        return sender == account.email
            ? account.email
            : "\(sender) <\(account.email)>"
    }
}

struct RecipientTextField: View {
    @Binding var text: String
    let placeholder: String

    @FocusState.Binding var focus: ComposeFieldFocus?
    let field: String
    let nextField: String
    let previousField: String?
    @State private var suggestions: [RecipientSuggestion] = []
    @State private var showSuggestions = false

    private var currentToken: String {
        text.components(separatedBy: ",")
            .last?
            .trimmingCharacters(in: .whitespaces) ?? ""
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            TextField(placeholder, text: $text)
                .focused($focus, equals: .field(field))
                .onExitCommand {
                    suggestions = []
                    showSuggestions = false
                }
                .onChange(of: text) { _, _ in
                    guard focus == .field(field) else {
                        suggestions = []
                        showSuggestions = false
                        return
                    }
                    updateSuggestions()
                }
                .onChange(of: focus) { previous, focus in
                    if focus == .field(field), case .suggestion = previous {
                        // Native text fields select all when focus returns. Keep previously
                        // chosen recipients when the user continues typing the next address.
                        let window = NSApp.keyWindow
                        DispatchQueue.main.async {
                            guard self.focus == .field(field), window?.isKeyWindow == true,
                                  let editor = window?.firstResponder as? NSTextView,
                                  editor.isFieldEditor else { return }
                            editor.setSelectedRange(NSRange(location: editor.string.utf16.count, length: 0))
                        }
                    }
                    else if focus == .field(field) { updateSuggestions() }
                    else {
                        switch focus {
                        case .suggestion: break
                        default:
                            suggestions = []
                            showSuggestions = false
                        }
                    }
                }
                .onKeyPress(.downArrow) {
                    guard let first = suggestions.first else { return .ignored }
                    focus = .suggestion(first.id)
                    return .handled
                }

            if showSuggestions {
                VStack(alignment: .leading, spacing: 2) {
                    ForEach(suggestions) { suggestion in
                        Button {
                            commitSuggestion(suggestion)
                        } label: {
                            HStack(spacing: 8) {
                                VStack(alignment: .leading, spacing: 1) {
                                    if let name = suggestion.name, !name.isEmpty {
                                        Text(name)
                                            .font(.callout)
                                            .lineLimit(1)
                                    }
                                    Text(suggestion.email)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                        .lineLimit(1)
                                }
                                Spacer()
                            }
                            .contentShape(Rectangle())
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                        }
                        .buttonStyle(.bordered)
                        .focusable()
                        .focused($focus, equals: .suggestion(suggestion.id))
                        .onKeyPress(.downArrow) { moveSuggestion(suggestion, offset: 1) }
                        .onKeyPress(.upArrow) { moveSuggestion(suggestion, offset: -1) }
                        .onKeyPress(.return) {
                            commitSuggestion(suggestion)
                            return .handled
                        }
                        .onKeyPress(.escape) {
                            suggestions = []
                            showSuggestions = false
                            focus = .field(field)
                            return .handled
                        }
                        .accessibilityLabel(Text([suggestion.name, suggestion.email]
                            .compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: ", ")))
                    }
                }
                .accessibilityElement(children: .contain)
            }
        }
        .onKeyPress(keys: [.tab]) { key in
            guard showSuggestions else { return .ignored }
            let backwards = key.modifiers.contains(.shift)
            guard !backwards || previousField != nil else { return .ignored }
            suggestions = []
            showSuggestions = false
            if backwards, let previousField { focus = .field(previousField) }
            else { focus = .field(nextField) }
            return .handled
        }
    }

    private func moveSuggestion(_ suggestion: RecipientSuggestion, offset: Int) -> KeyPress.Result {
        guard let index = suggestions.firstIndex(where: { $0.id == suggestion.id }) else { return .ignored }
        let next = index + offset
        if next < 0 { focus = .field(field) }
        else if suggestions.indices.contains(next) { focus = .suggestion(suggestions[next].id) }
        return .handled
    }

    private func updateSuggestions() {
        let token = currentToken
        guard token.count >= 2 else {
            suggestions = []
            showSuggestions = false
            return
        }
        suggestions = ContactsService.shared.suggestions(for: token, limit: 8)
        showSuggestions = !suggestions.isEmpty
    }

    private func commitSuggestion(_ suggestion: RecipientSuggestion) {
        var parts = text.components(separatedBy: ",")
            .map { $0.trimmingCharacters(in: .whitespaces) }
        if !parts.isEmpty { parts.removeLast() }
        parts.append(suggestion.email)
        text = parts.joined(separator: ", ") + ", "
        suggestions = []
        showSuggestions = false
        focus = .field(field)
    }
}
