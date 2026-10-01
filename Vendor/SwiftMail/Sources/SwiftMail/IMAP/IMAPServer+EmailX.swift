import Foundation
import NIOIMAPCore

// Ponytail: keep the application adapter on the pinned upstream implementation.
// Replace this file when upstream exposes equivalent delta/raw-byte APIs.
extension IMAPServer {
    public var supportsCondStore: Bool { capabilities.containsCapabilityIgnoringCase(.condStore) }
    public var supportsQResync: Bool { !emailXQResyncUnavailable && capabilities.containsCapabilityIgnoringCase(.qresync) }

    public func selectMailboxWithQResync(
        _ path: String, uidValidity: UInt32, modSeq: UInt64, knownUIDs: Set<UInt32>? = nil
    ) async throws -> Mailbox.Selection {
        guard let checkpoint = ModificationSequenceValue(exactly: modSeq), modSeq > 0 else {
            throw IMAPError.invalidArgument("Invalid MODSEQ checkpoint")
        }
        do {
            let enabled = try await enable([.qresync])
            guard enabled.contains(.qresync) else { throw IMAPError.commandNotSupported("QRESYNC not enabled") }
        } catch {
            // Do not enter the QRESYNC deletion path after negotiating it failed.
            emailXQResyncUnavailable = true
            throw error
        }
        do {
            let result = try await selectMailbox(path, resyncingFrom: UIDValidity(uidValidity), modificationSequence: checkpoint)
            var selection = result.selection
            selection.vanishedUIDs = Set(result.vanishedEarlier.toArray().map { $0.value }).union(result.vanished.toArray().map { $0.value })
            return selection
        } catch {
            emailXQResyncUnavailable = true
            throw error
        }
    }

    public func fetchMessageInfos(
        uidRange: PartialRangeFrom<UID>, options: FetchMessageInfoOptions,
        changedSince: UInt64
    ) async throws -> [MessageInfo] {
        try await fetchDelta(using: UIDSet(uidRange), options: options, changedSince: changedSince)
    }

    public func fetchFlagsOnly(
        using set: UIDSet, changedSince: UInt64? = nil
    ) async throws -> [MessageInfo] {
        try await fetchDelta(using: set, options: .uidFlagsOnly, changedSince: changedSince)
    }

    private func fetchDelta(
        using set: UIDSet, options: FetchMessageInfoOptions, changedSince: UInt64?
    ) async throws -> [MessageInfo] {
        if let value = changedSince, ModificationSequenceValue(exactly: value) == nil {
            throw IMAPError.invalidArgument("Invalid MODSEQ checkpoint")
        }
        return try await executeCommand(FetchMessageInfoCommand(
            identifierSet: set, options: options, changedSince: changedSince
        ))
    }

    public func fetchRawMessageChunked(identifier: UID) async throws -> Data {
        let chunkSize = 256 * 1024
        guard let info = try await fetchMessageInfo(for: identifier, options: [.size]),
              let size = info.size, size >= 0 else {
            throw IMAPError.fetchFailed("Message size unavailable")
        }
        var result = Data()
        while result.count < size {
            try Task.checkCancellation()
            let count = min(chunkSize, size - result.count)
            let chunk = try await fetchPart(section: .complete, of: identifier, offset: result.count, count: count)
            guard chunk.count == count else { throw IMAPError.fetchFailed("Incomplete raw message") }
            result.append(chunk)
        }
        return result
    }

    public func fetchRawMessagesPipelined(uids: [UID]) async throws -> [UID: Data] {
        guard !uids.isEmpty else { return [:] }
        // Bound each burst to avoid unbounded command and response buffering.
        var result: [UID: Data] = [:]
        for offset in stride(from: 0, to: uids.count, by: 8) {
            try Task.checkCancellation()
            let batch = uids[offset..<min(offset + 8, uids.count)]
            let fetched = try await fetchPartsPipelined(parts: batch.map { (uid: $0, section: .complete) })
            for (uid, parts) in fetched {
                if let data = parts.first(where: { $0.section == .complete })?.data { result[uid] = data }
            }
        }
        return result
    }

    public func deleteMailbox(_ path: String) async throws {
        try await executeCommand(DeleteMailboxCommand(mailboxName: resolveMailboxPath(path)))
    }

    public func renameMailbox(from oldPath: String, to newPath: String) async throws {
        try await executeCommand(RenameMailboxCommand(from: resolveMailboxPath(oldPath), to: resolveMailboxPath(newPath)))
    }

    @discardableResult
    public func append(rawData: Data, to mailbox: String, flags: [Flag], internalDate: Date?) async throws -> AppendResult {
        if let limit = capabilities.globalAppendLimit, rawData.count > limit {
            throw IMAPError.appendLimitExceeded(rawData.count, limit)
        }
        return try await executeCommand(AppendCommand(
            mailboxName: resolveMailboxPath(mailbox), message: rawData, flags: flags,
            internalDate: internalDate.flatMap(makeInternalDate(from:))
        ))
    }
}
