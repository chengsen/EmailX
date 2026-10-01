//
//  BulkActionPanelView.swift
//  EmailX
//

import SwiftUI

struct BulkActionPanelView: View {
    @Environment(AppState.self) private var appState
    @Environment(AppEnvironment.self) private var env
    @Environment(\.undoManager) private var undoManager

    var body: some View {
        ContentUnavailableView {
            Label(
                selectionLabel(appState.selectedMessageIDs.count),
                systemImage: "envelope.stack"
            )
        } actions: {
            FlowLayout(spacing: 8) {
                Button("Archive", systemImage: "archivebox") {
                    perform { ids in
                        await env.undoService.archiveMessages(ids, undoManager: undoManager)
                    }
                }
                .buttonStyle(.bordered)

                Button("Delete", systemImage: "trash", role: .destructive) {
                    perform { ids in
                        await env.undoService.deleteMessages(ids, undoManager: undoManager)
                    }
                }
                .buttonStyle(.bordered)

                Button("Mark as Spam", systemImage: "exclamationmark.octagon") {
                    perform { ids in
                        await env.syncService.markAsJunk(ids)
                    }
                }
                .buttonStyle(.bordered)
            }
        }
    }

    private nonisolated func selectionLabel(_ n: Int) -> String {
        String(localized: "\(n) messages selected")
    }

    private func perform(op: @escaping ([UUID]) async -> Void) {
        let ids = Array(appState.selectedMessageIDs)
        appState.selectedMessageIDs = []
        Task { await op(ids) }
    }
}
