// SPDX-License-Identifier: MIT
// Copyright © 2021 makadaw


import NIO

/// Log errors
enum LogError: Error {
    case outOfRange
}

/// Represent a Raft log
protocol Log: Sequence where Element == LogElement<Data> {
    associatedtype Data: LogData

    /// First index in the log, it could be not 0 as log can be trimmed
    var logStartIndex: UInt { get }

    /// Last index, should be higher than start index
    var logLastIndex: UInt { get }

    /// Return size of all elements data in bytes. Without additional data (term id, index, etc)
    var sizeBytes: UInt { get }

    /// Amount of elements in the log. Use Int to keep closer to other Swift collections
    var count: Int { get }

    /// Get an element at log position. As log can be compacted we may not have an element at current position
    /// If element is not present method will throw the LogError.outOfRange
    /// - Parameter position: Log element position, absolute number
    func entry(at position: UInt) throws -> LogElement<Data>

    /// Start to append new entries to the log. The entries may not be in the stable storage yet when this returns
    /// - Parameter entries: range of indexes of the new entries in the log, closed
    mutating func append(_ entries: [LogElement<Data>]) -> ClosedRange<UInt>

    /// Truncate entities before index
    mutating func truncatePrefix(_ firstIndex: UInt)

    /// Truncate entities after index
    mutating func truncateSuffix(_ lastIndex: UInt)

    /// Associated data with the current log
    var metadata: LogMetadata { get set }
}

extension Log {
    var sizeBytes: UInt {
        UInt(reduce(0) { acc, element in
            acc + element.sizeBytes
        })
    }
}
