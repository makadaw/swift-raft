// SPDX-License-Identifier: MIT
// Copyright © 2021 makadaw


import SwiftRaft
import NIO
import RaftNIO
import Logging

/// Key value node
final public actor KvNode: MessageProvider {

    private(set) var configuration: Configuration
    var raft: Raft<MemoryLog<String>>?

    private var logger: Logger {
        configuration.logger
    }

    public init(configuration: Configuration) {
        self.configuration = configuration
        self.stateMachine = KvStateMachine()
    }

    var stateMachine: KvStateMachine

    public func onMessage(_ message: RPCPacket.Message) async throws -> RPCPacket.Message {
        switch message {
            case let .`init`(nodeId, nodeIds):
                // Start a raft service
                guard let intNodeID = NodeID(nodeId) else {
                    fatalError("Can't cast node id to Int")
                }
                let peers = nodeIds.filter { $0 != nodeId }.compactMap { NodeID($0) }
                guard peers.count == nodeIds.count - 1 else {
                    fatalError("Can't cast node ids to Int")
                }
                // Update configuration for self node based on init message
                configuration.myself = .init(id: intNodeID, host: "localhost", port: 9000 + Int(intNodeID))
                self.raft = Raft(config: configuration,
                                 peers: [],
                                 log: MemoryLog())
                return .initOk

            case let .read(key: key):
                logger.trace("Key: \(key)")
                return try await read(key: key)

            case let .write(key: key, value: value):
                logger.trace("Write \(value) for key \(key)")
                return try await write(key: key, value: value)

            case let .cas(key: key, from: from, to: to):
                logger.trace("Write \(to) from \(from) key \(key)")
                return try await cas(key: key, from: from, to: to)

            default:
                throw RPCPacket.Error.notSupported
        }
    }

    private func read(key: Int) async throws -> RPCPacket.Message {
        do {
            return .readOk(value: try await self.stateMachine.query(key))
        } catch KvStateMachine.Error.keyDoesNotExist {
            throw RPCPacket.Error.keyDoesNotExist
        } catch {
            throw RPCPacket.Error.crash
        }
    }

    private func write(key: Int, value: Int) async throws -> RPCPacket.Message {
        do {
            try await stateMachine.apply(entry: .init(key: key, value: value))
            return .writeOk
        } catch {
            throw RPCPacket.Error.crash
        }
    }


    private func cas(key: Int, from: Int, to: Int) async throws -> RPCPacket.Message {
        do {
            let current = try? await stateMachine.query(key)
            if from == current {
                try await stateMachine.apply(entry: .init(key: key, value: to))
            } else {
                throw RPCPacket.Error.preconditionFailed
            }
            return .casOk
        } catch {
            if error is RPCPacket.Error {
                throw error
            }
            throw RPCPacket.Error.crash
        }
    }
}
