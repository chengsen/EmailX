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
    var maximumHeight: CGFloat = 140

    var body: some View {
        // Keep every attachment reachable without letting a large batch
        // consume the body editor. A single row keeps its natural height.
        ViewThatFits(in: .vertical) {
            attachmentFlow
            ScrollView(.vertical) {
                attachmentFlow
            }
            .scrollIndicators(.automatic)
        }
        .frame(maxHeight: maximumHeight)
    }

    private var attachmentFlow: some View {
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
                    .truncationMode(.middle)
                    .help(att.filename)
                Text(FormatHelpers.formatByteCount(Int(att.size)))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(Text(att.filename))
            .accessibilityValue(Text(FormatHelpers.formatByteCount(Int(att.size))))

            Button {
                onRemove(att)
            } label: {
                Image(systemName: "xmark")
                    .frame(minWidth: 20, minHeight: 20)
            }
            .buttonStyle(.bordered)
            .controlSize(.regular)
            .help("Remove attachment")
            .accessibilityLabel(Text("Remove attachment"))
            .accessibilityValue(Text(att.filename))
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
