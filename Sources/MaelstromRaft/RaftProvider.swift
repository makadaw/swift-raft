// SPDX-License-Identifier: MIT
// Copyright © 2021 makadaw


import NIO
import SwiftRaft
import RaftNIO
import Logging

public class RaftProvider: MessageProvider {

    var raft: Raft<MemoryLog<String>>?

    let logger: Logger

    public init(logger: Logger) {
        self.logger = logger
    }

    // Single node storage
    var storage: [Int: Int] = [:]

    public func onMessage(_ message: RPCPacket.Message, context: CallHandlerContext) -> EventLoopFuture<RPCPacket.Message> {
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

                self.raft = Raft(config: Configuration(id: intNodeID, host: "localhost", port: 9000 + Int(intNodeID)),
                                 peers: [],
                                 log: MemoryLog())
                return context.eventLoop.makeSucceededFuture(.initOk)

            case let .read(key: key):
                logger.trace("Key: \(key)")
                if let value = storage[key] {
                    return context.eventLoop.makeSucceededFuture(.readOk(value: value))
                }
                return context.eventLoop.makeFailedFuture(RPCPacket.Error.keyDoesNotExist)

            case let .write(key: key, value: value):
                logger.trace("Write \(value) for key \(key)")
                storage[key] = value
                return context.eventLoop.makeSucceededFuture(.writeOk)

            case let .cas(key: key, from: from, to: to):
                logger.trace("Write \(to) from \(from) key \(key)")
                if storage[key] == from {
                    storage[key] = to
                    return context.eventLoop.makeSucceededFuture(.casOk)
                }
                return context.eventLoop.makeFailedFuture(RPCPacket.Error.preconditionFailed)

            default:
                return context.eventLoop.makeFailedFuture(RPCPacket.Error.notSupported)
        }
    }
}
