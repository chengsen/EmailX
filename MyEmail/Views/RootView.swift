//
//  RootView.swift
//  MyEmail
//
//  Main window content: ContentView + bottom DebugLogPanelView.
//  Hosted inside MainWindowController's NSHostingView.
//

import SwiftUI

struct RootView: View {
    @AppStorage("debugLogPanelVisible") private var isDebugLogVisible: Bool = false

    var body: some View {
        VStack(spacing: 0) {
            ContentView()
                .frame(maxWidth: .infinity, maxHeight: .infinity)

            if isDebugLogVisible {
                Divider()
                DebugLogPanelView()
            }
        }
    }
}
