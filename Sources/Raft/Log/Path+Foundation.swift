// SPDX-License-Identifier: MIT
// Copyright © 2021 makadaw

import Foundation

extension Path {
    var toURL: URL {
        URL(fileURLWithPath: absolutePath)
    }

    public static func defaultTemporaryDirectory(_ defaultFolder: String = "LocalCluster") -> Path {
        let tempDirectoryPath = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
        return try! Path(tempDirectoryPath.appendingPathComponent(defaultFolder).path)
    }
}
