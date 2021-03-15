// SPDX-License-Identifier: MIT
// Copyright © 2021 makadaw


import struct Dispatch.DispatchTime
import enum Dispatch.DispatchTimeInterval
import Logging

public actor Raft<ApplicationLog: Log> {
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

    /// Current state. Should not be changed directly, use `_tryMoveTo(nextState:)` method
    var state: State

    /// Application log
    var log: ApplicationLog

    public init(config: Configuration, peers: [Peer], log: ApplicationLog) {
        self.config = config
        self.peers = peers
        self.log = log

        self.state = .follower

        self.term = Term(myself: config.myself.id,
                         id: log.metadata.termID ?? 0, // Start with a default term id 0
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

// MARK: Election
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
    func startVote(type: RequestVote.VoteType) async -> Bool {
        let term = self.term.nextTerm()
        if case .vote = type {
            // Set new term if this is a real vote
            self.term = term
        }
        // How much votes we need to win
        let tallyVotes = self.peers.quorumSize
        let request = RequestVote.Request(type: type,
                                          termID: term.id,
                                          candidateID: myself,
                                          lastLogIndex: 0,
                                          lastLogTerm: 0)
        // Get list of active peers
        let peers = self.peers

        // TODO Handle errors correctly
        // swiftlint:disable:next force_try
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

    /// Process vote and pre vote requests. Should be invoked by a host
    ///
    /// 1. Reply false if term `<` currentTerm (§5.1)
    /// 2. If votedFor is null or candidateId, and candidate’s log is at least as up-to-date as receiver’s log, grant vote (§5.2, §5.4)
    func onVoteRequest(_ request: RequestVote.Request) async -> RequestVote.Response {
        // TODO: On vote response we also should reset election timer
        let granted: Bool = {
            let lastLogTerm = self.log.metadata.termID ?? 0
            // If the caller has a less complete log, we can't give it our vote.
            let isLogOk = request.lastLogTerm > lastLogTerm
                        || (request.lastLogTerm == lastLogTerm
                            && request.lastLogIndex >= self.log.logLastIndex)
            if request.type == .preVote {
                return isLogOk && request.termID > term.id
            } else {
                return isLogOk && term.canAcceptNewTerm(request.termID, from: request.candidateID)
            }
        }()
        logger.debug("Vote response \(granted)", metadata: [
            "vote/self": "\(myself)",
            "vote/candidate": "\(request.candidateID)",
            "vote/granted": "\(granted)"
        ])
        return .init(type: request.type, termID: self.term.id, voteGranted: granted)
    }

}

/// Vote request message. Use for both pre and real vote
public struct RequestVote {

    public enum VoteType: ConcurrentValue {
        case preVote
        case vote
    }

    public struct Request: ConcurrentValue {
        /// Vote type `vote` or `PreVote`
        let type: VoteType

        /// Candidate’s term
        let termID: Term.ID

        /// Candidate requesting vote
        let candidateID: NodeID

        /// Index of candidate’s last log entry
        let lastLogIndex: UInt64

        /// Term of candidate’s last log entry
        let lastLogTerm: UInt64

        public init(type: VoteType, termID: Term.ID, candidateID: NodeID, lastLogIndex: UInt64, lastLogTerm: UInt64) {
            self.type = type
            self.termID = termID
            self.candidateID = candidateID
            self.lastLogIndex = lastLogIndex
            self.lastLogTerm = lastLogTerm
        }

    }

    public struct Response: ConcurrentValue {
        /// Vote type `vote` or `PreVote`, should be the the same as in request
        let type: VoteType

        /// Current term of the node, for candidate to update itself
        let termID: Term.ID

        /// True means candidate received vote
        let voteGranted: Bool

        public init(type: VoteType, termID: Term.ID, voteGranted: Bool) {
            self.type = type
            self.termID = termID
            self.voteGranted = voteGranted
        }
    }
}

// MARK: Entries
extension Raft {

    public enum EntriesCommand: ConcurrentValue, Equatable {
        /// For non leader state reset an election timer
        case resetElectionTimer
    }

    public struct AppendResponse: ConcurrentValue {
        let response: AppendEntries.Response

        let commands: [EntriesCommand]

        init(_ response: AppendEntries.Response, commands: [EntriesCommand]) {
            self.response = response
            self.commands = commands
        }
    }

    /// Process Entry append
    func onAppendEntries<T>(_ request: AppendEntries.Request<T>) async -> AppendResponse where T == ApplicationLog.Data {
        // 1. Reply false if term `<` currentTerm (§5.1)
        guard request.termID <= self.term.id else {
            return rejectAppendEntry(leader: request.leaderID, higherTermID: request.termID)
        }
        // Update leader id
        if self.term.leaderID == nil {
            self.term.leaderID = request.leaderID
        }
        logger.debug("Receive message", metadata: [
            "message/term": "\(request.termID)",
            "message/leader": "\(request.leaderID)"
        ])

        var commands = [EntriesCommand]()
        let isIAmAFollower = _tryMoveTo(nextState: .follower)
        let isLogOk = true
        // 2. Reply false if log doesn’t contain an entry at prevLogIndex whose term matches prevLogTerm (§5.3)
        // 3. If an existing entry conflicts with a new one (same index but different terms), delete the existing entry and all that follow it (§5.3)
        // 4. Append any new entries not already in the log
        // 5. If leaderCommit > commitIndex, set commitIndex = min(leaderCommit, index of last new entry)

        // At the end node should reset an election timer if not a leader. This is a very important step
        if !state.isLeader {
            // Reset election timer if node is not a leader
            commands.append(.resetElectionTimer)
        }
        return AppendResponse(.init(termID: term.id, success: isIAmAFollower && isLogOk), commands: commands)
    }

    private func rejectAppendEntry(leader: NodeID, higherTermID termID: Term.ID) -> AppendResponse {
        do {
            try self.term.tryToUpdateTerm(newTerm: termID, from: leader)
            if !_tryMoveTo(nextState: .follower) {
                logger.debug("Got term greater than current and failed to move to the follower state",
                             metadata: ["node/state": "\(self.state)",
                                        "node/term": "\(self.term)",
                                        "message/term": "\(termID)"])
            }
        } catch let error {
            logger.error("Error on step down into term \(termID)",
                         metadata: ["node/state": "\(self.state)",
                                    "node/term": "\(self.term)",
                                    "message/term": "\(termID)",
                                    "error": "\(error)"])
        }
        // Response with reject and reset election timer, as we not a leader anymore
        return AppendResponse(.init(termID: term.id, success: false), commands: [.resetElectionTimer])
    }
}

public struct AppendEntries {

    public struct Request<T: LogData>: ConcurrentValue {
        public typealias Element = LogElement<T>

        /// Current leader term id. Followers use them to validate correctness
        public let termID: Term.ID

        /// Leader id in the cluster
        public let leaderID: NodeID

        /// Index of log entry immediately preceding new ones
        public let prevLogIndex: UInt64

        /// Term id of prevLogIndex entry
        public let prevLogTerm: UInt64

        /// Leader’s commit index
        public let leaderCommit: UInt64

        // TODO Make sure compiler can check that generic argument is `ConcurrentValue`
        /// Log entries to store (empty for heartbeat; may send more than one for efficiency)
//        public let entries: [Element]

        public init(termID: Term.ID,
                    leaderID: NodeID,
                    prevLogIndex: UInt64,
                    prevLogTerm: UInt64,
                    leaderCommit: UInt64,
                    entries: [Element]) {
            self.termID = termID
            self.leaderID = leaderID
            self.prevLogIndex = prevLogIndex
            self.prevLogTerm = prevLogTerm
            self.leaderCommit = leaderCommit
//            self.entries = entries
        }
    }

    public struct Response: ConcurrentValue {
        /// Current node term, for leader to update itself
        public let termID: Term.ID

        /// True if a follower accepted the message
        public let success: Bool

        public init(termID: Term.ID, success: Bool) {
            self.termID = termID
            self.success = success
        }
    }
}
