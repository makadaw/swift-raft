// SPDX-License-Identifier: MIT
// Copyright © 2021 makadaw


import SwiftRaft
import NIO
import GRPC

// This type provides transform Raft messages into GRPC messages and back
@available(macOS 9999, *)
actor GRPCPeer: SwiftRaft.Peer {
    /// Remote peer configuration, uniq for peer
    let config: Configuration.Peer

    /// RPC related configuration, the same for all peers
    let rpcConfig: Configuration.RPC

    private let client: Raft_RaftClientProtocol
    private let group: EventLoopGroup

    init(config: Configuration.Peer, rpcConfig: Configuration.RPC, group: EventLoopGroup) {
        self.config = config
        self.rpcConfig = rpcConfig
        self.group = group
        let channel = ClientConnection
            .insecure(group: group)
            .withConnectionTimeout(minimum: .milliseconds(10))
            .connect(host: config.host, port: config.port)
        self.client = Raft_RaftClient(channel: channel)
    }

    func requestVote(_ request: RequestVote.Request) async throws -> RequestVote.Response {
        let rpcRequest = Raft_RequestVote.Request.with {
            $0.type = request.type == .vote ? .vote : .preVote
            $0.candidateID = request.candidateID
            $0.term = request.termID
            $0.lastLogIndex = request.lastLogIndex
            $0.lastLogTerm = request.lastLogTerm
        }

        let promise = group.next().makePromise(of: RequestVote.Response.self)

        let response = client.requestVote(
            rpcRequest,
            callOptions: CallOptions(timeLimit: .timeout(.nanoseconds(rpcConfig.voteTimeout.nanoseconds))))
        response.response.whenSuccess { message in
            promise.succeed(.init(type: message.type == .vote ? .vote : .preVote,
                                  termID: message.term,
                                  voteGranted: message.voteGranted))
        }
        return try await promise.futureResult.get()
    }

    func sendHeartbeat<T>(_ request: AppendEntries.Request<T>) async throws -> AppendEntries.Response where T : LogData {
        let rpcRequest = Raft_AppendEntries.Request.with {
            $0.term = request.termID
            $0.leaderID = request.leaderID
            $0.leaderCommit = request.leaderCommit
            $0.prevLogIndex = request.prevLogIndex
            $0.prevLogTerm = request.prevLogTerm
        }

        let promise = group.next().makePromise(of: AppendEntries.Response.self)

        let response = client.appendEntries(
            rpcRequest,
            callOptions: CallOptions(timeLimit: .timeout(.nanoseconds(rpcConfig.appendMessageTimeout.nanoseconds))))
        response.response.whenSuccess { message in
            promise.succeed(.init(termID: message.term,
                                  success: message.success))
        }
        return try await promise.futureResult.get()
    }
}
