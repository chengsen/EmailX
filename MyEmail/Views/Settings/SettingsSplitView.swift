//
//  SettingsSplitView.swift
//  EmailX
//
//  Native settings panes hosted by SettingsWindowController.
//  Pane navigation belongs to the window's preference-style NSToolbar.
//

import SwiftUI

enum SettingsCategory: String, Hashable, CaseIterable, Identifiable {
    case general, accounts, signatures, rules, privacy, appearance, advanced

    var id: Self { self }

    var title: String {
        switch self {
        case .general:    return String(localized: "General")
        case .accounts:   return String(localized: "Accounts")
        case .signatures: return String(localized: "Signatures")
        case .rules:      return String(localized: "Rules")
        case .privacy:    return String(localized: "Privacy")
        case .appearance: return String(localized: "Appearance")
        case .advanced:   return String(localized: "Advanced")
        }
    }

    var icon: String {
        switch self {
        case .general:    return "gearshape"
        case .accounts:   return "at"
        case .signatures: return "signature"
        case .rules:      return "line.3.horizontal.decrease.circle"
        case .privacy:    return "hand.raised"
        case .appearance: return "paintbrush"
        case .advanced:   return "gearshape.2"
        }
    }
}

struct SettingsPaneView: View {
    let category: SettingsCategory

    var body: some View {
        detailView
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    @ViewBuilder
    private var detailView: some View {
        switch category {
        case .general:    GeneralSettingsView()
        case .accounts:   AccountSettingsView()
        case .signatures: SignatureSettingsView()
        case .rules:      RuleSettingsView()
        case .privacy:    PrivacySettingsView()
        case .appearance: AppearanceSettingsView()
        case .advanced:   AdvancedSettingsView()
        }
    }
}
