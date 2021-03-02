// SPDX-License-Identifier: MIT
// Copyright © 2021 makadaw


import struct Dispatch.DispatchTime
import enum Dispatch.DispatchTimeInterval
import Logging

public actor Raft {
    let config: Configuration
    var logger: Logger {
        config.logger
    }

    /// Current node id
    var myself: NodeID {
        config.myself.id
    }

    var peers: [Peer]

    /// Latest term server has seen, increases monotonically
    var term: Term

    /// Current state. Should not changed directly, use `_tryMoveTo(nextState:)` method
    var state: State

    /// Application log
    var log: BaseLog

    init<ApplicationLog>(config: Configuration, peers: [Peer], log: ApplicationLog) where ApplicationLog: Log {
        self.config = config
        self.peers = peers
        self.log = AnyLog(log: log)

        self.state = .follower

        self.term = Term(myself: config.myself.id,
                         id: log.metadata.termId ?? 0, // Start with a default term id 0
                         votedFor: log.metadata.voteFor)
        self.logger.debug("The log contains indexes \(log.logStartIndex) through \(log.logLastIndex)")
    }

    /// States switch machine
    private func _tryMoveTo(nextState: State) -> Bool {
        if state.isValidNext(state: nextState) {
            self.state = nextState
            return true
        }
        return false
    }
}

//MARK: Election
extension Raft {

    /// Commands related to changes in election process
    public enum ElectionCommand: Equatable {
        /// Stop election timer, this means that node not in a follower state
        case stopTimer

        /// Schedule next round of election timer
        case scheduleNextTimer(delay: DispatchTimeInterval)

        /// Node is ready to start pre vote
        case startPreVote

        /// Node is ready to start election
        case startVote

        /// Election won, time to become a leader for the cluster
        case startToBeALeader
    }

    /// Election timer is out. Plan next steps
    public func onElectionTimeout() async -> ElectionCommand {
        if case .leader = state {
            return .stopTimer // We are the leader, stop the election timer
        }
        logger.debug("Node \(myself) would start an election campaign")
        if _tryMoveTo(nextState: .preCandidate) {
            return .startPreVote
        }
        return .scheduleNextTimer(delay: config.protocol.nextElectionTimeout)
    }

    public enum VoteType {
        case preVote
        case vote
    }

    /// Try to run a pre vote campaign
    public func startPreVote() async -> ElectionCommand {
        let term = self.term
        let voteResult = await startVote(type: .preVote)
        if voteResult {
            logger.debug("Won preVote election, starting vote")
            return .startVote
        }
        logger.warning("Lost preVote for \(term)")
        return .scheduleNextTimer(delay: config.protocol.nextElectionTimeout)
    }

    /// Try to run a election campaign
    public func startVote() async -> ElectionCommand {
        let voteResult = await startVote(type: .preVote)
        logger.debug("Finish campign", metadata: [
            "vote/result": "\(voteResult)",
            "vote/term": "\(self.term)"
        ])
        if voteResult && _tryMoveTo(nextState: .leader) {
            return .startToBeALeader
        }
        self.logger.debug("Failed to become a leader for \(self.term) term")
        return .scheduleNextTimer(delay: config.protocol.nextElectionTimeout)
    }

    /// Node is ready to start new vote
    func startVote(type: VoteType) async -> Bool {
        let term = self.term.nextTerm()
        if case .vote = type {
            // Set new term if this is a real vote
            self.term = term
        }
        // How much votes we need to win
        let tallyVotes = self.peers.quorumSize
        let request = RequestVote.Request(type: type,
                                          term: term.id,
                                          candidate: myself,
                                          lastLogIndex: 0,
                                          lastLogTerm: 0)
        // Get list of active peers
        let peers = self.peers

        // TODO Handle errors correctly
        let result = try! await Task.withGroup(resultType: Bool.self, returning: Bool.self) { group in

            // We should stop election at the moment when we got quorum
            for peer in peers {
                // We should stop election at the moment when we got quorum
                await group.add(operation: {
                    await peer.requestVote(request).voteGranted
                })
            }

            do {
                var grantedVotes: UInt = 1 // We already votes for ourself
                while let result = try await group.next() {
                    grantedVotes += result ? 1 : 0
                    if grantedVotes >= tallyVotes {
                        group.cancelAll()
                        return true
                    }
                }
                return false
            } catch {
                // If got any error we lost an election
                group.cancelAll()
                return false
            }
        }
        return result
    }

    /// Vote request message. Use for both pre and real vote
    public struct RequestVote {

        public struct Request {
            /// Vote type `vote` or `PreVote`
            let type: VoteType

            /// Candidate’s term
            let term: Term.ID

            /// Candidate requesting vote
            let candidate: NodeID

            /// Index of candidate’s last log entry
            let lastLogIndex: UInt64

            /// Term of candidate’s last log entry
            let lastLogTerm: UInt64

        }

        public struct Response {
            /// Vote type `vote` or `PreVote`, should be the the same as in request
            let type: VoteType

