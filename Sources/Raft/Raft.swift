// SPDX-License-Identifier: MIT
// Copyright © 2021 makadaw

import GRPC
import NIO
import Logging
import Foundation

/// Raft node public interface
final public class Raft {

    private let config: Configuration
    private var peers: [PeerConfiguration]
    private let group: EventLoopGroup
    private var server: Server?
    private var consensus: ConsensusService<FileLog<String>>!

    private var logger: Logger {
        self.config.logger
    }

    public init(config: Configuration, peers: [PeerConfiguration], group: EventLoopGroup) {
        self.config = config
        self.peers = peers
        self.group = group
    }

    public func start() {
        do {
            try config.validate()
        } catch {
            // TODO better error handling
            logger.error("Configuration error \(error)")
            return
        }
        self.consensus = ConsensusService(
            group: group,
            config: config,
            peers: peers.map({ Peer(myself: config.server.id, config: $0, rpcConfig: config.rpc, group: group) }),
            log: FileLog<String>(root: config.logRoot),
            logger: logger)

        let server = Server.insecure(group: group)
            .withServiceProviders([consensus])
            .bind(host: config.server.host, port: config.server.port)

        let load = server.map { (server: Server) -> SocketAddress? in
            self.server = server
            return server.channel.localAddress
        }
        load.whenFailure { error in
            self.logger.error("\(error)")
        }
        load.whenSuccess { address in
            self.logger.debug("Server started on port \(address!.port!)")
            self.consensus.onStart()
        }
    }

    public func shutdown() -> EventLoopFuture<Void>? {
        server?.initiateGracefulShutdown()
    }
}

// Use string as dummy application data
extension String: LogData {

    init?(data: Data) {
        self.init(data: data, encoding: .utf8)
    }

    var size: Int {
        self.data(using: .utf8)?.count ?? 0
    }
}
