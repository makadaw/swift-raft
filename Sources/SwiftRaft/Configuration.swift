// SPDX-License-Identifier: MIT
// Copyright © 2021 makadaw


import enum Dispatch.DispatchTimeInterval
import SystemPackage
import Logging

public typealias NodeID = UInt64

public struct Configuration: ConcurrentValue {

    /// Current node configuration
    public var myself: Peer

    /// Raft protocol configuration
    public var `protocol`: Consensus = .init()

    /// Log configuration
    public var log: Log

    /// RPC call related configuration
    public var rpc: RPC = .init()

    /// Node logger
    public var logger: Logger

    public init(id: NodeID, host: String = "localhost", port: Int = 0) {
        self.init(myself: Peer(id: id, host: host, port: port))
    }

    public init(myself: Peer) {
        self.myself = myself
        self.log = Log(root: "")
        self.logger = Logger(label: "raft-\(myself.id)")
    }

}

public extension Configuration {
    struct Consensus: ConcurrentValue {

        /// Election timeout. Use as a min time interval.
        public var electionTimeout: DispatchTimeInterval = .milliseconds(5000) {
            willSet {
                precondition(heartbeatPeriod.nanoseconds < newValue.nanoseconds,
                             "We should send heartbeat more often then run election")
            }
        }

        /// A leader sends RPCs at least this often, even if there is no data to send
        public var heartbeatPeriod: DispatchTimeInterval = .milliseconds(500) {
            willSet {
                precondition(newValue.nanoseconds < electionTimeout.nanoseconds,
                             "We should send heartbeat more often then run election")
            }
        }

        /// Random election timeout interval. Should be used to schedule next election
        public var nextElectionTimeout: DispatchTimeInterval {
            .nanoseconds(Int(self.electionTimeout.nanoseconds
                                + Int64.random(in: 1000...self.electionTimeout.nanoseconds)))

        }

    }

    struct Peer: ConcurrentValue {

        /// Identifier of the peer
        /// Each peer id including self should be uniq
        public let id: NodeID

        /// Peer address
        public let host: String

        /// Peer port
        public let port: Int

        public init(id: NodeID, host: String, port: Int) {
            self.id = id
            self.host = host
            self.port = port
        }
    }

    struct Log: ConcurrentValue {

        /// Root folder for a log instance
        public var root: FilePath
    }

    struct RPC: ConcurrentValue {

        /// Timeout for RPC vote messages. Should be set according to cluster abilities and should be less then Raft timeouts
        public var voteTimeout: DispatchTimeInterval = .milliseconds(100)

        /// Timeout for RPC message messages. Should be set according to cluster abilities and should be less then Raft timeouts
        public var appendMessageTimeout: DispatchTimeInterval = .milliseconds(100)
    }

}

extension Configuration.Peer: Equatable {}
extension FilePath: UnsafeConcurrentValue {}
extension DispatchTimeInterval: UnsafeConcurrentValue {}
extension Logger: UnsafeConcurrentValue {}
