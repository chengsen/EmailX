//
//  GeneralSettingsView.swift
//  MyEmail
//
//  General preferences: check interval, default account, start behavior.
//

import SwiftUI

struct GeneralSettingsView: View {
    @AppStorage("checkIntervalMinutes") private var checkInterval: Int = 5
    @AppStorage("markAsReadOnSelect") private var markAsReadOnSelect = true
    @AppStorage("showUnifiedInbox") private var showUnifiedInbox = true
    @AppStorage("confirmDelete") private var confirmDelete = false
    @AppStorage("windowLayout") private var layout: String = "wide"

    @State private var language: String = {
        guard let id = Bundle.main.bundleIdentifier,
              let languages = UserDefaults.standard.persistentDomain(forName: id)?["AppleLanguages"] as? [String],
              let first = languages.first else { return "system" }
        if first.hasPrefix("zh-Hans") { return "zh-Hans" }
        if first.hasPrefix("en") { return "en" }
        return "system"
    }()

    var body: some View {
        Form {
            Section("Language") {
                Picker("Application language", selection: $language) {
                    Text("Follow macOS").tag("system")
                    Text(verbatim: "简体中文").tag("zh-Hans")
                    Text(verbatim: "English").tag("en")
                }
                .onChange(of: language) { _, value in
                    // Native bundle localization also covers AppKit menus. Apply on
                    // next launch rather than mixing live SwiftUI and cached menus.
                    if value == "system" {
                        UserDefaults.standard.removeObject(forKey: "AppleLanguages")
                    } else {
                        UserDefaults.standard.set([value], forKey: "AppleLanguages")
                    }
                }
                Text("Changes take effect the next time you open EmailX.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Section("Layout") {
                Picker("Window layout", selection: $layout) {
                    Text("Wide").tag("wide")
                    Text("Classic").tag("classic")
                }
            }

            Section("Sync") {
                Picker("Check for new mail every", selection: $checkInterval) {
                    Text("1 minute").tag(1)
                    Text("5 minutes").tag(5)
                    Text("15 minutes").tag(15)
                    Text("30 minutes").tag(30)
                }
            }

            Section("Reading") {
                Toggle("Mark messages as read when selected", isOn: $markAsReadOnSelect)
            }

            Section("Sidebar") {
                Toggle("Show Unified Inbox", isOn: $showUnifiedInbox)
            }

            Section("Safety") {
                Toggle("Confirm before deleting messages", isOn: $confirmDelete)
            }
        }
        .formStyle(.grouped)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
