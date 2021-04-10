// SPDX-License-Identifier: MIT
// Copyright © 2021 makadaw


import RaftNIO
import SwiftRaft
import NIO
import Lifecycle
import Logging
import SystemPackage
import ArgumentParser
import enum Dispatch.DispatchTimeInterval

struct Start: ParsableCommand {
    @Argument(help: "list of peers in format `<id>:<host>:<port>`")
    var peers: [String] = []

    @Option(help: "number of local nodes to start, use if peers is not provided")
    var num: Int = 0

    @Option(help: "node id to run, skip if want to run all nodes", transform: { NodeID($0) ?? 0 })
    var runNode: NodeID?

    mutating func run() throws {
        let peers: [Configuration.Peer]
        if self.peers.isEmpty && num > 0 {
            peers = testNodes(num)
        } else if !self.peers.isEmpty && num == 0 {
            peers = parsePeers(self.peers)
        } else {
            preconditionFailure("Peers should be provided or num is set, but not both")
        }

        let tempDirectory = FilePath.temporaryDirectory.appending("File-Log")
        if !tempDirectory.isPathExist() {
            try tempDirectory.createDirectory()
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
                config.protocol.electionTimeout = .milliseconds(2000)
                config.log.root = tempDirectory.appending("node-\(node.id)")
                let bootstrap = GRPCBootstrap(group: group,
                                              config: config,
                                              peers: peers.filter({ $0.id != node.id }))

                lifecycle.register(
                    label: "raft-\(node.id)",
                    start: .sync {
                        try bootstrap.start()
                    },
                    shutdown: .sync {
                        try bootstrap.shutdown()?.wait()
                    })
            }

        try lifecycle.startAndWait()
    }

    func parsePeers(_ pattern: [String]) -> [Configuration.Peer] {
        pattern.compactMap { peer in
            let idHostPort = peer.split(separator: ":").map(String.init)
            guard idHostPort.count == 3, let id = NodeID(idHostPort[0]), let port = Int(idHostPort[2]) else {
                return nil
            }
            return Configuration.Peer(id: id, host: idHostPort[1], port: port)
        }
    }

    func testNodes(_ to: Int) -> [Configuration.Peer] {
        (1...to)
            .map { Configuration.Peer(id: NodeID($0), host: "localhost", port: 8890 + $0) }
    }
}

Start.main()
