// SPDX-License-Identifier: MIT
// Copyright © 2021 makadaw


import Foundation
import Logging
import NIO
import NIOConcurrencyHelpers
import NIOFoundationCompat


/// Process messages from the network
public protocol MessageProvider: Actor {
    func onMessage(_ message: Message) async throws -> Message
}

/// Message handler is responsible for connecting NIO runtime with actors handlers.
class MessageHandler: ChannelDuplexHandler, UnsafeConcurrentValue {
    typealias InboundIn = RPCPacket
    typealias OutboundIn = RPCPacket
    typealias OutboundOut = RPCPacket

    let logger: Logger
    let messageProvider: MessageProvider
    let counter: NIOAtomic<Int> = NIOAtomic.makeAtomic(value: 1)
    // RPC node id
    var nodeID: String?

    init(messageProvider: MessageProvider, logger: Logger) {
        self.messageProvider = messageProvider
        self.logger = logger
    }

    func channelRead(context: ChannelHandlerContext, data: NIOAny) {
        // Maelstrom request
        let request = unwrapInboundIn(data)

        logger.debug("Get RPC request \(request)")
        if nodeID == nil, request.isInit {
            self.nodeID = request.initNodeID
        }

        // Run a coroutine to get a response and write into the context
        Task.runDetached {
            let response: RPCPacket
            do {
                let message = try await self.messageProvider.onMessage(request.body)
                guard let nodeID = self.nodeID else {
                    preconditionFailure("Didn't get init message")
                }
                response = RPCPacket(src: nodeID,
                                     dest: request.src,
                                     id: request.id,
                                     body: message,
                                     msgID: self.counter.next(),
                                     inReplyTo: request.msgID)
            } catch {
                self.logger.error("\(error)")
                let finalError: Maelstrom.Error = error as? Maelstrom.Error ?? .undefined
                response = RPCPacket(src: self.nodeID ?? request.dest,
                                     dest: request.src,
                                     id: request.id,
                                     body: finalError,
                                     msgID: self.counter.next(),
                                     inReplyTo: request.msgID)
            }
            // Return back on the NIO event loop and write a response
            context.eventLoop.execute {
                _ = context.writeAndFlush(self.wrapOutboundOut(response))
            }
        }
    }

}

extension NIOAtomic where T == Int {
    func next() -> T {
        add(1)
    }
}

extension ChannelHandlerContext: UnsafeConcurrentValue {}

/// Maelstrom RPC messages service
final public class MaelstromRPC {

    let logger: Logger
    let bootstrap: NIOPipeBootstrap
    let group: EventLoopGroup

    var channel: Channel?

    public init(group: EventLoopGroup, logger: Logger, messageProvider: MessageProvider, additionalMessages: [Message.Type] = []) throws {
        self.logger = logger
        self.group = group

        let coder = RPCPacketCoder(logger: logger)

        self.bootstrap = NIOPipeBootstrap(group: group)
            .channelInitializer { channel in
                // Register handlers
                channel.pipeline.addHandlers([
                    // Bytes => RPC Message
                    ByteToMessageHandler(coder),
                    // RPC Message => Bytes
                    MessageToByteHandler(coder),
                    // RPC Message processor
                    MessageHandler(messageProvider: messageProvider, logger: logger)
                ])
            }
        try registerSystemMessages(in: coder, additionalMessages: additionalMessages)
    }

    public func start() throws -> Channel {
        let channel = try bootstrap.withPipes(inputDescriptor: STDIN_FILENO, outputDescriptor: STDOUT_FILENO).wait()
        self.channel = channel
        logger.info("Maelstrom started and listening on STDIN")
        return channel
    }

    public func stop() {
        do {
            try group.syncShutdownGracefully()
        } catch {
            logger.error("Error shutting down: \(error)")
        }
        logger.info("Maelstrom stopped")
    }

    func registerSystemMessages(in coder: RPCPacketCoder, additionalMessages: [Message.Type]) throws {
        // Register Maelstrom default messages
        try coder.registerMessage(Maelstrom.Error.self)
        try coder.registerMessage(Maelstrom.Init.self)
        try coder.registerMessage(Maelstrom.InitOk.self)
        try coder.registerMessage(Maelstrom.Echo.self)
        try coder.registerMessage(Maelstrom.EchoOk.self)
        try coder.registerMessage(Maelstrom.Read.self)
        try coder.registerMessage(Maelstrom.ReadOk.self)
        try coder.registerMessage(Maelstrom.Write.self)
        try coder.registerMessage(Maelstrom.WriteOk.self)
        try coder.registerMessage(Maelstrom.Cas.self)
        try coder.registerMessage(Maelstrom.CasOk.self)
    }
}
