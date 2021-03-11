// SPDX-License-Identifier: MIT
// Copyright © 2021 makadaw


import Foundation
import Logging
import NIO
import NIOConcurrencyHelpers
import NIOFoundationCompat


/// Process messages from the network
public protocol MessageProvider {

    func onMessage(_ message: RPCPacket.Message, context: CallHandlerContext) -> EventLoopFuture<RPCPacket.Message>
}

public struct CallHandlerContext {
    var logger: Logger

    var eventLoop: EventLoop
}

class MessageHandler: ChannelDuplexHandler {
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
        let future = messageProvider.onMessage(request.body,
                                               context: CallHandlerContext(logger: logger,
                                                                           eventLoop: context.eventLoop))
        if nodeID == nil, request.isInit {
            self.nodeID = request.initNodeID
        }
        future.whenSuccess { message in
            guard let nodeID = self.nodeID else {
                preconditionFailure("Didn't get init message")
            }
            let response = RPCPacket(src: nodeID,
                                     dest: request.src,
                                     id: request.id,
                                     body: message,
                                     msgID: self.counter.next(),
                                     inReplyTo: request.msgID)
            _ = context.writeAndFlush(self.wrapOutboundOut(response))
        }
        future.whenFailure { error in
            self.logger.error("\(error)")
            let finalError: RPCPacket.Error = error as? RPCPacket.Error ?? .undefined
            let response = RPCPacket(src: self.nodeID ?? request.dest,
                                     dest: request.src,
                                     id: request.id,
                                     body: .error(finalError),
                                     msgID: self.counter.next(),
                                     inReplyTo: request.msgID)
            _ = context.writeAndFlush(self.wrapOutboundOut(response))
        }
    }

}

extension NIOAtomic where T == Int {
    func next() -> T {
        add(1)
    }
}


final public class MaelstromRPC {

    let logger: Logger
    let bootstrap: NIOPipeBootstrap
    let group: EventLoopGroup
    var channel: Channel?

    public init(group: EventLoopGroup, logger: Logger, messageProvider: MessageProvider) {
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
            exit(0)
        }
        logger.info("Maelstrom stopped")
    }

}
