//
//  RemoteContentBanner.swift
//  EmailX
//

import SwiftUI
import SwiftMail

struct RemoteContentBanner: View {
    let senderEmail: String
    let onAllow: () -> Void
    let onTrustSender: () -> Void

    var body: some View {
        GroupBox {
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 12) {
                    noticeLabel
                    Spacer(minLength: 12)
                    loadMenu
                }
                VStack(alignment: .leading, spacing: 8) {
                    noticeLabel
                    loadMenu
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.top, 8)
    }

    private var noticeLabel: some View {
        Label("Remote images blocked", systemImage: "shield.lefthalf.filled")
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
    }

    private var loadMenu: some View {
        Menu {
            Button("Load remote content", action: onAllow)
            Divider()
            Button("Always load from \(EmailAddress.emailOnly(from: senderEmail))",
                   action: onTrustSender)
        } label: {
            Text("Load")
        } primaryAction: {
            onAllow()
        }
        .buttonStyle(.bordered)
        .controlSize(.small)
        .fixedSize()
        .accessibilityLabel(Text("Load remote content"))
    }
}
