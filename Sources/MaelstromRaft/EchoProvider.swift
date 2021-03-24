// SPDX-License-Identifier: MIT
// Copyright © 2021 makadaw


import NIO

public actor EchoProvider: MessageProvider {

    public init() {}

    public func onMessage(_ message: Message) async throws -> Message {
        switch message {
            case is Maelstrom.Init:
                return Maelstrom.InitOk()

            case let echo as Maelstrom.Echo:
                return Maelstrom.EchoOk(echo: echo.echo)

            default:
                throw Maelstrom.Error.notSupported
        }
    }
}
