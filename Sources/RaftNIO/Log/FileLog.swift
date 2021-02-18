// SPDX-License-Identifier: MIT
// Copyright © 2021 makadaw


import SystemPackage
import NIO
import SwiftProtobuf
import Foundation

// File log, simple implementation for prototype
// TODO:
//   - Do not use Foundation IO
//   - Use async IO for non-blocking operation
struct FileLog<T: LogData>: Log {
    typealias Data = T
    typealias Iterator = MemoryLog<Data>.Iterator

    // MARK: Files
    private let root: FilePath
    private let metadataPath: FilePath
    private var memoryLog: MemoryLog<Data>
    var metadata: LogMetadata {
        didSet {
            do {
                try Self.saveMetadata(metadata, to: metadataPath)
            } catch {
                // TODO log error
            }
        }
    }

    init(root: FilePath, metadataFileName: String = "metadata") {
        self.root = root
        if !FileManager.default.fileExists(atPath: root.string) {
            try! FileManager.default.createDirectory(atPath: root.string, withIntermediateDirectories: true)
        }

        self.metadataPath = root.appending(metadataFileName)

        // Load metadata file
        metadata = Self.loadMetadata(from: metadataPath)

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

// TODO: Do not use FileManager directly
extension FileLog {

    static func loadMetadata(from: FilePath) -> LogMetadata {
        if FileManager.default.fileExists(atPath: from.string),
           let data = try? Foundation.Data(contentsOf: from.toURL),
           let metadata = try? Raft_LogMetadata(serializedData: data) {
            return LogMetadata.from(message: metadata)
        }

        return LogMetadata()
    }

    // TODO should be async
    static func saveMetadata(_ metadata: LogMetadata, to: FilePath) throws {
        let data = try metadata.toMessage().serializedData()
        try data.write(to: to.toURL, options: .atomic)
    }
}
