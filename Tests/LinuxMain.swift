import XCTest

import swift_raftTests

var tests = [XCTestCaseEntry]()
tests += ConsensusService.allTests()
tests += TermTests.allTests()
XCTMain(tests)
