// SPDX-License-Identifier: MIT
// Copyright © 2021 makadaw


import XCTest
import Logging
import NIO
@testable import MaelstromRaft

class MessageHandlerTests: XCTestCase {

    func testInitMessageResponse() throws {
        let echoHandler = MessageHandler(messageProvider: EchoProvider(), logger: Logger(label: "tests"))

        let channel = EmbeddedChannel()
        defer {
            XCTAssertNoThrow(try channel.finish())
        }

        try channel.pipeline.addHandlers([
            echoHandler,
        ]).wait()

        let request = RPCPacket(src: "t0", dest: "n1", id: 0, body: .`init`(nodeID: "n1", nodeIDs: ["n1", "n2"]), msgID: 5)
        let context = try channel.pipeline.context(handlerType: MessageHandler.self).wait()
        echoHandler.channelRead(context: context, data: NIOAny(request))

        if let response = try channel.readOutbound(as: RPCPacket.self) {
            XCTAssertEqual(response.src, request.dest)
            XCTAssertEqual(response.dest, request.src)
            switch response.body {
                case .initOk:
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
        XCTAssertNoThrow(XCTAssertNil(try channel.readOutbound()))
    }
}
