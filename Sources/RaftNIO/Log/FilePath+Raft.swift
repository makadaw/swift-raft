// SPDX-License-Identifier: MIT
// Copyright © 2021 makadaw


import SystemPackage
import Foundation

extension FilePath {

    /// Trivial implementation of mktemp
    static public func mktemp(prefix: String? = nil,
                              suffix: String? = nil,
                              createDirectory: Bool = false,
                              random: Bool = true,
                              destination: FilePath? = nil) throws -> FilePath {
        // Check that prefix and suffix do not contain path separator
        guard random || !(prefix?.isEmpty ?? true && suffix?.isEmpty ?? true) else {
            // TODO should be an error
            preconditionFailure("For non random tmp path prefix or suffix should be provided")
        }

        // Get default tmp folder of the system
        let tempDirectory = destination ?? FilePath(NSTemporaryDirectory())

        // TODO Use XXXXXXX pattern? Or something better that UUID
        let generatePath = FilePath((prefix ?? "") + (random ? UUID().uuidString : "") + (suffix ?? ""))
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
    func isPathExist() -> Bool {
        FileManager.default.fileExists(atPath: string)
    }

    @discardableResult
    func createDirectory() throws -> Bool {
        try FileManager.default.createDirectory(atPath: string, withIntermediateDirectories: true)
        return true
    }

    @discardableResult
    func removePath() throws -> Bool {
        try FileManager.default.removeItem(atPath: string)
        return true
    }

}
