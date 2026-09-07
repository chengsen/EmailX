//
//  MCPJSONValue.swift
//  MyEmail
//
//  Minimal dynamic JSON value. JSON-RPC params and tool arguments are
//  schema-less at the transport level, and `[String: Any]` is not Sendable,
//  so requests are decoded into this instead.
//

import Foundation

enum JSONValue: Codable, Sendable, Equatable {
    case null
    case bool(Bool)
    case number(Double)
    case string(String)
    case array([Self])
    case object([String: Self])

    // MARK: - Codable

    nonisolated init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() {
            self = .null
        } else if let value = try? container.decode(Bool.self) {
            self = .bool(value)
        } else if let value = try? container.decode(Double.self) {
            self = .number(value)
        } else if let value = try? container.decode(String.self) {
            self = .string(value)
        } else if let value = try? container.decode([Self].self) {
            self = .array(value)
        } else if let value = try? container.decode([String: Self].self) {
            self = .object(value)
        } else {
            throw DecodingError.dataCorruptedError(
                in: container, debugDescription: "Unsupported JSON value"
            )
        }
    }

    nonisolated func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .null:            try container.encodeNil()
        case .bool(let value): try container.encode(value)
        case .number(let value):
            // Whole numbers encode as Int so ids round-trip as `1`, not `1.0`.
            if value == value.rounded(), abs(value) < 9_007_199_254_740_992 {
                try container.encode(Int(value))
            } else {
                try container.encode(value)
            }
        case .string(let value): try container.encode(value)
        case .array(let value):  try container.encode(value)
        case .object(let value): try container.encode(value)
        }
    }

    // MARK: - Accessors

    nonisolated subscript(key: String) -> Self? {
        guard case .object(let dict) = self else { return nil }
        let value = dict[key]
        return value == .null ? nil : value
    }

    nonisolated var stringValue: String? {
        if case .string(let value) = self { return value }
        return nil
    }

    nonisolated var intValue: Int? {
        switch self {
        case .number(let value): return Int(value)
        case .string(let value): return Int(value)
        default: return nil
        }
    }

    nonisolated var boolValue: Bool? {
        if case .bool(let value) = self { return value }
        return nil
    }

    nonisolated var arrayValue: [Self]? {
        if case .array(let value) = self { return value }
        return nil
    }

    /// String array tolerant of a bare string — agents routinely send
    /// `"to": "a@b.c"` where the schema asks for a list.
    nonisolated var stringArrayValue: [String]? {
        switch self {
        case .string(let value): return [value]
        case .array(let items):  return items.compactMap(\.stringValue)
        default: return nil
        }
    }

    /// ISO-8601 or `yyyy-MM-dd` date, whichever the caller sent.
    nonisolated var dateValue: Date? {
        guard let raw = stringValue else { return nil }
        if let date = ISO8601DateFormatter().date(from: raw) { return date }
        let plain = DateFormatter()
        plain.calendar = Calendar(identifier: .gregorian)
        plain.locale = Locale(identifier: "en_US_POSIX")
        plain.timeZone = TimeZone(identifier: "UTC")
        plain.dateFormat = "yyyy-MM-dd"
        return plain.date(from: raw)
    }

    nonisolated var uuidValue: UUID? {
        stringValue.flatMap(UUID.init(uuidString:))
    }

    // MARK: - Construction helpers

    nonisolated static func int(_ value: Int) -> Self { .number(Double(value)) }

    nonisolated static func strings(_ values: [String]) -> Self {
        .array(values.map { .string($0) })
    }

    /// Drops nil entries so tool output stays compact.
    nonisolated static func compactObject(_ pairs: [String: Self?]) -> Self {
        .object(pairs.compactMapValues { $0 })
    }

    nonisolated var encoded: Data {
        (try? JSONEncoder().encode(self)) ?? Data("null".utf8)
    }

    nonisolated var prettyEncoded: String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        guard let data = try? encoder.encode(self),
              let text = String(data: data, encoding: .utf8)
        else { return "null" }
        return text
    }
}
