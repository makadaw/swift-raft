// SPDX-License-Identifier: MIT
// Copyright © 2021 makadaw


import Foundation
import Logging
import NIO
import NIOConcurrencyHelpers
import NIOFoundationCompat


/// Process messages from the network. Here consumer get all messages from the network that is not a responses
/// It may also contain errors (eg: if processor get a message with unsupported type)
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

    // RPC node details
    var responseCallbacks: [String: MessageResponseCallback] = [:]
    let counter: NIOAtomic<Int> = NIOAtomic.makeAtomic(value: 1)
    var nodeID: String?

    init(messageProvider: MessageProvider, logger: Logger) {
        self.messageProvider = messageProvider
        self.logger = logger
    }

    func channelRead(context: ChannelHandlerContext, data: NIOAny) {
        // Maelstrom request
        let request = unwrapInboundIn(data)

        logger.debug("Get RPC request \(request)")
        // Set node ID from `init` message
        if nodeID == nil, request.isInit {
            self.nodeID = request.initNodeID
        }

        // Check is we have a callback waiting for this message. For this compare source and reply id
        if let key = request.internalBody.inReplyTo.map({buildKey(src: request.src, msgID: $0)}),
           let callback = responseCallbacks[key] {
            // Delete a callback, we should not get a second message with the same reply id
            responseCallbacks.removeValue(forKey: key)
            if let error = request.body as? Maelstrom.Error {
                callback.promise.fail(error)
            } else {
                callback.promise.succeed(request.body)
            }
        }

        // Run a normal routine for a message. Consumer should process it or return an error
        // Run a coroutine to get a response and write into the context
        Task.runDetached {
            let response: RPCPacket
            do {
                let message = try await self.messageProvider.onMessage(request.body)
                response = self.createPacket(dest: request.src, id: request.id, inReplyTo: request.msgID, body: message)
            } catch {
                self.logger.error("\(error)")
                let finalError: Maelstrom.Error = error as? Maelstrom.Error ?? .undefined
                // Build error packet manually, as we may not have a `nodeID` yet
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

    func createPacket(dest: String, id: Int = 0, inReplyTo: Int? = nil, body: Message) -> RPCPacket {
        guard let nodeID = self.nodeID else {
            preconditionFailure("Send message before getting init message, we don't know self node id, yet")
        }
        return RPCPacket(src: nodeID,
                         dest: dest,
                         id: id,
                         body: body,
                         msgID: counter.next(),
                         inReplyTo: inReplyTo)
    }

    /// Register a message callback based on message ID
    func registerCallback(_ callback: MessageResponseCallback) {
        responseCallbacks[buildKey(src: callback.src, msgID: callback.msgID)] = callback
    }

    private func buildKey(src: String, msgID: Int) -> String {
        "\(src):\(msgID)"
    }
}

struct MessageResponseCallback {
    let msgID: Int
    let src: String
    let promise: EventLoopPromise<Message>
}

extension NIOAtomic where T == Int {
    // Monotonic increase counter (if call only this method)
    func next() -> T {
        add(1)
    }
}

extension ChannelHandlerContext: UnsafeConcurrentValue {}

/// Maelstrom RPC messages service
final public actor MaelstromRPC {

    let logger: Logger
    let bootstrap: NIOPipeBootstrap
    let group: EventLoopGroup

    var messageHandler: MessageHandler?
    var channel: Channel?

    public init(group: EventLoopGroup, logger: Logger, additionalMessages: [Message.Type] = []) throws {
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
                ])
            }
        try registerMessages(in: coder, additionalMessages: additionalMessages)
    }

    /// Start a service. Service subscribe on STDIN and response to STDOUT
    public func start(messageProvider: MessageProvider) async throws {
        try await innerStart(
            messageProvider: messageProvider,
            inputDescriptor: STDIN_FILENO,
            outputDescriptor: STDOUT_FILENO)
    }

    @discardableResult
    func innerStart(messageProvider: MessageProvider, inputDescriptor: CInt, outputDescriptor: CInt) async throws -> Channel {
        let channel = try await bootstrap.withPipes(inputDescriptor: inputDescriptor, outputDescriptor: outputDescriptor).get()
        let messageHandler = MessageHandler(messageProvider: messageProvider, logger: logger)
        self.messageHandler = messageHandler
        // Add RPC Message processor
        try await channel.pipeline.addHandler(messageHandler).get()
        self.channel = channel
        self.logger.info("Maelstrom started and listening on STDIN")
        return channel
    }

    /// Close the channel if it was open. Will not fire an error
    public func stop() async {
        do {
            try await channel?.close().get()
        } catch {
            logger.error("Error shutting down: \(error)")
            return
        }
        logger.info("Maelstrom stopped")
    }

    private func registerMessages(in coder: RPCPacketCoder, additionalMessages: [Message.Type]) throws {
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
        // After system messages register user messages, they can't override already registered
        for messageType in additionalMessages {
            try coder.registerMessage(messageType)
        }
    }

    // MARK: Broadcast
    /// Broadcast message into Maelstrom network. Future will be fulfilled when we get an response from Maelstrom network
    public func send(_ message: Message, dest: String) async throws -> Message {
        guard let channel = self.channel, let messageHandler = self.messageHandler else {
            preconditionFailure("Send a message without starting a channel")
        }
        let packet = messageHandler.createPacket(dest: dest, body: message)
        guard let msgID = packet.msgID else {
            preconditionFailure("We should not create messages without ID for sending")
        }
        let promise = group.next().makePromise(of: Message.self)
        messageHandler.registerCallback(MessageResponseCallback(msgID: msgID, src: dest, promise: promise))
        _ = channel.writeAndFlush(packet)
        return try await promise.futureResult.get()
    }
}
