//
//  SettingsWindowController.swift
//  EmailX
//
//  AppKit preference toolbar owns pane navigation. SwiftUI supplies the forms.
//

import AppKit
import SwiftUI

@MainActor
final class SettingsWindowController: NSWindowController, NSWindowDelegate, NSToolbarDelegate {
    private static let selectedPaneKey = "settingsSelectedPane"
    private let appState: AppState
    private let environment: AppEnvironment
    private let paneContainer = NSView()
    private var paneViews: [SettingsCategory: NSView] = [:]
    private var settingsToolbar: NSToolbar?

    init(appState: AppState, environment: AppEnvironment) {
        self.appState = appState
        self.environment = environment

        let window = SettingsWindow(
            contentRect: NSRect(x: 0, y: 0, width: 820, height: 620),
            styleMask: [.titled, .closable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.minSize = NSSize(width: 760, height: 560)
        window.toolbarStyle = .preference
        window.autorecalculatesKeyViewLoop = true
        window.collectionBehavior = [.fullScreenNone]
        window.tabbingMode = .disallowed
        window.standardWindowButton(.miniaturizeButton)?.isEnabled = false
        window.standardWindowButton(.zoomButton)?.isEnabled = false
        window.setFrameAutosaveName("EmailXSettingsWindow")
        window.isReleasedWhenClosed = false
        window.contentView = paneContainer

        super.init(window: window)
        window.delegate = self

        let toolbar = NSToolbar(identifier: "EmailXSettingsToolbar")
        toolbar.delegate = self
        toolbar.allowsUserCustomization = false
        toolbar.allowsDisplayModeCustomization = false
        toolbar.autosavesConfiguration = false
        toolbar.displayMode = .iconAndLabel
        window.toolbar = toolbar
        settingsToolbar = toolbar

        let restored = UserDefaults.standard.string(forKey: Self.selectedPaneKey)
            .flatMap(SettingsCategory.init(rawValue:)) ?? .general
        selectPane(restored)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    func show() {
        guard let window else { return }
        if !window.isVisible {
            window.center()
        }
        showWindow(nil)
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    private func selectPane(_ category: SettingsCategory) {
        guard let window else { return }
        // End field editing before hiding its pane. Keep each visited hosting
        // view mounted so switching panes preserves unsaved rule/account edits.
        window.makeFirstResponder(nil)
        if paneViews[category] == nil {
            let root = SettingsPaneView(category: category)
                .environment(appState)
                .environment(environment)
                .environment(environment.logService)
            let host = NSHostingView(rootView: root)
            host.translatesAutoresizingMaskIntoConstraints = false
            paneContainer.addSubview(host)
            NSLayoutConstraint.activate([
                host.leadingAnchor.constraint(equalTo: paneContainer.leadingAnchor),
                host.trailingAnchor.constraint(equalTo: paneContainer.trailingAnchor),
                host.topAnchor.constraint(equalTo: paneContainer.topAnchor),
                host.bottomAnchor.constraint(equalTo: paneContainer.bottomAnchor)
            ])
            paneViews[category] = host
        }
        for (pane, view) in paneViews {
            view.isHidden = pane != category
        }
        window.title = category.title
        settingsToolbar?.selectedItemIdentifier = itemIdentifier(for: category)
        UserDefaults.standard.set(category.rawValue, forKey: Self.selectedPaneKey)
        window.recalculateKeyViewLoop()
    }

    private func itemIdentifier(for category: SettingsCategory) -> NSToolbarItem.Identifier {
        NSToolbarItem.Identifier("EmailXSettings.\(category.rawValue)")
    }

    private var paneIdentifiers: [NSToolbarItem.Identifier] {
        SettingsCategory.allCases.map(itemIdentifier)
    }

    func toolbarDefaultItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        paneIdentifiers
    }

    func toolbarAllowedItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        paneIdentifiers
    }

    func toolbarSelectableItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        paneIdentifiers
    }

    func toolbarImmovableItemIdentifiers(_ toolbar: NSToolbar) -> Set<NSToolbarItem.Identifier> {
        Set(paneIdentifiers)
    }

    func toolbar(
        _ toolbar: NSToolbar,
        itemIdentifier: NSToolbarItem.Identifier,
        canBeInsertedAt index: Int
    ) -> Bool {
        false
    }

    func toolbar(
        _ toolbar: NSToolbar,
        itemForItemIdentifier identifier: NSToolbarItem.Identifier,
        willBeInsertedIntoToolbar flag: Bool
    ) -> NSToolbarItem? {
        guard let category = SettingsCategory.allCases.first(where: { itemIdentifier(for: $0) == identifier }) else {
            return nil
        }
        let item = NSToolbarItem(itemIdentifier: identifier)
        item.label = category.title
        item.paletteLabel = category.title
        item.toolTip = category.title
        item.image = NSImage(systemSymbolName: category.icon, accessibilityDescription: category.title)
        item.target = self
        item.action = #selector(changePane(_:))
        item.tag = SettingsCategory.allCases.firstIndex(of: category) ?? 0
        item.visibilityPriority = .high
        return item
    }

    @objc private func changePane(_ sender: NSToolbarItem) {
        guard SettingsCategory.allCases.indices.contains(sender.tag) else { return }
        selectPane(SettingsCategory.allCases[sender.tag])
    }

    func windowDidUpdate(_ notification: Notification) {
        guard let window, let toolbar = settingsToolbar else { return }
        if window.toolbar !== toolbar { window.toolbar = toolbar }
        if !toolbar.isVisible { toolbar.isVisible = true }
    }
}

/// Settings navigation must stay visible; this window has no hide-toolbar action.
private final class SettingsWindow: NSWindow {
    override func toggleToolbarShown(_ sender: Any?) { }

    override func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        switch menuItem.action {
        case #selector(NSWindow.toggleToolbarShown(_:)),
             #selector(NSWindow.performMiniaturize(_:)),
             #selector(NSWindow.miniaturize(_:)),
             #selector(NSWindow.performZoom(_:)),
             #selector(NSWindow.zoom(_:)):
            return false
        default:
            return super.validateMenuItem(menuItem)
        }
    }
}
