//
//  ComposeAttachmentsStripView.swift
//  EmailX
//

import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct ComposeAttachmentsStripView: View {
    let attachments: [ComposeAttachment]
    let onRemove: (ComposeAttachment) -> Void

    var body: some View {
        FlowLayout(spacing: 8) {
            ForEach(attachments) { att in
                chip(att)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func chip(_ att: ComposeAttachment) -> some View {
        HStack(spacing: 8) {
            Image(nsImage: fileIcon(for: att))
                .resizable()
                .accessibilityHidden(true)
                .aspectRatio(contentMode: .fit)
                .frame(width: 20, height: 20)

            VStack(alignment: .leading, spacing: 1) {
                Text(att.filename)
                    .font(.callout)
                    .lineLimit(1)
                Text(FormatHelpers.formatByteCount(Int(att.size)))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Button {
                onRemove(att)
            } label: {
                Image(systemName: "xmark")
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .help("Remove attachment")
            .accessibilityLabel(Text("Remove attachment"))
            .accessibilityHint(Text(att.filename))
        }
        .padding(.leading, 10)
        .padding(.trailing, 6)
        .padding(.vertical, 7)
        .accessibilityElement(children: .contain)
    }

    private func fileIcon(for att: ComposeAttachment) -> NSImage {
        let ext = (att.filename as NSString).pathExtension
        if !ext.isEmpty, let utType = UTType(filenameExtension: ext) {
            return NSWorkspace.shared.icon(for: utType)
        }
        if let utType = UTType(mimeType: att.mimeType) {
            return NSWorkspace.shared.icon(for: utType)
        }
        return NSWorkspace.shared.icon(for: .data)
    }
}
