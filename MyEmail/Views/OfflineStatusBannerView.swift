//
//  OfflineStatusBannerView.swift
//  EmailX
//

import SwiftUI

struct OfflineStatusBannerView: View {
    @Environment(AppEnvironment.self) private var env
    @Environment(\.accessibilityShowBorders) private var showBorders

    var body: some View {
        let sync = env.syncService
        let queue = env.offlineQueue

        Group {
            if !sync.isOnline {
                notice(
                    icon: "wifi.slash",
                    text: String(localized: "Offline — \(queue.pendingCount) pending"),
                    tint: .red
                )
            } else if sync.isSyncing {
                notice(
                    icon: "arrow.triangle.2.circlepath",
                    text: String(localized: "Syncing…"),
                    tint: .secondary
                )
            } else if queue.failedCount > 0 {
                Menu {
                    Button {
                        Task {
                            await queue.retryFailed()
                            await env.syncService.drainOfflineQueueIfNeeded()
                        }
                    } label: {
                        Label("Retry failed actions", systemImage: "arrow.clockwise")
                    }

                    Button(role: .destructive) {
                        Task { await queue.discardFailed() }
                    } label: {
                        Label("Discard failed actions", systemImage: "trash")
                    }
                } label: {
                    noticeContent(
                        icon: "exclamationmark.triangle",
                        text: String(localized: "\(queue.failedCount) failed actions"),
                        tint: .orange
                    )
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
                .help("Retry or discard failed actions")
            }
        }
        .transition(.opacity)
    }

    private func notice(icon: String, text: String, tint: Color) -> some View {
        noticeContent(icon: icon, text: text, tint: tint)
            .glassEffect()
            .overlay {
                if showBorders {
                    Capsule().stroke(.secondary)
                }
            }
    }

    private func noticeContent(icon: String, text: String, tint: Color) -> some View {
        Label(text, systemImage: icon)
            .font(.caption)
            .foregroundStyle(tint)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .fixedSize()
    }
}
