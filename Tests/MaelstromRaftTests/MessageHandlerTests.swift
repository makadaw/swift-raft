// SPDX-License-Identifier: MIT
// Copyright © 2021 makadaw


import XCTest
import Logging
import NIO
@testable import MaelstromRaft

class MessageHandlerTests: XCTestCase {
    @available(macOS 9999, *)
    func testInitMessageResponse() throws {
        let echoHandler = MessageHandler(messageProvider: EchoProvider(), logger: Logger(label: "tests"))

        let channel = EmbeddedChannel()
        defer {
            XCTAssertNoThrow(try channel.finish())
        }

        try channel.pipeline.addHandlers([
            echoHandler
        ]).wait()

        let request = RPCPacket(src: "t0", dest: "n1", id: 0, body: Maelstrom.Init(nodeID: "n1", nodeIDs: ["n1", "n2"]), msgID: 5)
        let context = try channel.pipeline.context(handlerType: MessageHandler.self).wait()
        echoHandler.channelRead(context: context, data: NIOAny(request))

        // Sleep in this thread and schedule a next task on the event loop
        // Need to sync actors Task and response in NIO event loop
        sleep(1)
        context.eventLoop.execute {
            if let response = try? channel.readOutbound(as: RPCPacket.self) {
                XCTAssertEqual(response.src, request.dest)
                XCTAssertEqual(response.dest, request.src)
                switch response.body {
                    case is Maelstrom.InitOk:
                        XCTAssertEqual(response.dest, "t0")
                        XCTAssertEqual(response.src, "n1")
                        XCTAssertEqual(response.msgID, 1)
                        XCTAssertEqual(response.internalBody.inReplyTo, 5)
                    default:
                        XCTFail("On init message should answer `init_ok`")
                }
            } else {
                XCTFail("couldn't read from channel")
            }
        }
    }
}
