//
//  AttachmentStripView.swift
//  EmailX
//
//  Native attachment strip for message reading.
//

import Quartz
import SwiftUI
import UniformTypeIdentifiers

struct AttachmentStripView: View {
    let attachments: [Attachment]
    let onRefetch: (Attachment) async -> Attachment?
    var maximumHeight: CGFloat = 140

    @State private var refetchingIDs: Set<UUID> = []
    @State private var quickLookCoordinator = QuickLookCoordinator()

    var body: some View {
        // Keep one content tree mounted when its height changes so attachment
        // state and native keyboard focus survive viewport resizing.
        ScrollView(.vertical) { attachmentContent }
            .scrollBounceBehavior(.basedOnSize)
            .frame(maxHeight: maximumHeight)
            .fixedSize(horizontal: false, vertical: true)
    }

    private var attachmentContent: some View {
        FlowLayout(spacing: 6) {
            ForEach(attachments) { att in
                attachmentChip(att)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private func attachmentChip(_ att: Attachment) -> some View {
        let isRefetching = refetchingIDs.contains(att.id)
        Button {
            Task {
                if Self.isEml(att) {
                    await openInEmlViewer(att)
                } else {
                    await quickLookAttachment(att)
                }
            }
        } label: {
            HStack(spacing: 6) {
                if isRefetching {
                    ProgressView()
                        .controlSize(.small)
                        .frame(width: 20, height: 20)
                } else {
                    Image(nsImage: fileIcon(for: att))
                        .resizable()
                        .frame(width: 20, height: 20)
                        .accessibilityHidden(true)
                }
                Text(att.filename)
                    .font(.callout)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Text(FormatHelpers.formatByteCount(att.size))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .buttonStyle(.bordered)
        .accessibilityLabel(Text(att.filename))
        .accessibilityValue(Text(FormatHelpers.formatByteCount(att.size)))
        .accessibilityHint(Text(Self.isEml(att) ? LocalizedStringKey("Open") : LocalizedStringKey("Quick Look")))
        .disabled(isRefetching)
        .help(att.filename)
        .contextMenu { attachmentMenu(att) }
    }

    @ViewBuilder
    private func attachmentMenu(_ att: Attachment) -> some View {
        Button(String(localized: "Quick Look")) {
            Task { await quickLookAttachment(att) }
        }
        Divider()
        Button(String(localized: "Open")) {
            Task { await openAttachment(att) }
        }
        Button(String(localized: "Save As…")) {
            Task { await saveAs(att) }
        }
        Button(String(localized: "Show in Finder")) {
            showInFinder(att)
        }
    }

    // MARK: - Actions

    private func quickLookAttachment(_ att: Attachment) async {
        guard let path = await ensureLocalFile(att) else { return }
        // Collect all locally available URLs for arrow-key navigation
        var allURLs: [URL] = []
        var selectedIndex = 0
        for a in attachments {
            let url: URL
            if a.id == att.id {
                url = URL(fileURLWithPath: path)
                selectedIndex = allURLs.count
            } else if let p = a.localPath, FileManager.default.fileExists(atPath: p) {
                url = URL(fileURLWithPath: p)
            } else {
                continue
            }
            allURLs.append(url)
        }
        quickLookCoordinator.show(urls: allURLs, selectedIndex: selectedIndex)
    }

    private func openAttachment(_ att: Attachment) async {
        guard let path = await ensureLocalFile(att) else { return }
        if Self.isEml(att) {
            EmlViewerService.shared.open(url: URL(fileURLWithPath: path))
        } else {
            NSWorkspace.shared.open(URL(fileURLWithPath: path))
        }
    }

    private func openInEmlViewer(_ att: Attachment) async {
        guard let path = await ensureLocalFile(att) else { return }
        EmlViewerService.shared.open(url: URL(fileURLWithPath: path))
    }

    /// True when the attachment looks like an RFC822 message — either via
    /// MIME type or the `.eml` extension on the synthesized filename.
    nonisolated private static func isEml(_ att: Attachment) -> Bool {
        if att.mimeType.lowercased() == "message/rfc822" { return true }
        return att.filename.lowercased().hasSuffix(".eml")
    }

    private func saveAs(_ att: Attachment) async {
        guard let path = await ensureLocalFile(att) else { return }
        let panel = NSSavePanel()
        panel.nameFieldStringValue = att.filename
        panel.canCreateDirectories = true
        guard panel.runModal() == .OK, let dest = panel.url else { return }
        do {
            try FileManager.default.copyItem(
                at: URL(fileURLWithPath: path), to: dest
            )
        } catch {
            LogService.log(.error, .sync, "Save attachment failed", detail: "\(error)")
        }
    }

    private func showInFinder(_ att: Attachment) {
        guard let path = att.localPath,
              FileManager.default.fileExists(atPath: path) else { return }
        NSWorkspace.shared.activateFileViewerSelecting(
            [URL(fileURLWithPath: path)]
        )
    }

    /// Return local file path, re-fetching from IMAP if file was deleted.
    private func ensureLocalFile(_ att: Attachment) async -> String? {
        if let path = att.localPath, FileManager.default.fileExists(atPath: path) {
            return path
        }
        // File missing — re-fetch from server
        refetchingIDs.insert(att.id)
        defer { refetchingIDs.remove(att.id) }
        if let updated = await onRefetch(att) {
            return updated.localPath
        }
        return nil
    }

    // MARK: - Helpers

    private func fileIcon(for att: Attachment) -> NSImage {
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
