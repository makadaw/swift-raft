// SPDX-License-Identifier: MIT
// Copyright © 2021 makadaw


import struct Dispatch.DispatchTime
import enum Dispatch.DispatchTimeInterval
import Logging

actor public class Consensus {
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

    var state: State

    init(config: Configuration, peers: [Peer]) {
        self.config = config
        self.peers = peers

        self.term = Term(myself: config.myself.id)
        self.state = .follower
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
extension Consensus {

    /// Commands related to changes in election process
    public enum ElectionCommand {
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
                        return true
                    }
                }
                return false
            } catch {
                // If got any error we lost an election
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
            if request.type == .preVote {
                return request.term > term.id
            } else {
                return term.canAcceptNewTerm(request.term, from: request.candidate)
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
extension Consensus {
    /// Process Entry append
    ///
    /// 1. Reply false if term `<` currentTerm (§5.1)
    /// 2. Reply false if log doesn’t contain an entry at prevLogIndex whose term matches prevLogTerm (§5.3)
    /// 3. If an existing entry conflicts with a new one (same index but different terms), delete the existing entry and all that follow it (§5.3)
    /// 4. Append any new entries not already in the log
    /// 5. If leaderCommit > commitIndex, set commitIndex = min(leaderCommit, index of last new entry)
    func onAppendEntries() async -> Void {
        // TODO
    }
}
