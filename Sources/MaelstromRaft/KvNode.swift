// SPDX-License-Identifier: MIT
// Copyright © 2021 makadaw


import SwiftRaft
import NIO
import RaftNIO
import Logging

final public actor KvNode: MessageProvider {

    var configuration: Configuration
    var raft: Raft<MemoryLog<String>>?

    private var logger: Logger {
        configuration.logger
    }

    public init(configuration: Configuration) {
        self.configuration = configuration
    }

    var storage: [Int: Int] = [:]

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
                if let value = storage[key] {
                    return .readOk(value: value)
                }
                throw RPCPacket.Error.keyDoesNotExist

            case let .write(key: key, value: value):
                logger.trace("Write \(value) for key \(key)")
                storage[key] = value
                return .writeOk

            case let .cas(key: key, from: from, to: to):
                logger.trace("Write \(to) from \(from) key \(key)")
                if storage[key] == from {
                    storage[key] = to
                    return .casOk
                }
                throw RPCPacket.Error.preconditionFailed


            default:
                throw RPCPacket.Error.notSupported
        }
    }

}
