//
//  AddGenericAccountView.swift
//  EmailX
//
//  Шаг 2b в Add Account flow: плoш form с IMAP/SMTP параметрами.
//  Test Connection в M2 — stub (пишет в LogService, не коннектится).
//  Real IMAP test — M5.
//

import SwiftUI

struct AddGenericAccountView: View {
    @Environment(AppEnvironment.self) private var env
    @Environment(AppState.self) private var appState
    let onBack: () -> Void
    let onFinished: () -> Void

    @State private var form = GenericAccountForm()
    @State private var isSaving = false
    @State private var errorMessage: String?

    var body: some View {
        VStack(spacing: 0) {
            header

            Form {
                AccountFormGeneralSection(form: $form)
                AccountFormIMAPSection(form: $form)
                AccountFormSMTPSection(form: $form)
            }
            .formStyle(.grouped)

            footer
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack {
            Button {
                onBack()
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "chevron.left")
                    Text("Back")
                }
            }
            .buttonStyle(.bordered)
            .disabled(isSaving)

            Spacer()

            Text("Other IMAP Server")
                .font(.headline)

            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    // MARK: - Footer

    private var footer: some View {
        HStack {
            if let errorMessage {
                Text(errorMessage)
                    .font(.caption)
                    .foregroundStyle(.red)
            }

            Spacer()

            Button("Test Connection") {
                testConnection()
            }
            .buttonStyle(.bordered)
            .disabled(isSaving || !form.isValid)

            Button("Save") {
                Task { await save() }
            }
            .buttonStyle(.borderedProminent)
            .keyboardShortcut(.defaultAction)
            .disabled(isSaving || !form.isValid)
        }
        .padding(16)
    }

    // MARK: - Actions

    private func testConnection() {
        // M2 stub: real IMAP connect — в M5.
        LogService.shared.log(
            .info,
            .auth,
            "Test Connection stub (M5 will implement real IMAP)",
            detail: "host=\(form.imapHost):\(form.imapPort) security=\(form.imapSecurity.rawValue)"
        )
        errorMessage = nil
    }

    private func save() async {
        isSaving = true
        errorMessage = nil
        defer { isSaving = false }

        do {
            let draft = form.toDraft()
            let account = try await env.authService.addGenericAccount(draft: draft)

            // Push new account into live AppState so the main window exits
            // empty-state immediately — otherwise nothing renders until
            // next app launch.
            appState.accounts = (try? env.accountRepository.all()) ?? []
            appState.rebuildAccountLookup()
            appState.observeFolders()
            if let inbox = await env.syncService.syncAccount(account) {
                appState.selectedSidebarItem = .folder(inbox.id)
            }

            onFinished()
        } catch AuthError.accountAlreadyExists(let email) {
            errorMessage = String(localized: "Account \(email) is already added.")
        } catch {
            LogService.log(.error, .auth, "Account setup failed", detail: String(describing: error))
            errorMessage = String(localized: "Could not connect to the mail server. Check your network and account settings.")
        }
    }
}

// MARK: - Form state

struct GenericAccountForm {
    /// Label shown in sidebar / account picker (e.g. "Personal", "Work").
    /// Defaults to email if user leaves empty.
    var accountName: String = ""
    /// Sender name used in outgoing "From" header (RFC 5322 display-name).
    var name: String = ""
    var email: String = ""
    var password: String = ""

    var imapHost: String = ""
    var imapPort: Int = 993
    var imapSecurity: ConnectionSecurity = .ssl

    var smtpHost: String = ""
    var smtpPort: Int = 587
    var smtpSecurity: ConnectionSecurity = .starttls

    var isValid: Bool {
        !name.trimmingCharacters(in: .whitespaces).isEmpty
        && email.contains("@")
        && !password.isEmpty
        && !imapHost.isEmpty
        && !smtpHost.isEmpty
        && imapPort > 0
        && smtpPort > 0
    }

    func toDraft() -> GenericAccountDraft {
        let label = accountName.trimmingCharacters(in: .whitespaces)
        return GenericAccountDraft(
            accountName: label.isEmpty ? email : label,
            name: name,
            email: email,
            password: password,
            imapHost: imapHost,
            imapPort: imapPort,
            imapSecurity: imapSecurity,
            smtpHost: smtpHost,
            smtpPort: smtpPort,
            smtpSecurity: smtpSecurity
        )
    }
}

// MARK: - Default ports per ConnectionSecurity

enum DefaultPorts {
    static func imap(for security: ConnectionSecurity) -> Int {
        switch security {
        case .ssl: return 993
        case .starttls, .none: return 143
        }
    }

    static func smtp(for security: ConnectionSecurity) -> Int {
        switch security {
        case .ssl: return 465
        case .starttls: return 587
        case .none: return 25
        }
    }

    static let allIMAP: Set<Int> = [993, 143]
    static let allSMTP: Set<Int> = [465, 587, 25]
}

// MARK: - Sections

struct AccountFormGeneralSection: View {
    @Binding var form: GenericAccountForm

    var body: some View {
        Section("General") {
            TextField("Account name", text: $form.accountName, prompt: Text("Personal, Work, …"))
            TextField("Display name", text: $form.name, prompt: Text("Your name"))
            TextField("Email", text: $form.email, prompt: Text("user@example.com"))
            SecureField("Password", text: $form.password)
        }
    }
}

struct AccountFormIMAPSection: View {
    @Binding var form: GenericAccountForm

    var body: some View {
        Section("IMAP (incoming)") {
            TextField("Server", text: $form.imapHost, prompt: Text("imap.example.com"))
            TextField("Port", value: $form.imapPort, format: .number.grouping(.never))
            Picker("Security", selection: $form.imapSecurity) {
                Text("SSL/TLS").tag(ConnectionSecurity.ssl)
                Text("STARTTLS").tag(ConnectionSecurity.starttls)
                Text("None").tag(ConnectionSecurity.none)
            }
            .onChange(of: form.imapSecurity) { _, newSecurity in
                // Only replace known defaults; preserve custom company server ports.
                if DefaultPorts.allIMAP.contains(form.imapPort) {
                    form.imapPort = DefaultPorts.imap(for: newSecurity)
                }
            }
        }
    }
}

struct AccountFormSMTPSection: View {
    @Binding var form: GenericAccountForm

    var body: some View {
        Section("SMTP (outgoing)") {
            TextField("Server", text: $form.smtpHost, prompt: Text("smtp.example.com"))
            TextField("Port", value: $form.smtpPort, format: .number.grouping(.never))
            Picker("Security", selection: $form.smtpSecurity) {
                Text("SSL/TLS").tag(ConnectionSecurity.ssl)
                Text("STARTTLS").tag(ConnectionSecurity.starttls)
                Text("None").tag(ConnectionSecurity.none)
            }
            .onChange(of: form.smtpSecurity) { _, newSecurity in
                if DefaultPorts.allSMTP.contains(form.smtpPort) {
                    form.smtpPort = DefaultPorts.smtp(for: newSecurity)
                }
            }
        }
    }
}
