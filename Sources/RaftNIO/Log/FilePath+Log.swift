// SPDX-License-Identifier: MIT
// Copyright © 2021 makadaw


import SystemPackage
import Foundation

extension FilePath {

    var toURL: URL {
        URL(fileURLWithPath: string)
    }

    public static func defaultTemporaryDirectory(_ defaultFolder: String = "LocalCluster") -> FilePath {
        let tempDirectoryPath = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
        return FilePath(tempDirectoryPath.appendingPathComponent(defaultFolder).path)
    }
}
