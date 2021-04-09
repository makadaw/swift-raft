// SPDX-License-Identifier: MIT
// Copyright © 2021 makadaw


import XCTest
import Logging
import SwiftRaft
@testable import MaelstromRaft

class RaftMessagesCoding: XCTestCase {
    let logger: Logger = .init(label: "tests")
    var coder: RPCPacketCoder {
        RPCPacketCoder(logger: logger)
    }

    func testVoteResponse() throws {
        let origin = RequestVote.Response(type: .preVote, termID: 42, voteGranted: true)
        let coder = self.coder
        try coder.registerMessage(RequestVote.Response.self)
        let imposter = try doubleCoding(coder: coder, of: origin)
        XCTAssertEqual(origin.type, imposter.type)
        XCTAssertEqual(origin.termID, imposter.termID)
        XCTAssertEqual(origin.voteGranted, imposter.voteGranted)
    }

    func testVoteRequest() throws {
        let origin = RequestVote.Request(type: .preVote, termID: 42, candidateID: 3, lastLogIndex: 4, lastLogTerm: 5)
        let coder = self.coder
        try coder.registerMessage(RequestVote.Request.self)
        let imposter = try doubleCoding(coder: coder, of: origin)
        XCTAssertEqual(origin.type, imposter.type)
        XCTAssertEqual(origin.termID, imposter.termID)
        XCTAssertEqual(origin.candidateID, imposter.candidateID)
        XCTAssertEqual(origin.lastLogIndex, imposter.lastLogIndex)
        XCTAssertEqual(origin.lastLogTerm, imposter.lastLogTerm)
    }

    func testAppendEntriesRequest() throws {
        let origin = AppendEntries.Request<String>(termID: 42,
                                                   leaderID: 3,
                                                   prevLogIndex: 4,
                                                   prevLogTerm: 5,
                                                   leaderCommit: 6,
                                                   entries: [])
        let coder = self.coder
        try coder.registerMessage(AppendEntries.Request<String>.self)
        let imposter = try doubleCoding(coder: coder, of: origin)
        XCTAssertEqual(origin.termID, imposter.termID)
        XCTAssertEqual(origin.leaderID, imposter.leaderID)
        XCTAssertEqual(origin.prevLogIndex, imposter.prevLogIndex)
        XCTAssertEqual(origin.prevLogTerm, imposter.prevLogTerm)
        XCTAssertEqual(origin.leaderCommit, imposter.leaderCommit)
    }

    func testAppendEntriesResponse() throws {
        let origin = AppendEntries.Response(termID: 42, success: true)
        let coder = self.coder
        try coder.registerMessage(AppendEntries.Response.self)
        let imposter = try doubleCoding(coder: coder, of: origin)
        XCTAssertEqual(origin.termID, imposter.termID)
        XCTAssertEqual(origin.success, imposter.success)
    }
}
