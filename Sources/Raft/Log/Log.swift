// SPDX-License-Identifier: MIT
// Copyright © 2021 makadaw

import NIO
import Foundation

/// Log errors
enum LogError: Error {
    case outOfRange
}

struct LogMetadata {
    var termId: Term.Id?
    var voteFor: NodeId?

    mutating func updateTerm(_ term: Term) {
        termId = term.id
        voteFor = term.votedFor
    }
}

/// Represent a Raft log. Maybe should be a Collection
protocol Log: Sequence where Element == LogElement<Data> {
    associatedtype Data: LogData

    var logStartIndex: UInt { get }
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

    mutating func truncatePrefix(_ firstIndex: UInt)
    mutating func truncateSuffix(_ lastIndex: UInt)

    /// Log also used to store current term of the node. Node will read it on start to restore term
    var metadata: LogMetadata { get set }
}

extension Log {
    var sizeBytes: UInt {
        UInt(reduce(0) { acc, element in
            acc + element.sizeBytes
        })
    }
}

extension LogMetadata {
    func toMessage() -> Raft_LogMetadata {
        Raft_LogMetadata.with {
            if let termId = self.termId {
                $0.term = termId
            }
            if let voteFor = self.voteFor {
                $0.voteFor = voteFor
            }
        }
    }

    static func from(message: Raft_LogMetadata) -> LogMetadata {
        LogMetadata(termId: message.hasTerm ? message.term : nil,
                    voteFor: message.hasVoteFor ? message.voteFor : nil)
    }
}
