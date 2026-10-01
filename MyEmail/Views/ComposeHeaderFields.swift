//
//  ComposeHeaderFields.swift
//  EmailX
//

import SwiftUI

struct ComposeHeaderFields: View {
    let accounts: [Account]
    @Binding var selectedAccountID: UUID
    @Binding var to: String
    @Binding var cc: String
    @Binding var bcc: String
    @Binding var replyTo: String
    @Binding var subject: String
    @Binding var showExtraFields: Bool

    var body: some View {
        Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 8) {
            GridRow {
                fieldLabel("From")
                fromPicker
            }

            GridRow {
                fieldLabel("To")
                HStack(spacing: 8) {
                    RecipientTextField(text: $to, placeholder: String(localized: "To"))
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
                    RecipientTextField(text: $cc, placeholder: String(localized: "Cc"))
                }
                GridRow {
                    fieldLabel("Bcc")
                    RecipientTextField(text: $bcc, placeholder: String(localized: "Bcc"))
                }
                GridRow {
                    fieldLabel("Reply-To")
                    TextField("Reply-To", text: $replyTo)
                }
            }

            GridRow {
                fieldLabel("Subject")
                TextField("Subject", text: $subject)
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

    @FocusState private var isEditing: Bool
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
                .focused($isEditing)
                .onExitCommand {
                    suggestions = []
                    showSuggestions = false
                }
                .onChange(of: text) { _, _ in
                    guard isEditing else {
                        suggestions = []
                        showSuggestions = false
                        return
                    }
                    updateSuggestions()
                }
                .onChange(of: isEditing) { _, editing in
                    if editing { updateSuggestions() }
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
                        .accessibilityElement(children: .ignore)
                        .accessibilityLabel(Text([suggestion.name, suggestion.email]
                            .compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: ", ")))
                    }
                }
                .accessibilityElement(children: .contain)
            }
        }
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
        isEditing = true
    }
}
