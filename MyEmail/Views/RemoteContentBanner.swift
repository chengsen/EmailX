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

    @Environment(\.accessibilityShowBorders) private var showBorders

    var body: some View {
        HStack(spacing: 10) {
            Label("Remote images blocked", systemImage: "shield.lefthalf.filled")
                .foregroundStyle(.secondary)

            Spacer()

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
            .buttonStyle(.glass)
            .controlSize(.small)
            .fixedSize()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .glassEffect(in: .rect(cornerRadius: 12))
        .overlay {
            if showBorders {
                RoundedRectangle(cornerRadius: 12)
                    .stroke(.secondary)
            }
        }
        .padding(.horizontal, 12)
        .padding(.top, 8)
    }
}
