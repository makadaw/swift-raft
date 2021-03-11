// SPDX-License-Identifier: MIT
// Copyright © 2021 makadaw


import NIO

public class EchoProvider: MessageProvider {

    public init() {}

    public func onMessage(_ message: RPCPacket.Message, context: CallHandlerContext) -> EventLoopFuture<RPCPacket.Message> {
        switch message {
            case .`init`:
                return context.eventLoop.makeSucceededFuture(.initOk)

            case let .echo(payload):
                return context.eventLoop.makeSucceededFuture(.echoOk(payload))

            default:
                return context.eventLoop.makeFailedFuture(RPCPacket.Error.notSupported)
        }
    }
}
