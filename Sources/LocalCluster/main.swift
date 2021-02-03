// SPDX-License-Identifier: MIT
// Copyright © 2021 makadaw

import Raft
import NIO
import Lifecycle
import Logging
import ArgumentParser

struct Start: ParsableCommand {
    @Argument(help: "list of peers in format `<id>:<host>:<port>`")
    var peers: [String] = []

    @Option(help: "number of local nodes to start, use if peers is not provided")
    var num: Int = 0

    @Option(help: "node id to run, skip if want to run all nodes", transform: { NodeId($0) ?? 0 })
    var runNode: NodeId?

    mutating func run() throws {
        let peers: [PeerConfiguration]
        if self.peers.isEmpty && num > 0 {
            peers = testNodes(num)
        } else if !self.peers.isEmpty && num == 0 {
            peers = parsePeers(self.peers)
        } else {
            preconditionFailure("Peers should be provided or num is set, but not both")
        }

        let lifecycle = ServiceLifecycle()
        let group = MultiThreadedEventLoopGroup(numberOfThreads: System.coreCount)
        lifecycle.register(label: "local.group",
                           start: .none,
                           shutdown: .sync { try group.syncShutdownGracefully() })

        peers
            .filter({ config in
                self.runNode == nil || config.id == self.runNode
            })
            .forEach { node in
                var config = Configuration(id: node.id, port: node.port)
                config.logger.logLevel = .debug
                config.electionTimeout = .milliseconds(1000)
                let raftNode = Raft(config: config,
                                    peers: peers.filter({ $0.id != node.id }),
                                    group: group)

                lifecycle.register(
                    label: "raft-\(node.id)",
                    start: .sync { raftNode.start() },
                    shutdown: .sync {
                        try raftNode.shutdown()?.wait()
//                        try group.syncShutdownGracefully()
                    })
            }

        try lifecycle.startAndWait()
    }

    func parsePeers(_ pattern: [String]) -> [PeerConfiguration] {
        pattern.compactMap { peer in
            let idHostPort = peer.split(separator: ":").map(String.init)
            guard idHostPort.count == 3, let id = NodeId(idHostPort[0]), let port = Int(idHostPort[2]) else {
                return nil
            }
            return PeerConfiguration(id: id, host: idHostPort[1], port: port)
        }
    }

    func testNodes(_ to: Int) -> [PeerConfiguration] {
        (1...to)
            .map { PeerConfiguration(id: NodeId($0), host: "localhost", port: 8890 + $0) }
    }
}

Start.main()
