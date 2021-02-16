// SPDX-License-Identifier: MIT
// Copyright © 2021 makadaw


public protocol Peer {
    func requestVote(_ request: Consensus.RequestVote.Request) async -> Consensus.RequestVote.Response
}

extension RandomAccessCollection where Element == Peer {

    /// Quorum size should be higher then half
    var quorumSize: UInt {
        UInt(count/2 + 1)
    }
}
