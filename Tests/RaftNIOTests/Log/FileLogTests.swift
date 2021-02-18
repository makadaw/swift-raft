// SPDX-License-Identifier: MIT
// Copyright © 2021 makadaw

import XCTest
import Foundation
import SystemPackage
@testable import RaftNIO


final class FileLogTests: XCTestCase {
    var location: FilePath!

    override func setUpWithError() throws {
        let tempDirectory = FilePath.defaultTemporaryDirectory("FileLog-Tests")
        if FileManager.default.fileExists(atPath: tempDirectory.string) {
            try FileManager.default.removeItem(at: tempDirectory.toURL)
        }
        try FileManager.default.createDirectory(at: tempDirectory.toURL,
                                            withIntermediateDirectories: true)
        location = tempDirectory
    }

    override func tearDownWithError() throws {
        if let location = self.location {
            try FileManager.default.removeItem(atPath: location.string)
        }

    }

    func testMetadataSave() throws {
        let metadataPath = location.appending("metadata")
        var meta = FileLog<String>.loadMetadata(from: metadataPath)
        XCTAssertNil(meta.termId)
        meta.termId = 42
        try FileLog<String>.saveMetadata(meta, to: metadataPath)
        meta = FileLog<String>.loadMetadata(from: metadataPath)
        XCTAssertEqual(meta.termId, 42)
    }
}
