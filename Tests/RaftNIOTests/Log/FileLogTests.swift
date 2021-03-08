// SPDX-License-Identifier: MIT
// Copyright © 2021 makadaw


import XCTest
import SystemPackage
@testable import RaftNIO


final class FileLogTests: XCTestCase {
    var location: FilePath!

    override func setUpWithError() throws {
        let tempDirectory = try FilePath.mktemp(prefix: "File-Log", createDirectory: true)
        if tempDirectory.isPathExist() {
            try tempDirectory.removePath()
        }
        try tempDirectory.createDirectory()
        location = tempDirectory
    }

    override func tearDownWithError() throws {
        try location?.removePath()
    }

    func testMetadataRead() throws {
        var log = try FileLog<String>(root: location)
        log.metadata.termID = 2

        // Init second log
        log = try FileLog<String>(root: location)
        XCTAssertEqual(log.metadata.termID, 2)
    }
}
