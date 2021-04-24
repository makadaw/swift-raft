// SPDX-License-Identifier: MIT
// Copyright © 2021 makadaw


import XCTest
@testable import SwiftRaft

@available(macOS 9999, *)
final class AppendMessageTests: XCTestCase {

    func heartBeatRequest(termID: Term.ID, leaderID: NodeID) -> AppendEntries.Request<String> {
        .init(termID: termID, leaderID: leaderID, prevLogIndex: 0, prevLogTerm: 0, leaderCommit: 0, entries: [])
    }

    var instance: Raft<MemoryLog<String>>!
    override func setUpWithError() throws {
        instance = buildTestInstance()
    }

    func testFollowingALeader() {
        // send an append message with higher term
        runAsyncTestAndBlock {
            let response = await self.instance.onAppendEntries(self.heartBeatRequest(termID: 2, leaderID: 2))
            XCTAssertEqual(response.commands.count, 1)
            if case .resetElectionTimer = response.commands.first {
            } else {
                XCTFail("Node should reset an election timer if step down")
            }
            XCTAssertEqual(response.response.termID, 2, "On getting message with higher term we set this term as current")
            XCTAssertEqual(response.response.success, false)
        }
    }

    func testValidHeartbeat() {
        runAsyncTestAndBlock {
            // Emulate elections
            _ = await self.instance.onVoteRequest(.init(type: .vote, termID: 2, candidateID: 2, lastLogIndex: 0, lastLogTerm: 0))
            let response = await self.instance.onAppendEntries(self.heartBeatRequest(termID: 2, leaderID: 2))
            if case .resetElectionTimer = response.commands.first {
            } else {
                XCTFail("Node should reset an election timer if step down")
            }
            XCTAssertEqual(response.response.termID, 2)
            XCTAssertEqual(response.response.success, true)
        }
    }

    func testBecomeLeader() {
        runAsyncTestAndBlock {
            // Check not a leader node
            var commands = await self.instance.onBecomeLeader()
            XCTAssertEqual(commands, [], "If node is not leader we don't need to do anything")

            // Now become a leader and check what to do
            await self.instance.becomeLeaderInTerm()
            commands = await self.instance.onBecomeLeader()
            XCTAssertEqual(commands.first, .sendHeartBeat, "We should send a heard beat just after become a leader")
            XCTAssertTrue(commands[1].isScheduleHeartBeatTask, "We should schedule repeated send of heatbeats")
        }
    }

    func testHeartbeatOfNotLeader() {
        runAsyncTestAndBlock {
            var commands = await self.instance.sendHeartBeat()
            XCTAssertEqual(commands[0], .stepDown)
            XCTAssertTrue(commands[1].isResetElectionTimer)

            await self.instance.becomeLeaderInTerm()
            commands = await self.instance.sendHeartBeat()
            XCTAssertTrue(commands.isEmpty)
        }
    }
}

@available(macOS 9999, *)
extension Raft.EntriesCommand {
    var isScheduleHeartBeatTask: Bool {
        switch self {
            case .scheduleHeartBeatTask:
                return true
            default:
                return false
        }
    }

    var isResetElectionTimer: Bool {
        switch self {
            case .resetElectionTimer:
                return true
            default:
                return false
        }
    }
}
