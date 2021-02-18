// SPDX-License-Identifier: MIT
// Copyright © 2021 makadaw


/// Node term description. Collect together a term id and vote of the current term
public struct Term {
    public typealias ID = UInt64

    enum Error: Swift.Error {
        case newTermLessThenCurrent(ID, ID)
    }

    /// Current node
    let myself: NodeID

    /// Latest term node has seen, increases monotonically
    public private(set) var id: ID

    /// `candidateId` that received vote in current term
    public private(set) var votedFor: NodeID?

    /// Current term leader
    public var leader: NodeID?

    public init(myself: NodeID, id: ID = 0) {
        self.init(myself: myself, id: id, votedFor: nil, leader: nil)
    }

    init(myself: NodeID, id: ID, votedFor: NodeID?, leader: NodeID?) {
        self.myself = myself
        self.id = id
        self.votedFor = votedFor
        self.leader = leader
    }

    /// Return a next term and vote for myself. In this case we lost a leader
    /// - Returns: returns a next term where node already voted for itself
    public func nextTerm() -> Term {
        Term(myself: myself, id: id + 1, votedFor: myself, leader: nil)
    }

    /// This method update term if new term is higher then current. This methods should be called if we get AppendMessage
    /// with higher term, this mean that current node is out of date
    /// - Parameters:
    ///   - newTerm: new term id
    ///   - from: node that send us a message with higher term
    /// - Throws: error if new term is less then current
    mutating public func tryToUpdateTerm(newTerm: ID, from: NodeID) throws {
        guard newTerm > id else {
            throw Error.newTermLessThenCurrent(newTerm, id)
        }
        updateTerm(newTerm: newTerm, from: from)
    }

    /// Accept or reject new term from a node. Use this method in vote phase
    /// - Parameters:
    ///   - term: next term to check
    ///   - from: node id that proposed it
    /// - Returns: true if node already voted for this term and candidate or accepted new term and vote for the candidate
    mutating public func canAcceptNewTerm(_ term: ID, from: NodeID) -> Bool {
        if id > term { // Current term is higher, we don't accpet elections from past
            return false
        } else if id == term && votedFor != from { // We already voted in this term for other candidate
            return false
        } else if id < term { // Current term is less then proposed, accept it and vote for a candidate
            updateTerm(newTerm: term, from: from)
            return true
        }
        return true
    }

    mutating private func updateTerm(newTerm: ID, from: NodeID? = nil) {
        id = newTerm
        votedFor = from
        leader = nil
    }
}

extension Term: CustomStringConvertible, Equatable {

    public var description: String {
        "\(id)"
    }

    static public func == (lhs: Term, rhs: Term) -> Bool {
        lhs.id == rhs.id
    }
}
