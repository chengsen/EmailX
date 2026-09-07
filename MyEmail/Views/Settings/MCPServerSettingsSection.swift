//
//  MCPServerSettingsSection.swift
//  MyEmail
//
//  Settings block for the local MCP endpoint (Advanced). Off by default —
//  turning it on exposes the whole mailbox to any local process holding the
//  token, so the copy says so plainly.
//

import AppKit
import SwiftUI

struct MCPServerSettingsSection: View {
    let server: MCPServerService

    @State private var isEnabled: Bool
    @State private var port: Int
    @State private var copiedHint = false

    init(server: MCPServerService) {
        self.server = server
        _isEnabled = State(initialValue: server.isEnabled)
        _port = State(initialValue: server.port)
    }

    var body: some View {
        Section("Agent access (MCP)") {
            Toggle("Let agents work with this mailbox", isOn: $isEnabled)
                .onChange(of: isEnabled) { _, newValue in server.isEnabled = newValue }

            // swiftlint:disable:next line_length
            Text("Runs a local endpoint on 127.0.0.1 so an agent can search, read and diagnose your mail. Sending always asks you first. Anything holding the token can read every message — keep it to tools you trust.")
                .font(.caption)
                .foregroundStyle(.secondary)

            if isEnabled {
                MCPServerStatusRow(server: server)

                LabeledContent("Port") {
                    TextField("Port", value: $port, format: .number.grouping(.never))
                        .frame(width: 80)
                        .onSubmit { server.port = port }
                }

                HStack {
                    Button(copiedHint ? "Copied" : "Copy setup command") { copySetupCommand() }
                    Button("Regenerate token") { server.regenerateToken() }
                    Spacer()
                }
            }
        }
    }

    /// One clipboard paste wires an agent up — the token never has to be
    /// read off the screen.
    private func copySetupCommand() {
        let command = """
            claude mcp add myemail --transport http \(server.endpointURL) \
            --header "Authorization: Bearer \(server.token)"
            """
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(command, forType: .string)
        copiedHint = true
        Task {
            try? await Task.sleep(for: .seconds(2))
            copiedHint = false
        }
    }
}

/// Live listener state — separate so the status text observes the service
/// without the whole section re-rendering the token fields.
private struct MCPServerStatusRow: View {
    let server: MCPServerService

    var body: some View {
        LabeledContent("Status") {
            if let error = server.lastError {
                Text(error).foregroundStyle(.red)
            } else if server.isRunning {
                Text("\(server.endpointURL) · \(server.handledCallCount) calls")
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
            } else {
                Text("Stopped").foregroundStyle(.secondary)
            }
        }
        .font(.caption)
    }
}
