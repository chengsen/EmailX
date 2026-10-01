//
//  ErrorBannerView.swift
//  EmailX
//

import SwiftUI

struct ErrorBannerView: View {
    @Environment(AppState.self) private var appState
    @Environment(AppEnvironment.self) private var env

    var body: some View {
        VStack(spacing: 8) {
            ForEach(accountsNeedingReauth) { account in
                StatusNotice(
                    symbol: "exclamationmark.triangle.fill",
                    tint: .orange,
                    title: String(localized: "\(account.email) — authentication expired")
                ) {
                    Button("Reconnect") {
                        Task {
                            do {
                                try await env.authService.refreshViaOAuth(
                                    accountID: account.id, email: account.email
                                )
                                await env.syncService.syncAccount(account)
                            } catch AuthError.userCancelled {
                                // Keep the notice visible so the user can retry.
                            } catch {
                                LogService.log(.error, .auth, "Reconnect failed",
                                               detail: String(describing: error))
                                appState.errors.append(AppError(
                                    title: String(localized: "Reconnect failed"),
                                    detail: (error as? AuthError)?.errorDescription
                                        ?? String(localized: "Could not connect to the mail server. Check your network and account settings.")
                                ))
                            }
                        }
                    }
                    .buttonStyle(.glass)
                    .controlSize(.small)
                }
            }

            ForEach(appState.errors) { error in
                StatusNotice(
                    symbol: "xmark.circle.fill",
                    tint: .red,
                    title: error.title,
                    detail: error.detail
                ) {
                    Button {
                        appState.errors.removeAll { $0.id == error.id }
                    } label: {
                        Image(systemName: "xmark")
                    }
                    .buttonStyle(.glass)
                    .controlSize(.small)
                    .help("Dismiss")
                }
                .task {
                    try? await Task.sleep(for: .seconds(8))
                    guard !Task.isCancelled else { return }
                    appState.errors.removeAll { $0.id == error.id }
                }
            }
        }
    }

    private var accountsNeedingReauth: [Account] {
        appState.accounts.filter { $0.authState == .needsReauth }
    }
}

private struct StatusNotice<Actions: View>: View {
    let symbol: String
    let tint: Color
    let title: String
    var detail: String?
    @ViewBuilder let actions: () -> Actions

    @Environment(\.accessibilityShowBorders) private var showBorders

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: symbol)
                .foregroundStyle(tint)

            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(.callout.weight(.medium))
                if let detail, !detail.isEmpty {
                    Text(detail)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            }

            Spacer(minLength: 12)
            actions()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .glassEffect(in: .rect(cornerRadius: 14))
        .overlay {
            if showBorders {
                RoundedRectangle(cornerRadius: 14)
                    .stroke(.secondary)
            }
        }
    }
}
