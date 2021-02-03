import XCTest

#if !canImport(ObjectiveC)
public func allTests() -> [XCTestCaseEntry] {
    return [
        testCase(ConsensusService.allTests),
        testCase(TermTests.allTests),
    ]
}
#endif
