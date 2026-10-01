import Foundation
import NIO
import NIOEmbedded
@preconcurrency import NIOIMAP
import NIOIMAPCore
import Testing
@testable import SwiftMail

@Suite(.serialized)
struct EmailXCompatibilityTests {
    @Test func deltaFetchWireEncoding() async throws {
        let channel = try await NIOAsyncTestingChannel.withIMAPClientHandler()
        let command = FetchMessageInfoCommand(identifierSet: SwiftMail.UIDSet(SwiftMail.UID(1)...), options: .uidFlagsOnly, changedSince: 42)
        try await channel.writeAndFlush(IMAPClientHandler.OutboundIn.part(.tagged(command.toTaggedCommand(tag: "A001"))))
        var output = try #require(await channel.readOutbound(as: ByteBuffer.self))
        #expect(output.readString(length: output.readableBytes) == "A001 UID FETCH 1:* (UID MODSEQ FLAGS) (CHANGEDSINCE 42)\r\n")
    }

    @Test func rawPartialWireEncoding() async throws {
        let channel = try await NIOAsyncTestingChannel.withIMAPClientHandler()
        let command = FetchMessagePartCommand(identifier: SwiftMail.UID(7), section: .complete, range: 262144...524287)
        try await channel.writeAndFlush(IMAPClientHandler.OutboundIn.part(.tagged(command.toTaggedCommand(tag: "A002"))))
        var output = try #require(await channel.readOutbound(as: ByteBuffer.self))
        #expect(output.readString(length: output.readableBytes) == "A002 UID FETCH 7 (BODY.PEEK[]<262144.262144>)\r\n")
    }

    @Test func appendKeepsNonUTF8Bytes() {
        let data = Data([0xff, 0x00, 0x80, 0x0d, 0x0a])
        let command = AppendCommand(mailboxName: "Drafts", message: data, flags: [], internalDate: nil)
        #expect(command.message == data)
    }
}
