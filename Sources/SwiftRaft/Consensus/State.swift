// SPDX-License-Identifier: MIT
// Copyright © 2021 makadaw


/// Possible states of the Raft node. States represent a state machine and not all changes are legit
enum State: String, Sendable {
    case follower
    case preCandidate
    case candidate
    case leader
}

extension State {

    var isLeader: Bool {
        switch self {
            case .leader:
                return true
            default:
                return false
        }
    }

    func  isValidNext(state nextState: State) -> Bool {
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
