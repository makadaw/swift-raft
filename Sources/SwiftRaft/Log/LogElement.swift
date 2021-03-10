// SPDX-License-Identifier: MIT
// Copyright © 2021 makadaw


import Foundation

/// Protocol constraints for Data that we can store in the Log entry. This protocol should be implemented
/// by consumer and represent application data, not Raft types
public protocol LogData: ConcurrentValue {
    // TODO Replace foundation Data with custom type
    init?(data: Data)

    /// Log element data size in bytes
    var size: Int { get }
}

/// Log can contained not only application data, but also Raft messages
public enum LogElement<T: LogData>: ConcurrentValue {
    case configuration(termId: Term.ID, index: UInt64)
    case data(termId: Term.ID, index: UInt64, content: T)
}

public extension LogElement {
    var term: Term.ID {
        switch self {
        case let .configuration(termId, _):
            return termId
        case let .data(termId, _, _):
            return termId
        }
    }

    var index: UInt64 {
        switch self {
        case let .configuration(_, index):
            return index
        case let .data(_, index, _):
            return index
        }
    }

    var sizeBytes: Int {
        switch self {
        case .configuration:
            return 0
        case let .data(_, _, data):
            return data.size
        }
    }

    var content: T? {
        switch self {
        case .configuration:
            return nil
        case let .data(_, _, content):
            return content
        }
    }
}
