// SPDX-License-Identifier: MIT
// Copyright © 2021 makadaw

import GRPC
import NIO
import NIOConcurrencyHelpers
import Logging

/// Implementation of RPC service for Raft consensus
class ConsensusService<ApplicationLog> where ApplicationLog: Log {

    enum State {
        case follower
        case preCandidate
        case candidate
        case leader
    }

    private let group: EventLoopGroup
    private let eventLoop: EventLoop
    private let config: Configuration
    private let logger: Logger
    var interceptors: Raft_RaftServerInterceptorFactoryProtocol?

    /// Current node id
    var myself: NodeId {
        config.server.id
    }

    /// List of active peers for the current node
    private var peers: [Peer]

    /// Node current state, should not be changed directly, only via `_tryMoveTo(nextState:)` method. Node start as a follower
    /// Lock value
    private(set) var state: State = .follower {
        didSet {
            switch state {
                case .follower:
                    heartbeatTask?.cancel()
                    resetElectionTimer()

                case .preCandidate:
                    electionTimer?.cancel()
                    heartbeatTask?.cancel()
                    startPreVote()

                case .candidate:
                    electionTimer?.cancel()
                    heartbeatTask?.cancel()
                    startVote()

                case .leader:
                    electionTimer?.cancel()
                    resetHeartbeatTimer()
            }
        }
    }

    /// Latest term server has seen, increases monotonically
    /// Lock value
    private(set) var term: Term {
        didSet {
            // Update term in the log
            self.log.metadata.updateTerm(term)
        }
    }

    /// Application log
    var log: ApplicationLog

    private let lock: Lock = .init()
    // Timers
    var electionTimer: Scheduled<Void>?
    var heartbeatTask: RepeatedTask?

    init(group: EventLoopGroup, config: Configuration, peers: [Peer], log: ApplicationLog, logger: Logger) {
        self.group = group
        self.eventLoop = group.next()
        self.config = config
        self.peers = peers
        self.logger = logger

        self.log = log
        self.log.filter({ element in
            if case .configuration = element {
                return true
            }
            return false
        }).forEach { entity in
            // TODO apply configurations from the log
            print("Configuration \(entity)")
        }
        self.logger.debug("The log contains indexes \(log.logStartIndex) through \(log.logLastIndex)")
        self.term = Term(myself: config.server.id, id: log.metadata.termId ?? 0)
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

        let (granted, currentTermId) = lock.withLock { () -> (Bool, Term.Id) in
            let lastLogTerm = self.log.metadata.termId ?? 0
            // If the caller has a less complete log, we can't give it our vote.
            let isLogOk = request.lastLogTerm > lastLogTerm
                        || (request.lastLogTerm == lastLogTerm
                            && request.lastLogIndex >= self.log.logLastIndex)
            if request.type == .preVote {
                return (isLogOk && request.term > term.id, term.id)
            } else {

                return (isLogOk && term.canAcceptNewTerm(request.term, from: request.candidateID), term.id)
            }
        }
        let response = Raft_RequestVote.Response.with {
            $0.type = request.type
            $0.term = currentTermId
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

        let (shouldStepDown, term) = lock.withLock { () -> (Bool, Term) in
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
        if shouldStepDown {
            // Next method have own lock, should be called not from lock
            if !_tryMoveTo(nextState: .follower) {
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
            $0.success = _tryMoveTo(nextState: .follower)
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
        // randomise election timer
        let timeout = config.electionTimeout
            + .nanoseconds(Int64.random(in: 1000...config.electionTimeout.nanoseconds))
        electionTimer = eventLoop.scheduleTask(in: timeout, electionTimeout)
    }

    /// Election timeout fired, if node is not a leader start a campaign
    func electionTimeout() {
        if case .leader = state {
            return
        }
        logger.debug("Node \(myself) would start an election campaign")
        if !_tryMoveTo(nextState: .preCandidate) {
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
                _ = self._tryMoveTo(nextState: .candidate)
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
            if !(result && self._tryMoveTo(nextState: .leader)) { // Won an election
                self.logger.debug("Failed to become a leader for \(self.term) term")
            }
        }
        vote.whenFailure { err in
            self.logger.debug("Failed to finish election with error \(err)")
        }
        self.resetElectionTimer()
    }

    private func startVote(isPreVote: Bool) -> EventLoopFuture<Bool> {
        let resultPromise = eventLoop.makePromise(of: Bool.self)
        let allRequests = eventLoop.flatSubmit { () -> EventLoopFuture<Void> in
            let (termId, lastLogIndex, lastLogTerm) = self.lock.withLock { () -> (Term.Id, UInt, Term.Id) in
                let next = self.term.nextTerm()
                if !isPreVote {
                    self.term = next
                }
                return (next.id, self.log.logLastIndex, self.log.metadata.termId ?? 0)
            }
            let tallyVotes = self.peers.quorumSize
            let grantedVotes: NIOAtomic<UInt> = NIOAtomic.makeAtomic(value: 1) // We already votes for ourself

            self.logger.debug("Starting a \(isPreVote ? "pre " : "")campign", metadata: [
                "vote/term": "\(termId)",
                "vote/type": isPreVote ? "pre" : "real",
            ])

            return EventLoopFuture.andAllComplete(self.peers.map { peer -> EventLoopFuture<Bool> in
                peer.requestVote(isPreVote: isPreVote,
                                 term: termId,
                                 lastLogIndex: lastLogIndex,
                                 lastLogTerm: lastLogTerm).always { result in
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
            }, on: self.eventLoop)
        }
        allRequests.whenSuccess {
            // Send false on finish if we don't have enough votes
            resultPromise.succeed(false)
        }
        allRequests.cascadeFailure(to: resultPromise)
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
        heartbeatTask = eventLoop.scheduleRepeatedAsyncTask(initialDelay: TimeAmount.zero,
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
            return eventLoop.makeFailedFuture(AppendLogError.notALeaderTryToHeartbeat)
        }
        // Send heartbeat to all peers
        return EventLoopFuture.andAllComplete(peers.map({ peer -> EventLoopFuture<Bool> in
            return peer.sendHeartbeat(term: self.term)
        }), on: eventLoop)
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
