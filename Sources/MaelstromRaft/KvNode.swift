// SPDX-License-Identifier: MIT
// Copyright © 2021 makadaw


import SwiftRaft
import NIO
import RaftNIO
import Logging
import enum Dispatch.DispatchTimeInterval


public actor BootstrapNode: MessageProvider {

    let group: EventLoopGroup
    var configuration: Configuration

    var node: KvNode<MemoryLog<String>>?
    let peerClient: PeerClient
    var logger: Logger {
        configuration.logger
    }

    public init(group: EventLoopGroup, client: PeerClient, configuration: Configuration) {
        self.group = group
        self.peerClient = client
        self.configuration = configuration
    }

    public func onMessage(_ message: Message) async throws -> Message {
        switch message {
            case let onInit as Maelstrom.Init:
                guard let intNodeID = NodeID(onInit.nodeID) else {
                    fatalError("Can't cast node id to Int")
                }
                let peers = onInit.nodeIDs.filter { $0 != onInit.nodeID }.compactMap { NodeID($0) }
                guard peers.count == onInit.nodeIDs.count - 1 else {
                    fatalError("Can't cast node ids to Int")
                }
                configuration.myself = .init(id: intNodeID, host: "localhost", port: 9000 + Int(intNodeID))
                let node = KvNode(group: group, configuration: configuration, log: MemoryLog<String>())
                self.node = node
                await node.startNode(peers: peers
                                        .map({ Configuration.Peer(id: $0, host: "localhost", port: 0) })
                                        .map({ Peer(myself: $0, client: peerClient) }))
                return Maelstrom.InitOk()

            default:
                guard let node = self.node else {
                    logger.error("Node was not initialised")
                    return Maelstrom.Error.crash
                }
                return try await node.onMessage(message)
        }
    }
}

actor KvNode<ApplicationLog>: RaftNIO.Node<ApplicationLog> where ApplicationLog: Log {
    var storage: [Int: Int] = [:]
}

extension KvNode: MessageProvider {
    func onMessage(_ message: Message) async throws -> Message {
        switch message {
            case let read as Maelstrom.Read:
                logger.trace("Key: \(read.key)")
                if let value = storage[read.key] {
                    return Maelstrom.ReadOk(value: value)
                }
                throw Maelstrom.Error.keyDoesNotExist

            case let write as Maelstrom.Write:
                logger.trace("Write \(write.value) for key \(write.key)")
                storage[write.key] = write.value
                return Maelstrom.WriteOk()

            case let cas as Maelstrom.Cas:
                logger.trace("Write \(cas.to) from \(cas.from) key \(cas.key)")
                if storage[cas.key] == cas.from {
                    storage[cas.key] = cas.to
                    return Maelstrom.CasOk()
                }
                throw Maelstrom.Error.preconditionFailed

            default:
                throw Maelstrom.Error.notSupported
        }
    }
}

public protocol PeerClient: UnsafeConcurrentValue {
    func send(_ message: Message, dest: String) async throws -> Message
}

extension MaelstromRPC: PeerClient {}
