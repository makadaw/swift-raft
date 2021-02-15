// SPDX-License-Identifier: MIT
// Copyright © 2021 makadaw

import XCTest
@testable import RaftNIO

// Use LogCabin test case to validate memory log
final class PathTests: XCTestCase {

    func testPathNormalization() throws {
        let path = try Path("/users/main/../root/")
        XCTAssertEqual(path.absolutePath, "/users/root")
    }

    func testPathAppend() throws {
        var path = try Path("tmp/val")
        path = try path.appending("file")
        XCTAssertEqual(path.absolutePath, "tmp/val/file")
    }
}
