//
//  SearchQueryParser.swift
//  MyEmail
//
//  Tokenizer + state-machine parser for search bar input.
//  Grammar:
//    term            := word | quoted | negation | operator_expr
//    negation        := "-" word | "-" quoted | "-" operator_expr
//    quoted          := "\"" .* "\""
//    operator_expr   := key ":" value
//    key             := from|to|cc|bcc|subject|body|list|in|before|after|
//                       larger|smaller|is|has
//    value           := word | quoted
//
//  Multi-value operators (from/to/cc/bcc) accept repetition and
//  comma-separated lists. `from:alice,bob from:carol` → [alice, bob, carol].
//

import Foundation

enum SearchQueryParser {

    nonisolated static let knownOperators: Set<String> = [
        "from", "to", "cc", "bcc",
        "subject", "body", "list", "in",
        "before", "after", "larger", "smaller",
        "is", "has",
    ]

    /// Parse raw search text into a structured SearchQuery.
    nonisolated static func parse(_ raw: String) -> SearchQuery {
        let tokens = tokenize(raw)
        var query = SearchQuery()

        for token in tokens {
            switch token {
            case .word(let value, let negated):
                if negated { query.excludes.append(value) } else { query.freetext.append(value) }
            case .phrase(let value, let negated):
                if negated { query.excludes.append(value) } else { query.phrases.append(value) }
            case .op(let key, let value, let negated):
                apply(key: key, value: value, negated: negated, to: &query)
            }
        }

        return query
    }

    // MARK: - Apply operator

    /// Routes an operator to the group that owns it. Split by operator family
    /// rather than one flat switch: each group has its own value semantics —
    /// addresses accumulate and split on commas, text fields hold a single
    /// value, filters parse their value into a date, size or enum.
    nonisolated private static func apply(
        key: String, value: String, negated: Bool, to query: inout SearchQuery
    ) {
        if negated {
            applyNegated(key: key, value: value, to: &query)
        } else if !applyAddress(key: key, value: value, to: &query),
                  !applyText(key: key, value: value, to: &query) {
            applyFilter(key: key, value: value, to: &query)
        }
    }

    /// Negated field operators map to typed exclude lists so we can emit
    /// proper `NOT col:value` in FTS5 MATCH and `.not(.from(...))` on the
    /// server. Unknown keys drop into plain excludes for safety.
    nonisolated private static func applyNegated(
        key: String, value: String, to query: inout SearchQuery
    ) {
        switch key {
        case "from": query.excludeFrom.append(contentsOf: splitCSV(value))
        case "to": query.excludeTo.append(contentsOf: splitCSV(value))
        case "cc": query.excludeCc.append(contentsOf: splitCSV(value))
        case "bcc": query.excludeBcc.append(contentsOf: splitCSV(value))
        case "subject": query.excludeSubject.append(value)
        case "body": query.excludeBody.append(value)
        default: query.excludes.append("\(key):\(value)")
        }
    }

    /// Address operators repeat and accept comma-separated lists:
    /// `from:alice,bob from:carol` → [alice, bob, carol].
    /// Returns false when `key` belongs to another group.
    nonisolated private static func applyAddress(
        key: String, value: String, to query: inout SearchQuery
    ) -> Bool {
        switch key {
        case "from": query.from.append(contentsOf: splitCSV(value))
        case "to": query.to.append(contentsOf: splitCSV(value))
        case "cc": query.cc.append(contentsOf: splitCSV(value))
        case "bcc": query.bcc.append(contentsOf: splitCSV(value))
        default: return false
        }
        return true
    }

    /// Single-valued text operators — a repeat replaces the previous value.
    nonisolated private static func applyText(
        key: String, value: String, to query: inout SearchQuery
    ) -> Bool {
        switch key {
        case "subject": query.subject = value
        case "body": query.body = value
        case "list": query.listID = value.lowercased()
        case "in": query.folderName = value
        default: return false
        }
        return true
    }

