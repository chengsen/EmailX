//
//  ContentView.swift
//  MyEmail
//
//  Main macOS 27 shell: sidebar | message list | reading pane.
//

import AppKit
import SwiftUI

struct ContentView: View {
    @Environment(AppState.self) private var appState
    @Environment(AppEnvironment.self) private var env

    var body: some View {
        Group {
            if appState.accounts.isEmpty {
                emptyState
            } else {
                WideLayoutView()
                    .overlay(alignment: .top) { banners }
            }
        }
        .transaction { $0.animation = nil }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .task { await initialSync() }
        .task { wireNotificationNavigation() }
        .onChange(of: appState.selectedSidebarItem) { _, newItem in
            guard case .folder(let folderID) = newItem else {
                env.syncService.currentlySelectedFolderID = nil
                return
            }
            // Track current selection so prefetch scope-gate can match it.
            env.syncService.currentlySelectedFolderID = folderID
            Task {
                await env.syncService.syncFolderIfNeeded(folderID: folderID)
                await env.syncService.ensureIDLEForSelected(folderID: folderID)
            }
            // Body prefetch: warm cache for the newly-opened folder.
            // Cancels any previous folder's in-flight prefetch (replace: true default).
            env.syncService.schedulePrefetch(folderID: folderID)
        }
    }

    private var emptyState: some View {
        ContentUnavailableView {
            Label("EmailX", systemImage: "envelope")
        } description: {
            Text("Add an account to start using EmailX.")
        } actions: {
            Button("Open Settings") {
                (NSApp.delegate as? AppDelegate)?.showSettings(nil)
            }
            .keyboardShortcut(.defaultAction)
        }
    }

    private var banners: some View {
        ErrorBannerView()
            .padding(.top, 1)
    }

    private func wireNotificationNavigation() {
        NotificationService.shared.onNotificationClick = { accountID, folderID, messageUID in
            appState.selectedSidebarItem = .folder(folderID)
            Task {
                let msgID = await env.syncService.messageID(uid: messageUID, folderID: folderID)
                if let msgID { appState.selectedMessageIDs = [msgID] }
            }
        }
    }

    private func initialSync() async {
        do {
            appState.accounts = try env.accountRepository.all()
            appState.rebuildAccountLookup()
        } catch {
            LogService.log(.error, .sync, "Failed to load accounts", detail: "\(error)")
            return
        }

        guard !appState.accounts.isEmpty else { return }

        appState.observeFolders()
        appState.observeAccounts()

        if appState.selectedSidebarItem == nil,
           let inbox = appState.folders.first(where: { $0.specialUse == .inbox }) {
            appState.selectedSidebarItem = .folder(inbox.id)
        }

        for account in appState.accounts {
            await env.syncService.syncAccount(account)
        }
        await env.syncService.updateDockBadge()
    }
}
