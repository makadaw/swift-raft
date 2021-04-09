// SPDX-License-Identifier: MIT
// Copyright © 2021 makadaw


import XCTest
@testable import SwiftRaft

extension Raft {
    func getTerm() async -> Term {
        term
    }

    func becomeLeaderInTerm(_ id: Term.ID = 10) async {
        state = .leader
        term = Term(myself: config.myself.id, id: id)
    }
}

func buildTestInstance(log: MemoryLog<String>? = nil) -> Raft<MemoryLog<String>> {
    Raft(config: Configuration(id: 1), peers: [], log: log ?? MemoryLog<String>())
}

final class RaftTests: XCTestCase {

    func testInitWithLogTerm() {
        var log = MemoryLog<String>()
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
