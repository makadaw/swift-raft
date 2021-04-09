// SPDX-License-Identifier: MIT
// Copyright © 2021 makadaw


import XCTest
@testable import SwiftRaft

// Use LogCabin test case to validate memory log
final class MemoryLogTests: XCTestCase {
    var log: MemoryLog<String> {
        MemoryLog()
    }

    var sample: LogElement<String> {
        .data(termId: 42, index: 0, content: "foo")
    }

    func testBasic() {
        var log = self.log
        let range = log.append([sample])
        XCTAssertEqual(1, range.lowerBound)
        XCTAssertEqual(1, range.upperBound)
        let entry = try! log.entry(at: 1)
        XCTAssertEqual(42, entry.term)
        XCTAssertEqual("foo", entry.content)
    }

    func testAppend() {
        var log = self.log
        _ = log.append([sample])
        log.truncatePrefix(10)
        let range = log.append([sample, sample])
        XCTAssertEqual(10, range.lowerBound)
        XCTAssertEqual(11, range.upperBound)
        XCTAssertEqual(10, log.logStartIndex)
        XCTAssertEqual(11, log.logLastIndex)
    }

    func testEntryAccess() {
        var log = self.log
        _ = log.append([sample])
        let entry = try! log.entry(at: 1)//log[1]
        XCTAssertEqual(42, entry.term)
        XCTAssertThrowsError(try log.entry(at: 0))
        XCTAssertThrowsError(try log.entry(at: 2))

        let sampleEntry = LogElement.data(termId: 42, index: 0, content: "bar")
        _ = log.append([sampleEntry])
        log.truncatePrefix(2)
        XCTAssertThrowsError(try log.entry(at: 1))
        _ = log.append([sampleEntry])
        let entry2 = try! log.entry(at: 2) //log[2]
        XCTAssertEqual("bar", entry2.content)
    }

    func testLogStartIndex() {
        var log = self.log
        XCTAssertEqual(1, log.logStartIndex)
        log.truncatePrefix(200)
        log.truncatePrefix(100)
        XCTAssertEqual(200, log.logStartIndex)
    }

    func testLogLostIndex() {
        var log = self.log
        XCTAssertEqual(0, log.logLastIndex)
        _ = log.append([sample, sample])
        XCTAssertEqual(2, log.logLastIndex)

        log.truncatePrefix(2)
        XCTAssertEqual(2, log.logLastIndex)
    }

    func testSizeBytes() {
        var log = self.log
        XCTAssertEqual(0, log.sizeBytes)
        _ = log.append([sample])
        let size = log.sizeBytes
        XCTAssertLessThan(0, size)
        _ = log.append([sample])
        XCTAssertEqual(2 * size, log.sizeBytes)
    }

    func testTruncatePrefix() {
        var log = self.log
        XCTAssertEqual(1, log.startIndex)
        log.truncatePrefix(0)
        XCTAssertEqual(1, log.startIndex)
        log.truncatePrefix(1)
        XCTAssertEqual(1, log.startIndex)

        // case 1: entries is empty
        log.truncatePrefix(500)
        XCTAssertEqual(500, log.startIndex)
        XCTAssertEqual(0, log.count)

        // case 2: entries has fewer elements than truncated
        _ = log.append([sample])
        log.truncatePrefix(502)
        XCTAssertEqual(502, log.startIndex)
        XCTAssertEqual(0, log.count)

        // case 3: entries has exactly the elements truncated
        _ = log.append([sample, sample])
        log.truncatePrefix(504)
        XCTAssertEqual(504, log.startIndex)
        XCTAssertEqual(0, log.count)

        // case 4: entries has more elements than truncated
        let sampleEntry = LogElement.data(termId: 42, index: 0, content: "bar")
        _ = log.append([sample, sample, sampleEntry])
        log.truncatePrefix(506)
        XCTAssertEqual(506, log.startIndex)
        XCTAssertEqual(1, log.count)
        XCTAssertEqual(sampleEntry.content, log.storage[0].content)

        // make sure truncating to an earlier id has no effect
        log.truncatePrefix(400)
        XCTAssertEqual(506, log.startIndex)
    }

    func testTruncateSuffix() {
        var log = self.log
        log.truncateSuffix(0)
        log.truncateSuffix(10)
        XCTAssertEqual(0, log.logLastIndex)
        _ = log.append([sample, sample])
        log.truncateSuffix(10)
        XCTAssertEqual(2, log.logLastIndex)
        log.truncateSuffix(2)
        XCTAssertEqual(2, log.logLastIndex)
        log.truncateSuffix(1)
        XCTAssertEqual(1, log.logLastIndex)
        log.truncateSuffix(0)
        XCTAssertEqual(0, log.logLastIndex)

        log.truncatePrefix(10)
        _ = log.append([sample])
        XCTAssertEqual(10, log.logLastIndex)
        log.truncateSuffix(10)
        XCTAssertEqual(10, log.logLastIndex)
        log.truncateSuffix(8)
        XCTAssertEqual(9, log.logLastIndex)
        _ = log.append([sample])
        XCTAssertEqual(10, log.logLastIndex)
    }

    func testIterator() {
        var log = self.log
        _ = log.append([sample, sample])

        let map = log.map { _ in 1 }
        XCTAssertEqual(map.count, 2)
        XCTAssertEqual(log.count, 2)
    }
}

// Use string as dummy application data
extension String: LogData {

    public init?(data: Data) {
        self.init(data: data, encoding: .utf8)
    }

    public var size: Int {
        self.data(using: .utf8)?.count ?? 0
    }
}
