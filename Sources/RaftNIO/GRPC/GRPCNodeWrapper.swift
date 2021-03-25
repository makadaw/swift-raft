// SPDX-License-Identifier: MIT
// Copyright © 2021 makadaw


import SwiftRaft
import NIO
import GRPC

// Glue class that connect GRPC (NIO) runtime with Raft actors
class GRPCNodeWrapper<ApplicationLog>: Raft_RaftProvider where ApplicationLog: Log {
    var interceptors: Raft_RaftServerInterceptorFactoryProtocol? {
        nil
    }

    let node: Node<ApplicationLog>

    init(node: Node<ApplicationLog>) {
        self.node = node
    }

    func requestVote(request: Raft_RequestVote.Request, context: StatusOnlyCallContext) -> EventLoopFuture<Raft_RequestVote.Response> {
        let promise = context.eventLoop.makePromise(of: Raft_RequestVote.Response.self)
        let node = self.node
        Task.runDetached {
            let raftRequest = RequestVote.Request(type: request.type == .vote ? .vote : .preVote,
                                                  termID: request.term,
                                                  candidateID: request.candidateID,
                                                  lastLogIndex: request.lastLogIndex,
                                                  lastLogTerm: request.lastLogTerm)
            let response = await node.onVoteRequest(raftRequest)
            promise.succeed(Raft_RequestVote.Response.with({
                $0.type = response.type == .vote ? .vote : .preVote
                $0.term = response.termID
                $0.voteGranted = response.voteGranted
            }))
        }
        return promise.futureResult
    }

    func appendEntries(request: Raft_AppendEntries.Request, context: StatusOnlyCallContext) -> EventLoopFuture<Raft_AppendEntries.Response> {
        let promise = context.eventLoop.makePromise(of: Raft_AppendEntries.Response.self)
        let node = self.node
        Task.runDetached {
            let raftReqeust = AppendEntries.Request<ApplicationLog.Data>(termID: request.term,
                                                                         leaderID: request.leaderID,
                                                                         prevLogIndex: request.prevLogIndex,
                                                                         prevLogTerm: request.prevLogTerm,
                                                                         leaderCommit: request.leaderCommit,
                                                                         entries: [] ) // request.entries.map(LogElement<ApplicationLog.Data>.init)
            let response = await node.onAppendEntries(raftReqeust)
            promise.succeed(Raft_AppendEntries.Response.with({
                $0.term = response.termID
                $0.success = response.success
            }))
        }
        return promise.futureResult
    }
}

extension Raft_AppendEntries.Request: UnsafeConcurrentValue {}
extension Raft_RequestVote.Request: UnsafeConcurrentValue {}
extension EventLoopPromise: UnsafeConcurrentValue {}
