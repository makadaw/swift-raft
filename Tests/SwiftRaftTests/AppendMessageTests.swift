// SPDX-License-Identifier: MIT
// Copyright © 2021 makadaw


import XCTest
@testable import SwiftRaft

final class AppendMessageTests: XCTestCase {

    func heartBeatRequest(termID: Term.ID, leaderId: NodeID) -> Raft.AppendEntries.Request<String> {
        .init(termID: termID, leaderId: leaderId, prevLogIndex: 0, prevLogTerm: 0, leaderCommit: 0, entries: [])
    }

    func testFollowingALeader() {
        let raft = buildTestInstance()
        // send an append message with higher term
        runAsyncTestAndBlock {
            let response = await raft.onAppendEntries(self.heartBeatRequest(termID: 2, leaderId: 2))
            XCTAssertEqual(response.commands.count, 1)
            XCTAssertEqual(response.commands.first, .resetElectionTimer)
            XCTAssertEqual(response.termID, 2, "On getting message with higher term we set this term as current")
            XCTAssertEqual(response.success, false)
        }
    }

    func testValidHeartbeat() {
        let raft = buildTestInstance()
        runAsyncTestAndBlock {
            // Emulate elections
            _ = await raft.onVoteRequest(.init(type: .vote, term: 2, candidate: 2, lastLogIndex: 0, lastLogTerm: 0))
            let response = await raft.onAppendEntries(self.heartBeatRequest(termID: 2, leaderId: 2))
            XCTAssertEqual(response.commands.first, .resetElectionTimer)
            XCTAssertEqual(response.termID, 2)
            XCTAssertEqual(response.success, true)
        }
    }
}
