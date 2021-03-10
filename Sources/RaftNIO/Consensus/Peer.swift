// SPDX-License-Identifier: MIT
// Copyright © 2021 makadaw


import SwiftRaft
import GRPC
import NIO

/// Peer interface
class Peer {
    /// Current node id
    let myself: NodeID

    /// Remote peer configuration, uniq for peer
    let config: Configuration.Peer

    /// RPC related configuration, the same for all peers
    let rpcConfig: Configuration.RPC

    private let client: Raft_RaftClientProtocol
    private let group: EventLoopGroup

    init(myself: NodeID, config: Configuration.Peer, rpcConfig: Configuration.RPC, group: EventLoopGroup) {
        self.myself = myself
        self.config = config
        self.rpcConfig = rpcConfig
        self.group = group
        let channel = ClientConnection
            .insecure(group: group)
            .withConnectionTimeout(minimum: .milliseconds(10))
            .connect(host: config.host, port: config.port)
        self.client = Raft_RaftClient(channel: channel)
    }

    func requestVote(isPreVote: Bool = false,
                     term: Term.ID,
                     lastLogIndex: UInt,
                     lastLogTerm: Term.ID) -> EventLoopFuture<Bool> {
        let request = Raft_RequestVote.Request.with {
            $0.type = isPreVote ? .preVote : .vote
            $0.candidateID = myself
            $0.term = term
            $0.lastLogIndex = UInt64(lastLogIndex)
            $0.lastLogTerm = lastLogTerm
        }

        let promise = group.next().makePromise(of: Bool.self)

        let response = client.requestVote(
            request,
            callOptions: CallOptions(timeLimit: .timeout(.nanoseconds(rpcConfig.voteTimeout.nanoseconds))))
        response.response.whenSuccess { message in
            promise.succeed(message.voteGranted)
        }
        response.response.whenFailure { _ in
            // In case of any errors with connection fired false
            promise.succeed(false)
        }
        return promise.futureResult
    }

    func sendHeartbeat(term: Term) -> EventLoopFuture<Bool> {
        let request = Raft_AppendEntries.Request.with {
            $0.term = term.id
            $0.leaderID = myself
            $0.entries = [] // Hearbeat send empty entries
        }

        let promise = group.next().makePromise(of: Bool.self)

        let response = client.appendEntries(
            request,
            callOptions: CallOptions(timeLimit: .timeout(.nanoseconds(rpcConfig.appendMessageTimeout.nanoseconds))))
        response.response.whenSuccess { _ in
            // TODO do a check here
            promise.succeed(true)
        }
        response.response.whenFailure { _ in
            // In case of any errors with connection fired false
            promise.succeed(false)
        }
        return promise.futureResult
    }
}


extension RandomAccessCollection where Element == Peer {

    /// Quorum size should be higher then half
    var quorumSize: UInt {
        UInt(count/2 + 1)
    }
}
