// SPDX-License-Identifier: MIT
// Copyright © 2021 makadaw


import XCTest
@testable import SwiftRaft

extension Raft {
    func getTerm() async -> Term {
        term
    }

    func becomeLeader() async {
        state = .leader
        term = Term(myself: config.myself.id, id: 10)
    }
}

func buildTestInstance(log: ArrayLog<String>? = nil) -> Raft<ArrayLog<String>> {
    Raft(config: Configuration(id: 1), peers: [], log: log ?? ArrayLog<String>())
}

final class RaftTests: XCTestCase {

    func testInitWithLogTerm() {
        var log = ArrayLog<String>()
        log.metadata.termID = 3
        log.metadata.voteFor = 1
        let instance = buildTestInstance(log: log)
        runAsyncTestAndBlock {
            let term = await instance.getTerm()
            XCTAssertEqual(term.id, 3)
            XCTAssertEqual(term.votedFor, 1)
        }
    }
}