    /// Operators whose value is parsed into a date, a byte count or an enum.
    /// An unparseable value leaves the field nil, so `before:garbage` narrows
    /// nothing instead of matching everything.
    nonisolated private static func applyFilter(
        key: String, value: String, to query: inout SearchQuery
    ) {
        switch key {
        case "before": query.before = parseDate(value)
        case "after": query.after = parseDate(value)
        case "larger": query.largerThan = parseSize(value)
        case "smaller": query.smallerThan = parseSize(value)
        case "is": query.isFilter = SearchQuery.IsFilter(rawValue: value.lowercased())
        case "has": query.hasFilter = SearchQuery.HasFilter(rawValue: value.lowercased())
        default: break
        }
    }

    nonisolated private static func splitCSV(_ value: String) -> [String] {
        value.split(separator: ",").map {
            $0.trimmingCharacters(in: .whitespaces)
        }.filter { !$0.isEmpty }
    }

    // MARK: - Date parsing

    /// Parse absolute `YYYY-MM-DD` / `YYYY/MM/DD` or relative `7d`/`2w`/`3m`/`1y`.
    nonisolated static func parseDate(_ raw: String) -> Date? {
        let trimmed = raw.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return nil }

        // Relative: "Nd", "Nw", "Nm", "Ny"
        if let last = trimmed.last,
           "dwmy".contains(last),
           let n = Int(trimmed.dropLast()), n > 0 {
            let cal = Calendar(identifier: .gregorian)
            let component: Calendar.Component = switch last {
            case "d": .day
            case "w": .weekOfYear
            case "m": .month
            default: .year
            }
            return cal.date(byAdding: component, value: -n, to: Date())
        }

