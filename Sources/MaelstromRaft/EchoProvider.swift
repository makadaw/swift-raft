// SPDX-License-Identifier: MIT
// Copyright © 2021 makadaw


import NIO

public actor EchoProvider: MessageProvider {

    public init() {}

    public func onMessage(_ message: RPCPacket.Message) async throws -> RPCPacket.Message {
        switch message {
            case .`init`:
                return .initOk

            case let .echo(echo):
                return .echoOk(echo)

            default:
                throw RPCPacket.Error.notSupported
        }
    }
}
