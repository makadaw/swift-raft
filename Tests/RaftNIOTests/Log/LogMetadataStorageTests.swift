// SPDX-License-Identifier: MIT
// Copyright © 2021 makadaw


import XCTest
import SystemPackage
import SwiftRaft
@testable import RaftNIO


final class LogMetadataStorageTests: XCTestCase {
    var metadataTmp: FilePath!

    override func setUpWithError() throws {
        metadataTmp = try FilePath.mktemp(prefix: "metadata-test")
    }

    override func tearDownWithError() throws {
        try metadataTmp?.removePath()
    }

    func testWrite() throws {
        var metadata = LogMetadata()
        metadata.termID = 2
        metadata.voteFor = 3

        let storage = LogMetadataFileStorage(filePath: metadataTmp)
        try storage.save(metadata: metadata)

        let readMetadata = try storage.load()
        XCTAssertEqual(metadata, readMetadata)
    }
}
