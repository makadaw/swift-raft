// SPDX-License-Identifier: MIT
// Copyright © 2021 makadaw


import SystemPackage
import Foundation

extension FilePath {

    /// Temporary solution to workaround compilation error of last revision of SystemPackage
    public func appending(_ path: FilePath) -> FilePath {
        FilePath("\(self)/\(path)")
    }

    public func appending(_ path: String) -> FilePath {
        appending(FilePath(path))
    }

    var path: String {
        "\(self)"
    }

    var toURL: URL {
        URL(fileURLWithPath: path)
    }

    public static func defaultTemporaryDirectory(_ defaultFolder: String = "LocalCluster") -> FilePath {
        let tempDirectoryPath = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
        return FilePath(tempDirectoryPath.appendingPathComponent(defaultFolder).path)
    }
}
