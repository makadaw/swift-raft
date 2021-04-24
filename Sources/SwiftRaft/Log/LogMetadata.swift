// SPDX-License-Identifier: MIT
// Copyright © 2021 makadaw


public struct LogMetadata: Equatable, Sendable {
    public var termID: Term.ID?
    public var voteFor: NodeID?

    public init(termID: Term.ID? = nil, voteFor: NodeID? = nil) {
        self.termID = termID
        self.voteFor = voteFor
    }

    mutating public func updateTerm(_ term: Term) {
        termID = term.id
        voteFor = term.votedFor
    }
}
