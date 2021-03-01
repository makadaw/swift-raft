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

final class ConsensusTests: XCTestCase {

    func buildTestInstance(log: ArrayLog<String>? = nil) -> Raft {
        Raft(config: Configuration(id: 1), peers: [], log: log ?? ArrayLog<String>())
    }

    func testInitWithLogTerm() {
        var log = ArrayLog<String>()
        log.metadata.termId = 3
        log.metadata.voteFor = 1
        let instance = buildTestInstance(log: log)
        runAsyncTestAndBlock {
            let term = await instance.getTerm()
            XCTAssertEqual(term.id, 3)
            XCTAssertEqual(term.votedFor, 1)
        }
    }
}

extension ConsensusTests {

    func testElection() {
        let instance = buildTestInstance()
        runAsyncTestAndBlock {
            await instance.becomeLeader()
            let response = await instance.onVoteRequest(.init(type: .vote, term: 3, candidate: 2, lastLogIndex: 0, lastLogTerm: 0))
            XCTAssertEqual(response.term.id, 10)
            XCTAssertFalse(response.voteGranted)
        }
    }
    
    func testElectionTimeoutOnStart() {
        let instance = buildTestInstance()
        runAsyncTestAndBlock {
            let command = await instance.onElectionTimeout()
            if case .startPreVote = command {
                XCTAssertTrue(true)
            } else{
                XCTFail("On first election timeout we should start prevote")
            }
        }
    }

    func testVoteRequestCheckLogsIndex() {
        var log = ArrayLog<String>()
        _ = log.append([.data(termId: 1, index: 1, content: "Entity")])
        let instance = buildTestInstance(log: log)
        runAsyncTestAndBlock {
            // Request vote for the next term, but with lower log index
            let response = await instance.onVoteRequest(.init(type: .vote, term: 1, candidate: 2, lastLogIndex: 0, lastLogTerm: 0))
            XCTAssertFalse(response.voteGranted)
        }
    }

    func testVoteResponseKeepTheSameType() {
        let instance = buildTestInstance()
        runAsyncTestAndBlock {
            var response = await instance.onVoteRequest(.init(type: .preVote, term: 1, candidate: 2, lastLogIndex: 0, lastLogTerm: 0))
            XCTAssertEqual(response.type, .preVote)
            response = await instance.onVoteRequest(.init(type: .vote, term: 1, candidate: 2, lastLogIndex: 0, lastLogTerm: 0))
            XCTAssertEqual(response.type, .vote)
        }
    }

    func testPreVoteForHigherTerm() {
        let instance = buildTestInstance()
        runAsyncTestAndBlock {
            let response = await instance.onVoteRequest(.init(type: .preVote, term: 1, candidate: 2, lastLogIndex: 0, lastLogTerm: 0))
            XCTAssertEqual(response.term.id, 0, "PreVote phase do not change current node term")
            XCTAssertTrue(response.voteGranted)
        }
    }

    func testPreVoteForTheSameTerm() {
        let instance = buildTestInstance()
        runAsyncTestAndBlock {
            let response = await instance.onVoteRequest(.init(type: .preVote, term: 0, candidate: 2, lastLogIndex: 0, lastLogTerm: 0))
            XCTAssertEqual(response.term.id, 0)
            XCTAssertFalse(response.voteGranted)
        }
    }

    func testVoteForHigherTerm() {
        let instance = buildTestInstance()
        runAsyncTestAndBlock {
            let response = await instance.onVoteRequest(.init(type: .vote, term: 1, candidate: 2, lastLogIndex: 0, lastLogTerm: 0))
            XCTAssertEqual(response.term.id, 1, "After granted vote node set new term for itself")
            XCTAssertTrue(response.voteGranted)
        }
    }

    func testVoteForTheSameTerm() {
        let instance = buildTestInstance()
        runAsyncTestAndBlock {
            var response = await instance.onVoteRequest(.init(type: .vote, term: 1, candidate: 2, lastLogIndex: 0, lastLogTerm: 0))
            XCTAssertTrue(response.voteGranted)
            response = await instance.onVoteRequest(.init(type: .vote, term: 1, candidate: 3, lastLogIndex: 0, lastLogTerm: 0))
            XCTAssertEqual(response.term.id, 1)
            XCTAssertFalse(response.voteGranted, "Node can vote only for one candidate per term")
        }
    }

    func testVoteForTheHigherTerms() {
        let instance = buildTestInstance()
        runAsyncTestAndBlock {
            var response = await instance.onVoteRequest(.init(type: .vote, term: 1, candidate: 2, lastLogIndex: 0, lastLogTerm: 0))
            XCTAssertEqual(response.term.id, 1)
            XCTAssertTrue(response.voteGranted)
            response = await instance.onVoteRequest(.init(type: .vote, term: 2, candidate: 3, lastLogIndex: 0, lastLogTerm: 0))
            XCTAssertEqual(response.term.id, 2)
            XCTAssertTrue(response.voteGranted)
        }
    }

    func testVoteForTheLowerTerms() {
        let instance = buildTestInstance()
        runAsyncTestAndBlock {
            var response = await instance.onVoteRequest(.init(type: .vote, term: 2, candidate: 2, lastLogIndex: 0, lastLogTerm: 0))
            XCTAssertEqual(response.term.id, 2)
            XCTAssertTrue(response.voteGranted)
            response = await instance.onVoteRequest(.init(type: .vote, term: 1, candidate: 3, lastLogIndex: 0, lastLogTerm: 0))
            XCTAssertEqual(response.term.id, 2)
            XCTAssertFalse(response.voteGranted)
        }
    }
}
