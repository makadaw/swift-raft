// SPDX-License-Identifier: MIT
// Copyright © 2021 makadaw

import GRPC
import NIO
import NIOConcurrencyHelpers
import Logging

/// Implementation of RPC service for Raft consensus
class ConsensusService {

    enum State {
        case follower
        case preCandidate
        case candidate
        case leader
    }

    private let group: EventLoopGroup
    private let config: Configuration
    private let logger: Logger
    var interceptors: Raft_RaftServerInterceptorFactoryProtocol?

    /// Current node id
    var myself: NodeId {
        config.server.id
    }

    /// List of active peers for the current node
    private var peers: [Peer]

    /// Node current state, should not be changed directly, only via `tryBecome...` methods. Node start as a follower
    /// Lock value
    private(set) var state: State = .follower

    /// Latest term server has seen, increases monotonically
    /// Lock value
    private(set) var term: Term

    private let lock: Lock = .init()
    // Timers
    var electionTimer: Scheduled<Void>?
    var heartbeatTask: RepeatedTask?

    init(group: EventLoopGroup, config: Configuration, peers: [Peer], log: Logger) {
        self.group = group
        self.config = config
        self.peers = peers
        self.logger = log
        self.term = Term(myself: config.server.id)
    }

    func onStart() {
        self.resetElectionTimer()
    }

    /// States switch machine
    private func _tryMoveTo(nextState: State) -> Bool {
        lock.withLock { () -> Bool in
            if state.isValidNext(state: nextState) {
                self.state = nextState
                return true
            }
            return false
        }
    }

    func tryBecomePreCandidate() -> Bool {
        if !_tryMoveTo(nextState: .preCandidate) {
            return false
        }
        electionTimer?.cancel()
        heartbeatTask?.cancel()
        startPreVote()
        return true
    }

    func tryBecomeCandidate() -> Bool {
        if !_tryMoveTo(nextState: .candidate) {
            return false
        }
        // Stop an election timer and start vote
        electionTimer?.cancel()
        heartbeatTask?.cancel()
        startVote()
        return true
    }

    func tryBecomeFollower() -> Bool {
        if !_tryMoveTo(nextState: .follower) {
            return false
        }
        heartbeatTask?.cancel()
        resetElectionTimer()
        return true
    }

    func tryBecomeLeader() -> Bool {
        if !_tryMoveTo(nextState: .leader) {
            return false
        }
        // Stop election timer and schedule heartbeat
        electionTimer?.cancel()
        resetHeartbeatTimer()
        return true
    }

}

extension ConsensusService: Raft_RaftProvider {

    /// 1. Reply false if term `<` currentTerm (§5.1)
    /// 2. If votedFor is null or candidateId, and candidate’s log is at least as up-to-date as receiver’s log, grant vote (§5.2, §5.4)
    func requestVote(request: Raft_RequestVote.Request, context: StatusOnlyCallContext) -> EventLoopFuture<Raft_RequestVote.Response> {
        lock.withLockVoid {
            if case .leader = state {
            } else {
                self.resetElectionTimer()
            }
        }

        let granted: Bool = lock.withLock {
            if request.type == .preVote {
                return request.term > term.id
            } else {
                return term.canAcceptNewTerm(request.term, from: request.candidateID)
            }
        }
        let response = Raft_RequestVote.Response.with {
            $0.type = request.type
            $0.term = request.term
            $0.voteGranted = granted
        }
        logger.debug("Vote response \(response.voteGranted)", metadata: [
            "vote/self": "\(myself)",
            "vote/candidate": "\(request.candidateID)",
            "vote/granted": "\(response.voteGranted)"
        ])
        return context.eventLoop.makeSucceededFuture(response)
    }

    /// 1. Reply false if term `<` currentTerm (§5.1)
    /// 2. Reply false if log doesn’t contain an entry at prevLogIndex whose term matches prevLogTerm (§5.3)
    /// 3. If an existing entry conflicts with a new one (same index but different terms), delete the existing entry and all that follow it (§5.3)
    /// 4. Append any new entries not already in the log
    /// 5. If leaderCommit > commitIndex, set commitIndex = min(leaderCommit, index of last new entry)
    func appendEntries(request: Raft_AppendEntries.Request, context: StatusOnlyCallContext) -> EventLoopFuture<Raft_AppendEntries.Response> {
        lock.withLockVoid {
            if case .leader = state {
            } else {
                self.resetElectionTimer()
            }
        }

        let messageCheck: (Bool, Term) = lock.withLock {
            if request.term > self.term.id {
                // got a message with higher term, step down to a follower
                do {
                    try self.term.tryToUpdateTerm(newTerm: request.term, from: request.leaderID)
                } catch let error {
                    logger.error("\(error)")
                }
                return (true, self.term)
            }
            if self.term.leader == nil {
                self.term.leader = request.leaderID
            }
            return (false, self.term)
        }
        let (shouldStepDown, term) = messageCheck
        if shouldStepDown {
            // Next method have own lock, should be called not from lock
            if !tryBecomeFollower() {
                logger.debug("Got term greate than current and failed to move to the follower")
            }
            let response = Raft_AppendEntries.Response.with {
                $0.term = term.id
                $0.success = false
            }
            return context.eventLoop.makeSucceededFuture(response)
        }

        let response = Raft_AppendEntries.Response.with {
            $0.term = term.id
            // TODO check logs ids
            $0.success = tryBecomeFollower()
        }

        logger.debug("Receive message", metadata: [
            "message/term": "\(term.id)",
            "message/leader": "\(term.leader ?? 0)"
        ])
        return context.eventLoop.makeSucceededFuture(response)
    }
}

