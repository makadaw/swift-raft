// SPDX-License-Identifier: MIT
// Copyright © 2021 makadaw


public struct LogMetadata: Equatable {
    public var termId: Term.ID?
    public var voteFor: NodeID?

    public init(termId: Term.ID? = nil, voteFor: NodeID? = nil) {
        self.termId = termId
        self.voteFor = voteFor
    }

    mutating public func updateTerm(_ term: Term) {
        termId = term.id
        voteFor = term.votedFor
    }
}
