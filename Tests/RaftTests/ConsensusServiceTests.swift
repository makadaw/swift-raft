// SPDX-License-Identifier: MIT
// Copyright © 2021 makadaw

import XCTest
import NIO
import NIOHPACK
import Logging
import GRPC
@testable import Raft

final class ConsensusServiceTests: XCTestCase {
    let group = EmbeddedEventLoop()
    let log = Logger(label: "test")

    func testDefaults() {

        let config = Configuration(id: 1)
        let service = ConsensusService<MemoryLog<String>>(group: group,
                                               config: config,
                                               peers: [],
                                               log: MemoryLog(),
                                               logger: log)
        XCTAssertEqual(service.term.id, 0)
        XCTAssertEqual(service.state, .follower)
    }

    func testStateMove() {
        let service = ConsensusService<MemoryLog<String>>(group: group,
                                       config: Configuration(id: 1),
                                       peers: [],
                                       log: MemoryLog(),
                                       logger: log)
        let exp = expectation(description: "Vote response")
        service.requestVote(request: Raft_RequestVote.Request.with({
            $0.candidateID = 2
            $0.term = 1
        }), context: MockContext(eventLoop: group.next()))
        .whenSuccess { response in
            XCTAssertTrue(response.voteGranted)
            exp.fulfill()
        }
        wait(for: [exp], timeout: 1)
        try! group.syncShutdownGracefully()
    }

    static var allTests = [
        ("testDefaults", testDefaults),
    ]
}

class MockContext: StatusOnlyCallContext {
    var responseStatus: GRPCStatus = GRPCStatus(code: .ok, message: "")

    var trailers: HPACKHeaders = HPACKHeaders()

    var eventLoop: EventLoop

    var headers: HPACKHeaders = HPACKHeaders()

    var userInfo: UserInfo = UserInfo()

    var logger: Logger = Logger(label: "test")

    var compressionEnabled: Bool = false

    init(eventLoop: EventLoop) {
        self.eventLoop = eventLoop
    }
}
