import AppKit
import SwiftUI
import Observation
@Observable final class AppState { }
@Observable final class LogService { }
@Observable final class AppEnvironment { let logService = LogService() }
struct GeneralSettingsView: View { var body: some View { Text("General") } }
struct AccountSettingsView: View { var body: some View { Text("Accounts") } }
struct SignatureSettingsView: View { var body: some View { Text("Signatures") } }
struct RuleSettingsView: View { var body: some View { Text("Rules") } }
struct PrivacySettingsView: View { var body: some View { Text("Privacy") } }
struct AppearanceSettingsView: View { var body: some View { Text("Appearance") } }
struct AdvancedSettingsView: View { var body: some View { Text("Advanced") } }
@main struct SettingsToolbarProbe {
    @MainActor static func main() {
        _ = NSApplication.shared
        let previous = UserDefaults.standard.object(forKey: "settingsSelectedPane")
        defer {
            if let previous { UserDefaults.standard.set(previous, forKey: "settingsSelectedPane") }
            else { UserDefaults.standard.removeObject(forKey: "settingsSelectedPane") }
        }
        UserDefaults.standard.set("rules", forKey: "settingsSelectedPane")
        let controller = SettingsWindowController(appState: AppState(), environment: AppEnvironment())
        guard let window = controller.window, let toolbar = window.toolbar else { fatalError("missing toolbar") }
        precondition(window.toolbarStyle == .preference)
        precondition(!toolbar.allowsUserCustomization && !toolbar.allowsDisplayModeCustomization
                     && !toolbar.autosavesConfiguration && toolbar.isVisible)
        precondition(toolbar.items.count == SettingsCategory.allCases.count)
        precondition(window.title == SettingsCategory.rules.title)
        precondition(toolbar.selectedItemIdentifier?.rawValue == "EmailXSettings.rules")
        precondition(window.standardWindowButton(.zoomButton)?.isEnabled == false)
        precondition(window.standardWindowButton(.miniaturizeButton)?.isEnabled == false)
        for action in [#selector(NSWindow.toggleToolbarShown(_:)),
                       #selector(NSWindow.performMiniaturize(_:)),
                       #selector(NSWindow.miniaturize(_:)),
                       #selector(NSWindow.performZoom(_:)),
                       #selector(NSWindow.zoom(_:))] {
            let menuItem = NSMenuItem(title: "Fixture", action: action, keyEquivalent: "")
            precondition(!window.validateMenuItem(menuItem))
        }
        window.toggleToolbarShown(nil)
        precondition(toolbar.isVisible)
        let canonical = toolbar.itemIdentifiers
        precondition(controller.toolbarImmovableItemIdentifiers(toolbar) == Set(canonical))
        for identifier in canonical {
            precondition(!controller.toolbar(toolbar, itemIdentifier: identifier, canBeInsertedAt: 0))
            precondition(!controller.toolbar(toolbar, itemIdentifier: identifier, canBeInsertedAt: NSNotFound))
        }
        precondition(toolbar.selectedItemIdentifier?.rawValue == "EmailXSettings.rules")
        precondition(window.title == SettingsCategory.rules.title)
        let originalRulesHost = window.contentView!.subviews.first!
        for (index, category) in SettingsCategory.allCases.enumerated() {
            let item = toolbar.items[index]
            precondition(item.visibilityPriority == .high)
            precondition(NSApp.sendAction(item.action!, to: item.target, from: item))
            precondition(window.title == category.title)
            precondition(toolbar.selectedItemIdentifier == item.itemIdentifier)
            precondition(window.contentView!.subviews.filter { !$0.isHidden }.count == 1)
        }
        let rulesItem = toolbar.items[SettingsCategory.allCases.firstIndex(of: .rules)!]
        _ = NSApp.sendAction(rulesItem.action!, to: rulesItem.target, from: rulesItem)
        precondition(window.contentView!.subviews.contains(where: { $0 === originalRulesHost && !$0.isHidden }))
        let restored = SettingsWindowController(appState: AppState(), environment: AppEnvironment())
        precondition(restored.window?.title == SettingsCategory.rules.title)
        print("PASS: actual settings controller preference toolbar, all seven pane actions, selected state/title, hide protection, disabled toolbar/minimize/zoom menus, native immovable pane delegates, pane reuse and restoration")
    }
}
