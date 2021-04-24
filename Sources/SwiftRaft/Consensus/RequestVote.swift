// SPDX-License-Identifier: MIT
// Copyright © 2021 makadaw


/// Vote request message. Use for both pre and real vote
public struct RequestVote {

    public enum VoteType: Sendable {
        case preVote
        case vote
    }

    public struct Request: Sendable {
        /// Vote type `vote` or `PreVote`
        public let type: VoteType

        public let rand = 1

        /// Candidate’s term
        public let termID: Term.ID

        /// Candidate requesting vote
        public let candidateID: NodeID

        /// Index of candidate’s last log entry
        public let lastLogIndex: UInt64

        /// Term of candidate’s last log entry
        public let lastLogTerm: UInt64

        public init(type: VoteType, termID: Term.ID, candidateID: NodeID, lastLogIndex: UInt64, lastLogTerm: UInt64) {
            self.type = type
            self.termID = termID
            self.candidateID = candidateID
            self.lastLogIndex = lastLogIndex
            self.lastLogTerm = lastLogTerm
        }

    }

    public struct Response: Sendable {
        /// Vote type `vote` or `PreVote`, should be the the same as in request
        public let type: VoteType

        /// Current term of the node, for candidate to update itself
        public let termID: Term.ID

        /// True means candidate received vote
        public let voteGranted: Bool

        public init(type: VoteType, termID: Term.ID, voteGranted: Bool) {
            self.type = type
            self.termID = termID
            self.voteGranted = voteGranted
        }
    }
}
