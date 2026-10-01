//
//  EmptyStateView.swift
//  EmailX
//

import SwiftUI

struct EmptyStateView: View {
    let icon: String
    let message: String
    var actionLabel: String?
    var action: (() -> Void)?

    var body: some View {
        ContentUnavailableView {
            Label {
                Text(message)
            } icon: {
                Image(systemName: icon)
            }
        } actions: {
            if let actionLabel, let action {
                Button(actionLabel, action: action)
            }
        }
    }
}