        // Absolute formats.
        let formats = ["yyyy-MM-dd", "yyyy/MM/dd", "dd.MM.yyyy"]
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "UTC")
        for fmt in formats {
            formatter.dateFormat = fmt
            if let date = formatter.date(from: trimmed) { return date }
        }
        return nil
    }

    // MARK: - Size parsing

    /// Parse `5M`, `100k`, `2G`, `1024` (bytes). Case-insensitive.
    nonisolated static func parseSize(_ raw: String) -> Int? {
        let s = raw.trimmingCharacters(in: .whitespaces).lowercased()
        guard !s.isEmpty else { return nil }
        guard let last = s.last else { return nil }

        let multiplier: Int
        let digitsPart: String

        switch last {
        case "k": multiplier = 1024; digitsPart = String(s.dropLast())
        case "m": multiplier = 1024 * 1024; digitsPart = String(s.dropLast())
        case "g": multiplier = 1024 * 1024 * 1024; digitsPart = String(s.dropLast())
        default: multiplier = 1; digitsPart = s
        }

        guard let n = Double(digitsPart), n >= 0 else { return nil }
        return Int(n * Double(multiplier))
    }

    // MARK: - Tokenizer

    private enum Token {
        case word(String, negated: Bool)
        case phrase(String, negated: Bool)
        case op(key: String, value: String, negated: Bool)
    }

    /// Split input respecting quotes. `from:"Anton K" -spam "hello world"` →
    ///  [.op("from", "Anton K", false), .word("spam", true), .phrase("hello world", false)]
    nonisolated private static func tokenize(_ raw: String) -> [Token] {
        var tokens: [Token] = []
        var cursor = raw.startIndex
        let end = raw.endIndex

        while cursor < end {
            cursor = skipWhitespace(raw, from: cursor, end: end)
            guard cursor < end else { break }

            let (negated, afterNegation) = readNegation(raw, from: cursor, end: end)
            cursor = afterNegation

            // A recognized operator consumes its value even when that value is
            // empty (`from:` alone), so the scan advances either way.
            if let (token, next) = readOperator(raw, from: cursor, end: end, negated: negated) {
                if let token { tokens.append(token) }
                cursor = next
                continue
            }

            let (token, next) = readTerm(raw, from: cursor, end: end, negated: negated)
            if let token { tokens.append(token) }
            cursor = next
        }

        return tokens
    }

    nonisolated private static func skipWhitespace(
        _ raw: String, from start: String.Index, end: String.Index
    ) -> String.Index {
        var cursor = start
        while cursor < end, raw[cursor].isWhitespace {
            cursor = raw.index(after: cursor)
        }
        return cursor
    }

    /// A leading `-` negates the next term, but only when something follows it:
    /// a bare `-` is an ordinary word.
    nonisolated private static func readNegation(
        _ raw: String, from start: String.Index, end: String.Index
    ) -> (negated: Bool, next: String.Index) {
        guard raw[start] == "-" else { return (false, start) }
        let next = raw.index(after: start)
        guard next < end, !raw[next].isWhitespace else { return (false, start) }
        return (true, next)
    }

    /// Parses `key:value` when `key` is a known operator. Returns nil when the
    /// run is not an operator at all, so the caller falls back to a plain term.
    /// The inner token is nil for a recognized key with an empty value.
    nonisolated private static func readOperator(
        _ raw: String, from start: String.Index, end: String.Index, negated: Bool
    ) -> (token: Token?, next: String.Index)? {
        guard let colon = findColon(raw, from: start, end: end) else { return nil }
        let key = String(raw[start..<colon]).lowercased()
        guard knownOperators.contains(key) else { return nil }

        let (value, next) = readValue(raw, from: raw.index(after: colon), end: end)
        guard !value.isEmpty else { return (nil, next) }
        return (.op(key: key, value: value, negated: negated), next)
    }

    /// Colon ending the operator key, searched only within the contiguous
    /// non-whitespace run and only before any quote — `"a:b"` is a phrase,
    /// not an operator.
    nonisolated private static func findColon(
        _ raw: String, from start: String.Index, end: String.Index
    ) -> String.Index? {
        var cursor = start
        while cursor < end, !raw[cursor].isWhitespace {
            if raw[cursor] == ":" { return cursor }
            if raw[cursor] == "\"" { return nil }
            cursor = raw.index(after: cursor)
        }
        return nil
    }

    /// Everything that is not an operator: a quoted phrase or a bare word.
    nonisolated private static func readTerm(
        _ raw: String, from start: String.Index, end: String.Index, negated: Bool
    ) -> (token: Token?, next: String.Index) {
        if start < end, raw[start] == "\"" {
            let (value, next) = readQuoted(raw, from: start, end: end)
            return (value.isEmpty ? nil : .phrase(value, negated: negated), next)
        }
        let (value, next) = readWord(raw, from: start, end: end)
        return (value.isEmpty ? nil : .word(value, negated: negated), next)
    }

    /// Read operator value: may be quoted or plain word.
    nonisolated private static func readValue(
        _ raw: String, from start: String.Index, end: String.Index
    ) -> (String, String.Index) {
        guard start < end else { return ("", start) }
        if raw[start] == "\"" {
            return readQuoted(raw, from: start, end: end)
        }
        return readWord(raw, from: start, end: end)
    }

    nonisolated private static func readQuoted(
        _ raw: String, from start: String.Index, end: String.Index
    ) -> (String, String.Index) {
        // Expect raw[start] == "\""
        guard start < end, raw[start] == "\"" else { return ("", start) }
        var i = raw.index(after: start)
        let valueStart = i
        while i < end, raw[i] != "\"" {
            i = raw.index(after: i)
        }
        let value = String(raw[valueStart..<i])
        let next = i < end ? raw.index(after: i) : end
        return (value, next)
    }

    nonisolated private static func readWord(
        _ raw: String, from start: String.Index, end: String.Index
    ) -> (String, String.Index) {
        var i = start
        while i < end, !raw[i].isWhitespace {
            i = raw.index(after: i)
        }
        return (String(raw[start..<i]), i)
    }
}
