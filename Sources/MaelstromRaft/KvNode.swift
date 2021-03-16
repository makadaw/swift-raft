// SPDX-License-Identifier: MIT
// Copyright © 2021 makadaw


import SwiftRaft
import NIO
import RaftNIO
import Logging

// swiftlint:disable:next orphaned_doc_comment
/// Key value based node
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

    public func onMessage(_ message: Message) async throws -> Message {
        switch message {
            case let onInit as Maelstrom.Init:
                // Start a raft service
                guard let intNodeID = NodeID(onInit.nodeID) else {
                    fatalError("Can't cast node id to Int")
                }
                let peers = onInit.nodeIDs.filter { $0 != onInit.nodeID }.compactMap { NodeID($0) }
                guard peers.count == onInit.nodeIDs.count - 1 else {
                    fatalError("Can't cast node ids to Int")
                }
                // Update configuration for self node based on init message
                configuration.myself = .init(id: intNodeID, host: "localhost", port: 9000 + Int(intNodeID))
                self.raft = Raft(config: configuration,
                                 peers: [],
                                 log: MemoryLog())
                return Maelstrom.InitOk()

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
