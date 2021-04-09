// SPDX-License-Identifier: MIT
// Copyright © 2021 makadaw


import SwiftRaft

actor Peer: SwiftRaft.Peer {

    let myself: Configuration.Peer
    let client: PeerClient

    init(myself: Configuration.Peer, client: PeerClient) {
        self.myself = myself
        self.client = client
    }

    func requestVote(_ request: RequestVote.Request) async throws -> RequestVote.Response {
        guard let response = try await client.send(request, dest: "\(myself.id)") as? RequestVote.Response else {
            fatalError("Wrong type of the response!")
        }
        return response
    }

    func sendHeartbeat<T>(_ request: AppendEntries.Request<T>) async throws -> AppendEntries.Response where T : LogData {
        guard let response = try await client.send(request, dest: "\(myself.id)") as? AppendEntries.Response else {
            fatalError("Wrong type of the response!")
        }
        return response
    }

}

extension RequestVote.VoteType {
    init?(from rawValue: String) {
        switch rawValue {
            case "vote":
                self = .vote
            case "pre_vote":
                self = .preVote
            default:
                return nil
        }
    }

    var toString: String {
        switch self {
            case .vote:
                return "vote"
            case .preVote:
                return "pre_vote"
        }
    }
}

extension RequestVote.Request: Message {
    public static var messageType: String = "vote_request"

    enum CodingKeys: String, CodingKey {
        // Request is coded into a JSON with already existed `type` field
        case type = "voteType"
        case termID = "termId"
        case candidateID = "candidateId"
        case lastLogIndex, lastLogTerm
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        guard let type = RequestVote.VoteType(from: try container.decode(String.self, forKey: .type)) else {
            throw DecodingError.dataCorruptedError(forKey: .type, in: container, debugDescription: "Not supported vote type")
        }
        self.init(type: type,
                  termID: try container.decode(Term.ID.self, forKey: .termID),
                  candidateID: try container.decode(NodeID.self, forKey: .candidateID),
                  lastLogIndex: try container.decode(UInt64.self, forKey: .lastLogIndex),
                  lastLogTerm: try container.decode(UInt64.self, forKey: .lastLogTerm))
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(self.type.toString, forKey: .type)
        try container.encode(termID, forKey: .termID)
        try container.encode(candidateID, forKey: .candidateID)
        try container.encode(lastLogIndex, forKey: .lastLogIndex)
        try container.encode(lastLogTerm, forKey: .lastLogTerm)
    }
}

extension RequestVote.Response: Message {
    public static var messageType: String = "vote_response"

    enum CodingKeys: String, CodingKey {
        // Request is coded into a JSON with already existed `type` field
        case type = "voteType"
        case termID = "termId"
        case voteGranted
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        guard let type = RequestVote.VoteType(from: try container.decode(String.self, forKey: .type)) else {
            throw DecodingError.dataCorruptedError(forKey: .type, in: container, debugDescription: "Not supported vote type")
        }
        self.init(type: type,
                  termID: try container.decode(Term.ID.self, forKey: .termID),
                  voteGranted: try container.decode(Bool.self, forKey: .voteGranted))
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(self.type.toString, forKey: .type)
        try container.encode(termID, forKey: .termID)
        try container.encode(voteGranted, forKey: .voteGranted)
    }
}

extension AppendEntries.Request: Message {
    public static var messageType: String { "append_entries_request" }

    enum CodingKeys: String, CodingKey {
        case termID = "termId"
        case leaderID = "leaderId"
        case prevLogIndex, prevLogTerm, leaderCommit
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        // TODO Support entries
        self.init(termID: try container.decode(Term.ID.self, forKey: .termID),
                  leaderID: try container.decode(NodeID.self, forKey: .leaderID),
                  prevLogIndex: try container.decode(UInt64.self, forKey: .prevLogIndex),
                  prevLogTerm: try container.decode(UInt64.self, forKey: .prevLogTerm),
                  leaderCommit: try container.decode(UInt64.self, forKey: .leaderCommit),
                  entries: [])
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(termID, forKey: .termID)
        try container.encode(leaderID, forKey: .leaderID)
        try container.encode(prevLogIndex, forKey: .prevLogIndex)
        try container.encode(prevLogTerm, forKey: .prevLogTerm)
        try container.encode(leaderCommit, forKey: .leaderCommit)
        // TODO Add entries
    }
}

extension AppendEntries.Response: Message {
    public static var messageType: String = "append_entries_response"

    enum CodingKeys: String, CodingKey {
        case termID = "termId"
        case success
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(termID: try container.decode(Term.ID.self, forKey: .termID),
                  success: try container.decode(Bool.self, forKey: .success))
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(termID, forKey: .termID)
        try container.encode(success, forKey: .success)
    }
}
