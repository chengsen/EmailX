//
//  MCPHTTPListener.swift
//  MyEmail
//
//  Loopback HTTP/1.1 front for the MCP endpoint. Deliberately not a
//  general-purpose server — it speaks the subset an MCP client actually
//  sends: one request at a time per keep-alive connection, body length
//  from Content-Length, no chunked encoding, no TLS.
//
//  Everything runs on the main queue, so NW callbacks are already on
//  MainActor and hop with `assumeIsolated` instead of a Task.
//

import Foundation
import Network

struct MCPHTTPRequest: Sendable {
    let method: String
    let path: String
    /// Header names lowercased — HTTP field names are case-insensitive.
    let headers: [String: String]
    let body: Data
}

struct MCPHTTPResponse: Sendable {
    var status: Int
    var reason: String
    var headers: [String: String] = [:]
    var body = Data()

    static func json(_ body: Data) -> Self {
        Self(
            status: 200, reason: "OK",
            headers: ["Content-Type": "application/json"],
            body: body
        )
    }

    static func empty(_ status: Int, _ reason: String) -> Self {
        Self(status: status, reason: reason)
    }

    static func text(_ status: Int, _ reason: String, _ message: String) -> Self {
        Self(
            status: status, reason: reason,
            headers: ["Content-Type": "text/plain; charset=utf-8"],
            body: Data(message.utf8)
        )
    }
}

/// Accepts loopback connections and hands complete requests to `handler`.
@MainActor
final class MCPHTTPListener {
    /// A request larger than this is a bug or an attack, not an MCP call.
    private static let maxRequestBytes = 8 * 1024 * 1024

    private var listener: NWListener?
    private var connections: [ObjectIdentifier: MCPHTTPConnection] = [:]
    private let handler: (MCPHTTPRequest) async -> MCPHTTPResponse

    /// Set when the listener fails; surfaced in Settings.
    private(set) var failureText: String?
    private(set) var isListening = false
    private(set) var connectionCount = 0

    init(handler: @escaping (MCPHTTPRequest) async -> MCPHTTPResponse) {
        self.handler = handler
    }

    // MARK: - Lifecycle

    func start(port: UInt16) throws {
        stop()
        guard let nwPort = NWEndpoint.Port(rawValue: port) else {
            throw MCPServerError.invalidPort(port)
        }

        let params = NWParameters.tcp
        // Loopback only — the endpoint exposes the whole mailbox, it must not
        // be reachable from the network even if the firewall is open.
        params.requiredInterfaceType = .loopback
        params.allowLocalEndpointReuse = true

        let listener = try NWListener(using: params, on: nwPort)
        listener.newConnectionHandler = { [weak self] connection in
            MainActor.assumeIsolated { self?.accept(connection) }
        }
        listener.stateUpdateHandler = { [weak self] state in
            MainActor.assumeIsolated { self?.listenerStateChanged(state) }
        }
        listener.start(queue: .main)
        self.listener = listener
    }

    func stop() {
        for connection in connections.values { connection.close() }
        connections.removeAll()
        connectionCount = 0
        listener?.cancel()
        listener = nil
        isListening = false
    }

    private func listenerStateChanged(_ state: NWListener.State) {
        switch state {
        case .ready:
            isListening = true
            failureText = nil
        case .failed(let error):
            isListening = false
            failureText = error.localizedDescription
            LogService.log(.error, .uiDebug, "MCP listener failed", detail: "\(error)")
        case .cancelled:
            isListening = false
        default:
            break
        }
    }

    // MARK: - Connections

    private func accept(_ connection: NWConnection) {
        let wrapper = MCPHTTPConnection(
            connection: connection,
            maxRequestBytes: Self.maxRequestBytes,
            handler: handler,
            onClose: { [weak self] key in
                MainActor.assumeIsolated {
                    guard let self else { return }
                    self.connections[key] = nil
                    self.connectionCount = self.connections.count
                }
            }
        )
        connections[ObjectIdentifier(connection)] = wrapper
        connectionCount = connections.count
        wrapper.start()
    }
}

// MARK: - Per-connection request framing

@MainActor
private final class MCPHTTPConnection {
    private let connection: NWConnection
    private let maxRequestBytes: Int
    private let handler: (MCPHTTPRequest) async -> MCPHTTPResponse
    private let onClose: (ObjectIdentifier) -> Void

    private var buffer = Data()
    /// One in-flight request per connection: a pipelined second request waits
    /// in `buffer` until the current response is written.
    private var isHandling = false
    private var isClosed = false

