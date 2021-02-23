// SPDX-License-Identifier: MIT
// Copyright © 2021 makadaw


import SwiftRaft

struct LogMetadata: Equatable {
    var termId: Term.ID?
    var voteFor: NodeID?

    mutating func updateTerm(_ term: Term) {
        termId = term.id
        voteFor = term.votedFor
    }
}