            /// Current term of the node, for candidate to update itself
            let term: Term

            /// True means candidate received vote
            let voteGranted: Bool
        }
    }

    /// Process vote and pre vote requests. Should be invoked by a host
    ///
    /// 1. Reply false if term `<` currentTerm (§5.1)
    /// 2. If votedFor is null or candidateId, and candidate’s log is at least as up-to-date as receiver’s log, grant vote (§5.2, §5.4)
    func onVoteRequest(_ request: RequestVote.Request) async -> RequestVote.Response {
        // TODO: On vote response we also should reset election timer
        let granted: Bool = {
            let lastLogTerm = self.log.metadata.termId ?? 0
            // If the caller has a less complete log, we can't give it our vote.
            let isLogOk = request.lastLogTerm > lastLogTerm
                        || (request.lastLogTerm == lastLogTerm
                            && request.lastLogIndex >= self.log.logLastIndex)
            if request.type == .preVote {
                return isLogOk && request.term > term.id
            } else {
                return isLogOk && term.canAcceptNewTerm(request.term, from: request.candidate)
            }
        }()
        logger.debug("Vote response \(granted)", metadata: [
            "vote/self": "\(myself)",
            "vote/candidate": "\(request.candidate)",
            "vote/granted": "\(granted)"
        ])
        return .init(type: request.type, term: self.term, voteGranted: granted)
    }

}

// MARK: Entries
extension Raft {

    public struct AppendEntries {

        public struct Request<T: LogData> {
            /// Current leader term id. Followers use them to validate correctness
            public let termId: Term.ID

            /// Leader id in the cluster
            public let leaderId: NodeID

            /// Index of log entry immediately preceding new ones
            public let prevLogIndex: UInt64

            /// Term id of prevLogIndex entry
            public let prevLogTerm: UInt64

            /// Leader’s commit index
            public let leaderCommit: UInt64

            /// Log entries to store (empty for heartbeat; may send more than one for efficiency)
            public let entries: [LogElement<T>]

            public init(termId: Term.ID,
                        leaderId: NodeID,
                        prevLogIndex: UInt64,
                        prevLogTerm: UInt64,
                        leaderCommit: UInt64,
                        entries: [LogElement<T>]) {
                self.termId = termId
                self.leaderId = leaderId
                self.prevLogIndex = prevLogIndex
                self.prevLogTerm = prevLogTerm
                self.leaderCommit = leaderCommit
                self.entries = entries
            }
        }

        public struct Response {
            /// Current node term, for leader to update itself
            public let termId: Term.ID

            /// True if a follower accepted the message
            public let success: Bool

            public init(termId: Term.ID, success: Bool) {
                self.termId = termId
                self.success = success
            }
        }
    }

    public enum EntriesCommand: Equatable {
        /// For non leader state reset an election timer
        case resetElectionTimer
    }

    /// Process Entry append
    ///
    /// 1. Reply false if term `<` currentTerm (§5.1)
    /// 2. Reply false if log doesn’t contain an entry at prevLogIndex whose term matches prevLogTerm (§5.3)
    /// 3. If an existing entry conflicts with a new one (same index but different terms), delete the existing entry and all that follow it (§5.3)
    /// 4. Append any new entries not already in the log
    /// 5. If leaderCommit > commitIndex, set commitIndex = min(leaderCommit, index of last new entry)
    /// Return a pair of side-effects and a response
    func onAppendEntries<T: LogData>(_ request: AppendEntries.Request<T>) async -> ([EntriesCommand], AppendEntries.Response) {
        var commands = Array<EntriesCommand>()
        if request.termId > self.term.id {
            // got a message with higher term, step down to a follower
            do {
                try term.tryToUpdateTerm(newTerm: request.termId, from: request.leaderId)
                if !_tryMoveTo(nextState: .follower) {
                    logger.debug("Got term greater than current and failed to move to the follower state")
                }
                // Reset election timer, as we not a leader anymore
                commands.append(.resetElectionTimer)
            } catch let error {
                logger.error("Error on stepdown into term \(request.termId). \(error)",
                             metadata: ["message/term": "\(term)"])
            }
            return (commands, AppendEntries.Response(termId: term.id, success: false))
        }
        if self.term.leader == nil {
            self.term.leader = request.leaderId
        }

        logger.debug("Receive message", metadata: [
            "message/term": "\(term.id)",
            "message/leader": "\(term.leader ?? 0)"
        ])

        let isIAmAFollower = _tryMoveTo(nextState: .follower)
        let isLogOk = true
        for _ in request.entries {
            // TODO: Check log entries terms and indices, add missing messages to the log
        }

        // At the end node should reset an election timer if not a leader. This is a very important step
        if !state.isLeader {
            // Reset election timer node is not a leader
            commands.append(.resetElectionTimer)
        }
        return (commands, AppendEntries.Response(termId: term.id, success: isIAmAFollower && isLogOk))
    }
}
