// SPDX-License-Identifier: MIT
// Copyright © 2021 makadaw

import Logging
import NIO

public typealias NodeId = UInt64

/// Cluster peers configuration
public struct PeerConfiguration {
    /// Identifier of the node
    /// Each peer id including self should be uniq
    public let id: NodeId

    /// Node address
    public let host: String

    /// Node port
    public let port: Int

    public init(id: NodeId, host: String, port: Int) {
        self.id = id
        self.host = host
        self.port = port
    }
}

/// Node configuration
public struct Configuration {

    /// Current node server configuration
    public var server: PeerConfiguration

    /// Election timeout in milliseconds
    public var electionTimeout: TimeAmount = .milliseconds(5000)

    /// A leader sends RPCs at least this often, even if there is no data to send
    public var heartbeatPeriod: TimeAmount = .milliseconds(500)

    /// RPC call related configuration
    public var rpc: RPCConfiguration = .init()

    /// Node logger
    public var logger: Logger

    public init(server: PeerConfiguration) {
        self.server = server
        self.logger = Logger(label: "raft-\(server.id)")
    }

    public init(id: NodeId, host: String = "localhost", port: Int = 0) {
        self.init(server: PeerConfiguration(id: id, host: host, port: port))
    }
}

public struct RPCConfiguration {

    /// Timeout for RPC vote messages. Should be set according to cluster abilities and should be less then Raft timeouts
    public var voteTimeout: TimeAmount = .milliseconds(100)

    /// Timeout for RPC message messages. Should be set according to cluster abilities and should be less then Raft timeouts
    public var appendMessageTimeout: TimeAmount = .milliseconds(100)
}

extension Configuration {

    enum Error: Swift.Error {
        case heartbeatTimeShouldBeLessThanElection
    }

    /// Validate configuration
    /// - Throws: configuration error
    func validate() throws {
        if heartbeatPeriod > electionTimeout {
            throw Error.heartbeatTimeShouldBeLessThanElection
        }
    }
}

extension PeerConfiguration: Equatable {}
