// SPDX-License-Identifier: MIT
// Copyright © 2021 makadaw


import Foundation

/// Protocol constraints for Data that we can store in the Log entry. This protocol should be implemented
/// by consumer and represent application data, not Raft types
protocol LogData {
    init?(data: Data)

    /// Log element data size in bytes
    var size: Int { get }
}


/// Log can contained not only application data, but also Raft messages
enum LogElement<T: LogData> {
    case configuration(termId: Term.Id, index: UInt64)
    case data(termId: Term.Id, index: UInt64, data: T)
}

extension LogElement {
    init?(_ raftLog: Raft_Entry) {
        switch raftLog.type {
            case .configuration:
                self = LogElement.configuration(termId: raftLog.term, index: raftLog.index)
            case .data:
                guard let data = T.init(data: raftLog.data) else {
                    return nil
                }
                self = LogElement.data(termId: raftLog.term, index: raftLog.index, data: data)
            default:
                return nil
        }
    }
}

extension LogElement {
    var term: Term.Id {
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
        case .configuration(_, _):
            return 0
        case let .data(_, _, data):
            return data.size
        }
    }

    var data: T? {
        switch self {
        case .configuration(_, _):
            return nil
        case let .data(_, _, data):
            return data
        }
    }
}