//MARK: Election
extension ConsensusService {

    enum ElectionError: Error {
        case cantMoveToCandidateState
    }

    /// Election timer if reached will initiate a vote, reset it if we are still in the valid state
    /// - when get a heartbeat in follower state
    /// - when vote failed and we need to restart a round
    func resetElectionTimer() {
        // cancel old timer
        if let electionTimer = electionTimer {
            electionTimer.cancel()
        }
        // randomize election timer
        let timeout = config.electionTimeout
            + .nanoseconds(Int64.random(in: 1000...config.electionTimeout.nanoseconds))
        electionTimer = group.next().scheduleTask(in: timeout, electionTimeout)
    }

    /// Election timeout fired, if node is not a leader start a campaign
    func electionTimeout() {
        if case .leader = state {
            return
        }
        logger.debug("Node \(myself) would start an election campaign")
        if !tryBecomePreCandidate() {
            // Failed to switch state, just reset an election timer and wait for a next round
            resetElectionTimer()
        }
    }

    /// Before real campaign we start `primaries` to check if we can win
    func startPreVote() {
        let vote = startVote(isPreVote: true)
        vote.whenSuccess { result in
            if result {
                // TODO Error log
                _ = self.tryBecomeCandidate()
            } else {
                self.resetElectionTimer()
            }
        }
        vote.whenFailure { err in
            self.logger.error("Lost a preVote with \(err)")
            self.resetElectionTimer()
        }
    }

    /// Start an election campaign and election timer
    func startVote() {
        let vote = startVote(isPreVote: false)
        vote.whenSuccess { result in
            self.logger.debug("Finish campign", metadata: [
                "vote/result": "\(result)",
                "vote/term": "\(self.term)"
            ])
            if !(result && self.tryBecomeLeader()) { // Won an election
                self.logger.debug("Failed to become a leader for \(self.term) term")
            }
        }
        vote.whenFailure { err in
            self.logger.debug("Failed to finish election with error \(err)")
        }
        self.resetElectionTimer()
    }

    private func startVote(isPreVote: Bool) -> EventLoopFuture<Bool> {
        let resultPromise = group.next().makePromise(of: Bool.self)
        let allReqeusts = group.next().flatSubmit { () -> EventLoopFuture<Void> in
            let termId = self.lock.withLock { () -> Term.Id in
                let next = self.term.nextTerm()
                if !isPreVote {
                    self.term = next
                }
                return next.id
            }
            let tallyVotes = self.peers.quorumSize
            let grantedVotes: NIOAtomic<UInt> = NIOAtomic.makeAtomic(value: 1) // We already votes for ourself

            self.logger.debug("Starting a \(isPreVote ? "pre " : "")campign", metadata: [
                "vote/term": "\(termId)",
                "vote/type": isPreVote ? "pre" : "real",
            ])

            return EventLoopFuture.andAllComplete(self.peers.map { peer -> EventLoopFuture<Bool> in
                peer.requestVote(isPreVote: isPreVote, term: termId).always { result in
                    // Check is response is true and we still in the same term when started
                    if case let .success(accepted) = result,
                       accepted,
                       isPreVote || termId == self.lock.withLock({ self.term.id }) {
                        if grantedVotes.add(1) >= tallyVotes {
                            // Won an election, promises are one shoot by definition
                            resultPromise.succeed(true)
                        }
                    }
                }
            }, on: self.group.next())
        }
        allReqeusts.whenSuccess {
            // Send false on finish if we don't have enough votes
            resultPromise.succeed(false)
        }
        allReqeusts.cascadeFailure(to: resultPromise)
        return resultPromise.futureResult
    }
}

//MARK: Leader

extension ConsensusService {

    enum AppendLogError: Error {
        case notALeaderTryToHeartbeat
    }

    func resetHeartbeatTimer() {
        if let heartbeatTask = heartbeatTask {
            heartbeatTask.cancel()
        }
        heartbeatTask = group.next().scheduleRepeatedAsyncTask(initialDelay: TimeAmount.zero,
                                                               delay: heartbeatTimeout(),
                                                               heartbeat)
    }

    func heartbeatTimeout() -> TimeAmount {
        return config.heartbeatPeriod
    }

    func heartbeat(task: RepeatedTask) -> EventLoopFuture<Void> {
        guard case .leader = state else {
            logger.error("Not a leader tried to send a heartbeat message")
            heartbeatTask?.cancel()
            return group.next().makeFailedFuture(AppendLogError.notALeaderTryToHeartbeat)
        }
        // Send heartbeat to all peers
        return EventLoopFuture.andAllComplete(peers.map({ peer -> EventLoopFuture<Bool> in
            return peer.sendHeartbeat(term: self.term)
        }), on: group.next())
    }

}

extension ConsensusService.State {
    func  isValidNext(state nextState: ConsensusService.State) -> Bool {
        guard self != nextState else {
            return true
        }
        switch (self, nextState) {
        case (.follower, .preCandidate), (.follower, .candidate):
            return true
        case (.preCandidate, .candidate), (.preCandidate, .follower):
            return true
        case (.candidate, .leader), (.candidate, .follower):
            return true
        // Technically we should move from a leader only to a follower, but it's important to step down in any case
        case (.leader, _):
            return true
        default:
            return false
        }
    }
}
