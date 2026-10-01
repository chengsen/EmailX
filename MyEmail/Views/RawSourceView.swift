//
//  RawSourceView.swift
//  MyEmail
//
//  Raw RFC822 source viewer. Monospaced, read-only, copy-able.
//

import SwiftUI

// MARK: - Sheet trigger (atomic item for .sheet(item:) — rule #7)

struct SourceSheet: Identifiable {
    let id = UUID()
    let source: String?
}

// MARK: - Source viewer

struct RawSourceView: View {
    let source: String?
    let onDismiss: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Message Source")
                    .font(.headline)
                Spacer()
                if let source, !source.isEmpty {
                    Button("Copy") {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(source, forType: .string)
                    }
                }
                Button("Close") { onDismiss() }
                    .keyboardShortcut(.cancelAction)
            }
            .buttonStyle(.bordered)
            .padding(12)

            Divider()

            if let source, !source.isEmpty {
                ScrollView {
                    Text(source)
                        .font(.system(.body, design: .monospaced))
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(12)
                }
            } else {
                ContentUnavailableView(
                    "Failed to load message source",
                    systemImage: "doc.text.magnifyingglass"
                )
            }
        }
        .frame(minWidth: 500, idealWidth: 700, minHeight: 350, idealHeight: 500)
    }
}
