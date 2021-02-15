// SPDX-License-Identifier: MIT
// Copyright © 2021 makadaw

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
    private let root: Path
    private let metadataPath: Path
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

    init(root: Path, metadataFileName: String = "metadata") {
        guard let metadataPath = try? root.appending(metadataFileName) else {
            fatalError("Metadata filename or root path not really paths")
        }
        self.root = root
        if !FileManager.default.fileExists(atPath: root.absolutePath) {
            try! FileManager.default.createDirectory(atPath: root.absolutePath, withIntermediateDirectories: true)
        }

        self.metadataPath = metadataPath

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

    static func loadMetadata(from: Path) -> LogMetadata {
        if FileManager.default.fileExists(atPath: from.absolutePath),
           let data = try? Foundation.Data(contentsOf: from.toURL),
           let metadata = try? Raft_LogMetadata(serializedData: data) {
            return LogMetadata.from(message: metadata)
        }

        return LogMetadata()
    }

    // TODO should be async
    static func saveMetadata(_ metadata: LogMetadata, to: Path) throws {
        let data = try metadata.toMessage().serializedData()
        try data.write(to: to.toURL, options: .atomic)
    }
}
