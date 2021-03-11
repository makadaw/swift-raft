// SPDX-License-Identifier: MIT
// Copyright © 2021 makadaw


import XCTest
import Logging
import NIO
@testable import MaelstromRaft

class RaftProviderTests: XCTestCase {

    func testInit() throws {
        let logger = Logger(label: "tests")
        let raft = RaftProvider(logger: logger)

        let channel = EmbeddedChannel()
        let onInit = try raft.onMessage(.`init`(nodeID: "1", nodeIDs: ["1", "2"]),
                                        context: CallHandlerContext(logger: logger, eventLoop: channel.eventLoop))
            .wait()
        XCTAssertEqual(onInit, .initOk)
    }

    func testNonExistingRead() throws {
        let logger = Logger(label: "tests")
        let raft = RaftProvider(logger: logger)
        let channel = EmbeddedChannel()
        let context = CallHandlerContext(logger: logger, eventLoop: channel.eventLoop)

        let onInit = try raft.onMessage(.`init`(nodeID: "1", nodeIDs: ["1", "2"]),
                                        context: context)
            .wait()
        XCTAssertEqual(onInit, .initOk)

        XCTAssertThrowsError(try raft.onMessage(.read(key: 123), context: context).wait(), "Key does not exist") { error in
            XCTAssertEqual(error as? RPCPacket.Error, .keyDoesNotExist)
        }
    }
}
