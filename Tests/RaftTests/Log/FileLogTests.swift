// SPDX-License-Identifier: MIT
// Copyright © 2021 makadaw

import XCTest
import Foundation
@testable import Raft


final class FileLogTests: XCTestCase {
    var location: Path!

    override func setUpWithError() throws {
        var tempDirectoryPath = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
        tempDirectoryPath.appendPathComponent("FileLog-Tests")
        if FileManager.default.fileExists(atPath: tempDirectoryPath.absoluteString) {
            try FileManager.default.removeItem(at: tempDirectoryPath)
        }
        try FileManager.default.createDirectory(at: tempDirectoryPath,
                                            withIntermediateDirectories: true)
        location = try Path(tempDirectoryPath.path)
    }

    override func tearDownWithError() throws {
        if let location = self.location {
            try FileManager.default.removeItem(atPath: location.absolutePath)
        }

    }

    func testMetadataSave() throws {
        guard let metadataPath = try? location.appending("metadata") else {
            fatalError("Metadata filename or root path not really paths")
        }
        var meta = FileLog<String>.loadMetadata(from: metadataPath)
        XCTAssertNil(meta.termId)
        meta.termId = 42
        try FileLog<String>.saveMetadata(meta, to: metadataPath)
        meta = FileLog<String>.loadMetadata(from: metadataPath)
        XCTAssertEqual(meta.termId, 42)
    }
}
