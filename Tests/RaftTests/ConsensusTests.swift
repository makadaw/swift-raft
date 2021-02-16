// SPDX-License-Identifier: MIT
// Copyright © 2021 makadaw

import XCTest
import _Concurrency
@testable import Raft

final class ConsensusTests: XCTestCase {

    var testConfiguration: Configuration {
        Configuration(id: 1)
    }

    func testElectionTimeoutOnStart() {
        let instance = Consensus(config: testConfiguration, peers: [])
        runAsyncAndBlock {
            let command = await instance.onElectionTimeout()
            if case .startPreVote = command {
                XCTAssertTrue(true)
            } else{
                XCTFail("On first election timeout we should start prevote")
            }
        }
    }

    func testResponseKeepTheSameType() {
        let instance = Consensus(config: testConfiguration, peers: [])
        runAsyncAndBlock {
            var response = await instance.onVoteRequest(.init(type: .preVote, term: 1, candidate: 2, lastLogIndex: 0, lastLogTerm: 0))
            XCTAssertEqual(response.type, .preVote)
            response = await instance.onVoteRequest(.init(type: .vote, term: 1, candidate: 2, lastLogIndex: 0, lastLogTerm: 0))
            XCTAssertEqual(response.type, .vote)
        }
    }

    func testPreVoteForHigherTerm() {
        let instance = Consensus(config: testConfiguration, peers: [])
        runAsyncAndBlock {
            let response = await instance.onVoteRequest(.init(type: .preVote, term: 1, candidate: 2, lastLogIndex: 0, lastLogTerm: 0))
            XCTAssertEqual(response.term.id, 0, "PreVote phase do not change current node term")
            XCTAssertTrue(response.voteGranted)
        }
    }

    func testPreVoteForTheSameTerm() {
        let instance = Consensus(config: testConfiguration, peers: [])
        runAsyncAndBlock {
            let response = await instance.onVoteRequest(.init(type: .preVote, term: 0, candidate: 2, lastLogIndex: 0, lastLogTerm: 0))
            XCTAssertEqual(response.term.id, 0)
            XCTAssertFalse(response.voteGranted)
        }
    }

    func testVoteForHigherTerm() {
        let instance = Consensus(config: testConfiguration, peers: [])
        runAsyncAndBlock {
            let response = await instance.onVoteRequest(.init(type: .vote, term: 1, candidate: 2, lastLogIndex: 0, lastLogTerm: 0))
            XCTAssertEqual(response.term.id, 1, "After granted vote node set new term for itself")
            XCTAssertTrue(response.voteGranted)
        }
    }

    func testVoteForTheSameTerm() {
        let instance = Consensus(config: testConfiguration, peers: [])
        runAsyncAndBlock {
            var response = await instance.onVoteRequest(.init(type: .vote, term: 1, candidate: 2, lastLogIndex: 0, lastLogTerm: 0))
            XCTAssertTrue(response.voteGranted)
            response = await instance.onVoteRequest(.init(type: .vote, term: 1, candidate: 3, lastLogIndex: 0, lastLogTerm: 0))
            XCTAssertEqual(response.term.id, 1)
            XCTAssertFalse(response.voteGranted, "Node can vote only for one candidate per term")
        }
    }

    func testVoteForTheHigherTerms() {
        let instance = Consensus(config: testConfiguration, peers: [])
        runAsyncAndBlock {
            var response = await instance.onVoteRequest(.init(type: .vote, term: 1, candidate: 2, lastLogIndex: 0, lastLogTerm: 0))
            XCTAssertEqual(response.term.id, 1)
            XCTAssertTrue(response.voteGranted)
            response = await instance.onVoteRequest(.init(type: .vote, term: 2, candidate: 3, lastLogIndex: 0, lastLogTerm: 0))
            XCTAssertEqual(response.term.id, 2)
            XCTAssertTrue(response.voteGranted)
        }
    }

    func testVoteForTheLowerTerms() {
        let instance = Consensus(config: testConfiguration, peers: [])
        runAsyncAndBlock {
            var response = await instance.onVoteRequest(.init(type: .vote, term: 2, candidate: 2, lastLogIndex: 0, lastLogTerm: 0))
            XCTAssertEqual(response.term.id, 2)
            XCTAssertTrue(response.voteGranted)
            response = await instance.onVoteRequest(.init(type: .vote, term: 1, candidate: 3, lastLogIndex: 0, lastLogTerm: 0))
            XCTAssertEqual(response.term.id, 2)
            XCTAssertFalse(response.voteGranted)
        }
    }
}
