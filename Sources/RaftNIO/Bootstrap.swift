// SPDX-License-Identifier: MIT
// Copyright © 2021 makadaw


import SwiftRaft
import GRPC
import NIO
import Logging
import enum Dispatch.DispatchTimeInterval

final public class RaftNIOBootstrap {

    let group: EventLoopGroup
    let config: Configuration
    let peers: [Configuration.Peer]
    private var server: Server?

    var logger: Logger {
        config.logger
    }

    public init(group: EventLoopGroup, config: Configuration, peers: [Configuration.Peer]) {
        self.group = group
        self.config = config
        self.peers = peers
    }

    public func start() throws {

        let node = Node(group: group,
                               configuration: config,
                               log: MemoryLog<String>())

        let server = Server.insecure(group: group)
            .withServiceProviders([GRPCNodeWrapper(node: node)])
            .bind(host: config.myself.host, port: config.myself.port)

        let load = server.map { (server: Server) -> SocketAddress? in
            self.server = server
            return server.channel.localAddress
        }
        load.whenFailure { error in
            self.logger.error("\(error)")
        }
        load.whenSuccess { address in
            self.logger.debug("Server started on port \(address!.port!)")
            let peers = self.peers.map({ GRPCPeer(myself: self.config.myself.id, config: $0, rpcConfig: self.config.rpc, group: self.group) })
            Task.runDetached {
                await node.startNode(peers: peers)
            }
        }
    }

    public func shutdown() -> EventLoopFuture<Void>? {
        server?.initiateGracefulShutdown()
    }
}
