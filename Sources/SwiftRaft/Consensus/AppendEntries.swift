// SPDX-License-Identifier: MIT
// Copyright © 2021 makadaw


public struct AppendEntries {

    public struct Request<T: LogData>: Sendable {
        public typealias Element = LogElement<T>

        /// Current leader term id. Followers use them to validate correctness
        public let termID: Term.ID

        /// Leader id in the cluster
        public let leaderID: NodeID

        /// Index of log entry immediately preceding new ones
        public let prevLogIndex: UInt64

        /// Term id of prevLogIndex entry
        public let prevLogTerm: UInt64

        /// Leader’s commit index
        public let leaderCommit: UInt64

        // TODO Make sure compiler can check that generic argument is `ConcurrentValue`
        /// Log entries to store (empty for heartbeat; may send more than one for efficiency)
//        public let entries: [Element]

        public init(termID: Term.ID,
                    leaderID: NodeID,
                    prevLogIndex: UInt64,
                    prevLogTerm: UInt64,
                    leaderCommit: UInt64,
                    entries: [Element]) {
            self.termID = termID
            self.leaderID = leaderID
            self.prevLogIndex = prevLogIndex
            self.prevLogTerm = prevLogTerm
            self.leaderCommit = leaderCommit
//            self.entries = entries
        }
    }

    public struct Response: Sendable {
        /// Current node term, for leader to update itself
        public let termID: Term.ID

        /// True if a follower accepted the message
        public let success: Bool

        public init(termID: Term.ID, success: Bool) {
            self.termID = termID
            self.success = success
        }
    }
}
