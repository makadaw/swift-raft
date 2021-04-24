// SPDX-License-Identifier: MIT
// Copyright © 2021 makadaw


import XCTest
@testable import SwiftRaft

@available(macOS 9999, *)
extension Raft {
    func getTerm() async -> Term {
        term
    }

    func becomeLeaderInTerm(_ id: Term.ID = 10) async {
        state = .leader
        term = Term(myself: config.myself.id, id: id)
    }
}

@available(macOS 9999, *)
func buildTestInstance(log: MemoryLog<String>? = nil) -> Raft<MemoryLog<String>> {
    Raft(config: Configuration(id: 1), peers: [], log: log ?? MemoryLog<String>())
}

@available(macOS 9999, *)
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
