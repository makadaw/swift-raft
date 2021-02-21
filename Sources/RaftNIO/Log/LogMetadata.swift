// SPDX-License-Identifier: MIT
// Copyright © 2021 makadaw


import SwiftRaft

struct LogMetadata {
    var termId: Term.ID?
    var voteFor: NodeID?

    mutating func updateTerm(_ term: Term) {
        termId = term.id
        voteFor = term.votedFor
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
