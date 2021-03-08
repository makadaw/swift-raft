// SPDX-License-Identifier: MIT
// Copyright © 2021 makadaw


import SystemPackage
import SwiftRaft
import NIO
import SwiftProtobuf

// File log, simple implementation for prototype
// TODO:
//   - Do not use Foundation IO
//   - Use async IO for non-blocking operation
struct FileLog<T: LogData>: Log {
    typealias Data = T
    typealias Iterator = MemoryLog<Data>.Iterator

    // MARK: Files
    private let root: FilePath
    private let metadataStorage: LogMetadataFileStorage
    private var memoryLog: MemoryLog<Data>
    var metadata: LogMetadata {
        didSet {
            do {
                try self.metadataStorage.save(metadata: metadata)
            } catch {
                // TODO log error
            }
        }
    }

    init(root: FilePath, metadataFileName: String = "metadata") throws {
        self.root = root
        if !root.isPathExist() {
            try root.createDirectory()
        }

        self.metadataStorage = LogMetadataFileStorage(filePath: root.appending(metadataFileName))

        // Load metadata file
        metadata = (try? self.metadataStorage.load()) ?? LogMetadata()

        // Check for entities in files
        memoryLog = MemoryLog()
    }

    // MARK: Log data
    var logStartIndex: UInt {
        memoryLog.logStartIndex
    }

    var logLastIndex: UInt {
        memoryLog.logLastIndex
    }

    var count: Int {
        memoryLog.count
    }

    func entry(at position: UInt) throws -> LogElement<Data> {
        try memoryLog.entry(at: position)
    }

    mutating func append(_ entries: [LogElement<Data>]) -> ClosedRange<UInt> {
        memoryLog.append(entries)
    }

    mutating func truncatePrefix(_ firstIndex: UInt) {
        memoryLog.truncatePrefix(firstIndex)
    }

    mutating func truncateSuffix(_ lastIndex: UInt) {
        memoryLog.truncateSuffix(lastIndex)
    }

    __consuming func makeIterator() -> Iterator {
        memoryLog.makeIterator()
    }
}

//MARK: Metadata

/// Logs metadata file manager. Provide methods to read/write into stable storage. Storage is sync and blocking
/// Use protobuf model for storage on the disk
/// Each method are isolated
/// TODO:
///   - Check if open 1 descriptor can be more beneficial
class LogMetadataFileStorage {

    enum Error: Swift.Error {
        case metadataNotEncodable
        case failedToOpenFile(FilePath, Swift.Error)
        case failedToWriteFile(FilePath)
        case failedToReadFile(FilePath)
        case failedToParseMetadata
    }

    /// Metadata file path
    let filePath: FilePath

    init(filePath: FilePath) {
        self.filePath = filePath
    }

    func save(metadata: LogMetadata) throws {
        let message = Raft_LogMetadata.with {
            if let termId = metadata.termID {
                $0.term = termId
            }
            if let voteFor = metadata.voteFor {
                $0.voteFor = voteFor
            }
        }
        // TODO What to do if we can't encode metadata? Should delete existing file?
        guard let data = try? message.serializedData() else {
            throw Error.metadataNotEncodable
        }

        do {
            let descriptor = try FileDescriptor.open(filePath,
                                                     .writeOnly,
                                                     options: [.create],
                                                     permissions: [.ownerReadWrite, .groupReadWrite])
            _ = try descriptor.closeAfter {
                try data.withUnsafeBytes {
                    _ = try descriptor.write($0)
                }
            }
        } catch {
            throw Error.failedToWriteFile(filePath)
        }
    }

    func load() throws -> LogMetadata? {
        do {
            let descriptor = try FileDescriptor.open(filePath, .readOnly)
            return try descriptor.closeAfter { () -> LogMetadata in

                // TODO Read any file size
                // Read file into a data buffer
                let data = try Array<UInt8>.init(unsafeUninitializedCapacity: 20) { (buf, count) in
                    count = try descriptor.read(into: UnsafeMutableRawBufferPointer(buf))
                }

                // Parse data into protobuf message
                guard let message = try? Raft_LogMetadata(contiguousBytes: data) else {
                    throw Error.failedToParseMetadata
                }

                return LogMetadata(termID: message.hasTerm ? message.term : nil,
                                   voteFor: message.hasVoteFor ? message.voteFor : nil)
            }
        } catch let error as Errno {
            if error == .noSuchFileOrDirectory {
                // File do not exist yet => there are no metadata
                return nil
            }
            throw Error.failedToOpenFile(filePath, error)
        } catch {
            throw Error.failedToReadFile(filePath)
        }
    }
}
