//
//  ComposeView+Prefill.swift
//  MyEmail
//
//  Reply/forward prefill for ComposeView. Builds attributed body with
//  HTML-backed <blockquote> for replies and From/Date/Subject header for
//  forwards. Separated from the main view to keep file under 500 lines.
//

import AppKit
import Foundation
import SwiftUI

extension ComposeView {

    /// Shared date formatter for attribution and forward-header lines.
    /// Cached to avoid per-invocation allocation.
    private static let replyDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter
    }()

    func prefill() {
        // Mailto needs no source Message — apply prefill regardless.
        if case .mailto(_, let prefill) = mode {
            toField = prefill.to
            ccField = prefill.cc
            bccField = prefill.bcc
            subjectField = prefill.subject
            if !prefill.body.isEmpty {
                attributedBody = NSAttributedString(
                    string: prefill.body,
                    attributes: RichTextSupport.defaultTypingAttributes
                )
            }
            return
        }
        guard let msg = message else { return }
        switch mode {
        case .newMessage, .mailto:
            break
        case .reply:
            toField = msg.replyToAddresses.first ?? msg.fromAddress
            subjectField = prefixed(msg.subject, prefix: "Re:")
            attributedBody = replyScaffold(for: msg)
            scheduleQuoteInsertion(for: msg, asQuote: true)
        case .replyAll:
            toField = msg.replyToAddresses.first ?? msg.fromAddress
            let others = (msg.toAddresses + msg.ccAddresses)
                .filter { !$0.isEmpty
                    && $0.caseInsensitiveCompare(selectedAccount.email) != .orderedSame }
            ccField = others.joined(separator: ", ")
            subjectField = prefixed(msg.subject, prefix: "Re:")
            attributedBody = replyScaffold(for: msg)
            scheduleQuoteInsertion(for: msg, asQuote: true)
        case .forward:
            subjectField = prefixed(msg.subject, prefix: "Fwd:")
            attributedBody = forwardScaffold(for: msg)
            scheduleQuoteInsertion(for: msg, asQuote: false)
        }
    }

    /// Prepend `prefix` only if the subject does not already carry it
    /// (case-insensitive; tolerates variants like "RE:", "re:", "Re[2]:").
    private func prefixed(_ subject: String, prefix: String) -> String {
        let trimmed = subject.trimmingCharacters(in: .whitespaces)
        let base = prefix.lowercased().trimmingCharacters(in: CharacterSet(charactersIn: ":"))
        let leading = trimmed.lowercased()
        if leading.hasPrefix(base + ":") || leading.hasPrefix(base + "[") {
            return subject
        }
        return "\(prefix) \(subject)"
    }

    /// Reply scaffold: two blank lines for the cursor + attribution line.
    /// The quote itself arrives via scheduleQuoteInsertion.
    private func replyScaffold(for msg: Message) -> NSAttributedString {
        let attrs = RichTextSupport.defaultTypingAttributes
        let out = NSMutableAttributedString()
        out.append(NSAttributedString(string: "\n\n", attributes: attrs))
        out.append(NSAttributedString(string: attribution(msg) + "\n", attributes: attrs))
        return out
    }

    /// Forward scaffold: banner + header block. Body arrives async.
    private func forwardScaffold(for msg: Message) -> NSAttributedString {
        let attrs = RichTextSupport.defaultTypingAttributes
        let out = NSMutableAttributedString()
        out.append(NSAttributedString(
            string: "\n\n---------- Forwarded message ----------\n",
            attributes: attrs
        ))
        out.append(NSAttributedString(string: forwardHeader(msg) + "\n\n", attributes: attrs))
        return out
    }

    /// Insert the quoted original off the first paint: the WebKit HTML
    /// importer is main-thread-only, so running it in prefill() froze the
    /// window open (Thunderbird also streams the quote in asynchronously).
    /// Inserted before the signature — applySelectedSignature() runs first
    /// in onAppear and appends at the end. User typing is safe: the caret
    /// sits at the top, insertion happens below it.
    private func scheduleQuoteInsertion(for msg: Message, asQuote: Bool) {
        Task { @MainActor in
            var quote = parsedBody(msg)
            if asQuote {
                // Mail.app / Thunderbird convention: indentation + muted color
                // as paragraph style instead of a nested-<html> blockquote.
                quote = RichTextSupport.applyQuoteStyle(to: quote)
            }
            guard quote.length > 0 else { return }
            let merged = NSMutableAttributedString(attributedString: attributedBody)
            let at = signatureRanges(in: merged).first?.location ?? merged.length
            merged.insert(quote, at: at)
            attributedBody = merged
        }
    }

    /// Original body as attributed text: parsed HTML when present, plain
    /// text otherwise.
    private func parsedBody(_ msg: Message) -> NSAttributedString {
        if let html = msg.bodyHTML, !html.isEmpty,
           let parsed = RichTextSupport.attributedFromHTML(html) {
            return parsed
        }
        return NSAttributedString(
            string: msg.bodyText ?? "",
            attributes: RichTextSupport.defaultTypingAttributes
        )
    }

    /// RFC 3676 / common MUA attribution line: "On <date>, <sender> wrote:".
    private func attribution(_ msg: Message) -> String {
        let sender: String = {
            if let name = msg.fromName, !name.isEmpty { return "\(name) <\(msg.fromAddress)>" }
            return msg.fromAddress
        }()
        return String(
            format: String(localized: "On %@, %@ wrote:"),
            Self.replyDateFormatter.string(from: msg.date),
            sender
        )
    }

    private func forwardHeader(_ msg: Message) -> String {
        var lines: [String] = []
        lines.append("From: \(msg.fromName.map { "\($0) <\(msg.fromAddress)>" } ?? msg.fromAddress)")
        lines.append("Date: \(Self.replyDateFormatter.string(from: msg.date))")
        lines.append("Subject: \(msg.subject)")
        if !msg.toAddresses.isEmpty {
            lines.append("To: \(msg.toAddresses.joined(separator: ", "))")
        }
        if !msg.ccAddresses.isEmpty {
            lines.append("Cc: \(msg.ccAddresses.joined(separator: ", "))")
        }
        return lines.joined(separator: "\n")
    }
}
