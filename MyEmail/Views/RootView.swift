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
        VSplitView {
            ContentView()
                .frame(maxWidth: .infinity, minHeight: 300, idealHeight: 580, maxHeight: .infinity)

            if isDebugLogVisible {
                DebugLogPanelView()
            }
        }
    }
}
