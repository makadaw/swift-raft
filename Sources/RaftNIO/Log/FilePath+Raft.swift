// SPDX-License-Identifier: MIT
// Copyright © 2021 makadaw


import SystemPackage
import Foundation

extension FilePath {

    /// Temporary dictionary should be not depend on the Foundation
    static public var temporaryDirectory: FilePath {
        FilePath(NSTemporaryDirectory())
    }

    /// Trivial implementation of mktemp
    static func mktemp(prefix: String? = nil,
                       suffix: String? = nil,
                       createDirectory: Bool = false,
                       destination: FilePath? = nil) throws -> FilePath {
        // Get default tmp folder of the system
        let tempDirectory = destination ?? Self.temporaryDirectory

        // TODO Use XXXXXXX pattern? Or something better that UUID
        let generatePath = FilePath((prefix ?? "") + UUID().uuidString + (suffix ?? ""))
        guard generatePath.isLexicallyNormal && generatePath.components.count == 1,
              let generatePath = generatePath.lastComponent else {
            // TODO Not the best error
            throw Errno.badFileTypeOrFormat
        }
        let finalPath = tempDirectory.appending(generatePath)

        if createDirectory {
            // TODO Do not use foundation
            // Create a folder
            if !finalPath.isPathExist() {
                try FileManager.default
                    .createDirectory(atPath: finalPath.string,
                                     withIntermediateDirectories: false,
                                     attributes: [.posixPermissions: FilePermissions.ownerReadWriteExecute.rawValue])
            }
        } else {
            // Create a file and close a descriptor
            try FileDescriptor.open(finalPath,
                                    .readOnly,
                                    options: [.create],
                                    permissions: [.ownerReadWriteExecute],
                                    retryOnInterrupt: true)
                .close()
        }
        return finalPath
    }

    /// Temporary methods to hide direct usage of FileManager
    public func isPathExist() -> Bool {
        FileManager.default.fileExists(atPath: string)
    }

    @discardableResult
    public func createDirectory() throws -> Bool {
        try FileManager.default.createDirectory(atPath: string, withIntermediateDirectories: true)
        return true
    }

    @discardableResult
    func removePath() throws -> Bool {
        try FileManager.default.removeItem(atPath: string)
        return true
    }

}
