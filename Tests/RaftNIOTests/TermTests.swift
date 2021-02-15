// SPDX-License-Identifier: MIT
// Copyright © 2021 makadaw

import XCTest
import Raft
@testable import RaftNIO

final class TermTests: XCTestCase {
    let mySelf: NodeId = 1

    func testNext() {
        var term: Term = Term(myself: mySelf)
        term = term.nextTerm()
        XCTAssertEqual(term, Term(myself: 1, id: 1))
        term = term.nextTerm()
        XCTAssertEqual(term, Term(myself: 1, id: 2))
    }

    func testVoteAccept() {
        var term: Term = Term(myself: mySelf, id: 10)
        term = term.nextTerm()

        XCTAssertFalse(term.canAcceptNewTerm(10, from: 2), "Should reject votes from smaller terms")
        XCTAssertFalse(term.canAcceptNewTerm(11, from: 2), "Should reject votes from already voted terms")
        XCTAssertFalse(term.canAcceptNewTerm(2, from: mySelf), "Reject votes myself on lower terms")

        XCTAssertTrue(term.canAcceptNewTerm(12, from: 2), "Accept therms that higher")
    }

    func testBumpCurrentTerm() {
        var term: Term = Term(myself: mySelf, id: 10)
        try! term.tryToUpdateTerm(newTerm: 11, from: mySelf)
        XCTAssertEqual(term.votedFor, mySelf, "Should update voted for")
        XCTAssertEqual(term.id, 11)

        XCTAssertThrowsError(try term.tryToUpdateTerm(newTerm: 9, from: mySelf),
                             "Should throw an error if try to set lowwer term")
    }

    static var allTests = [
        ("testNext", testNext),
        ("testVoteAccept", testVoteAccept),
        ("testBumpCurrentTerm", testBumpCurrentTerm),
    ]
}
