//
//  FormatHelpers.swift
//  MyEmail
//
//  Shared formatting utilities.
//

import Foundation

nonisolated enum FormatHelpers {
    /// Human-readable byte count (B/KB/MB). Dash for zero/negative.
    static func formatByteCount(_ bytes: Int) -> String {
        guard bytes > 0 else { return "—" }
        return Int64(bytes).formatted(.byteCount(style: .file))
    }
}