    init(
        connection: NWConnection,
        maxRequestBytes: Int,
        handler: @escaping (MCPHTTPRequest) async -> MCPHTTPResponse,
        onClose: @escaping (ObjectIdentifier) -> Void
    ) {
        self.connection = connection
        self.maxRequestBytes = maxRequestBytes
        self.handler = handler
        self.onClose = onClose
    }

    func start() {
        connection.stateUpdateHandler = { [weak self] state in
            MainActor.assumeIsolated {
                switch state {
                case .failed, .cancelled: self?.close()
                default: break
                }
            }
        }
        connection.start(queue: .main)
        receive()
    }

    func close() {
        guard !isClosed else { return }
        isClosed = true
        connection.cancel()
        onClose(ObjectIdentifier(connection))
    }

    private func receive() {
        connection.receive(
            minimumIncompleteLength: 1, maximumLength: 64 * 1024
        ) { [weak self] data, _, isComplete, error in
            MainActor.assumeIsolated {
                guard let self, !self.isClosed else { return }
                if let data, !data.isEmpty {
                    self.buffer.append(data)
                    if self.buffer.count > self.maxRequestBytes {
                        self.respond(.text(413, "Payload Too Large", "Request too large"),
                                     keepAlive: false)
                        return
                    }
                    self.drain()
                }
                if isComplete || error != nil {
                    self.close()
                } else {
                    self.receive()
                }
            }
        }
    }

    /// Pulls one complete request out of `buffer`, if there is one.
    private func drain() {
        guard !isHandling, !isClosed else { return }
        guard let separator = buffer.range(of: Data("\r\n\r\n".utf8)) else { return }

        guard let headText = String(
            bytes: buffer[buffer.startIndex..<separator.lowerBound], encoding: .utf8
        ) else { return respond(badRequest, keepAlive: false) }
        var lines = headText.components(separatedBy: "\r\n")
        guard !lines.isEmpty else { return respond(badRequest, keepAlive: false) }

        // Full request line or nothing: "METHOD /path HTTP/1.1". Two bare
        // words would otherwise sail through as a method and a path.
        let requestLine = lines.removeFirst().split(separator: " ", maxSplits: 2)
        guard requestLine.count == 3,
              requestLine[1].hasPrefix("/"),
              requestLine[2].hasPrefix("HTTP/")
        else { return respond(badRequest, keepAlive: false) }

        var headers: [String: String] = [:]
        for line in lines {
            guard let colon = line.firstIndex(of: ":") else { continue }
            let name = line[..<colon].trimmingCharacters(in: .whitespaces).lowercased()
            let value = line[line.index(after: colon)...].trimmingCharacters(in: .whitespaces)
            headers[name] = value
        }

        let contentLength = Int(headers["content-length"] ?? "0") ?? 0
        guard contentLength >= 0, contentLength <= maxRequestBytes else {
            return respond(badRequest, keepAlive: false)
        }
        // Wait for the rest of the body before dispatching.
        let bodyStart = separator.upperBound
        guard buffer.distance(from: bodyStart, to: buffer.endIndex) >= contentLength else { return }

        let bodyEnd = buffer.index(bodyStart, offsetBy: contentLength)
        let request = MCPHTTPRequest(
            method: String(requestLine[0]).uppercased(),
            path: String(requestLine[1]),
            headers: headers,
            body: Data(buffer[bodyStart..<bodyEnd])
        )
        // Re-base the buffer: Data slices keep the parent's indices.
        buffer = Data(buffer[bodyEnd...])

        let keepAlive = headers["connection"]?.lowercased() != "close"
        isHandling = true
        Task { @MainActor in
            let response = await handler(request)
            self.respond(response, keepAlive: keepAlive)
        }
    }

    private var badRequest: MCPHTTPResponse {
        .text(400, "Bad Request", "Malformed HTTP request")
    }

    private func respond(_ response: MCPHTTPResponse, keepAlive: Bool) {
        guard !isClosed else { return }

        var head = "HTTP/1.1 \(response.status) \(response.reason)\r\n"
        for (name, value) in response.headers.sorted(by: { $0.key < $1.key }) {
            head += "\(name): \(value)\r\n"
        }
        head += "Content-Length: \(response.body.count)\r\n"
        head += "Connection: \(keepAlive ? "keep-alive" : "close")\r\n\r\n"

        var payload = Data(head.utf8)
        payload.append(response.body)

        connection.send(content: payload, completion: .contentProcessed { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.isHandling = false
                if keepAlive {
                    // A pipelined request may already be buffered.
                    self.drain()
                } else {
                    self.close()
                }
            }
        })
    }
}
