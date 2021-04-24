// SPDX-License-Identifier: MIT
// Copyright © 2021 makadaw


import MaelstromRaft
import SwiftRaft
import NIO
import Logging
import Lifecycle


@available(macOS 9999, *)
class App {

    func run() throws {
        var logger = Logger(label: "RAFT") { _ in
            StreamLogHandler.standardError(label: "RAFT")
        }
        logger.logLevel = .debug

        let lifecycle = ServiceLifecycle(configuration: .init(logger: logger))
        let group = MultiThreadedEventLoopGroup(numberOfThreads: System.coreCount)

        var config = Configuration(id: 0)
        config.logger = logger
        let service = try MaelstromRPC(
            group: group,
            logger: logger,
            additionalMessages: [RequestVote.Request.self,
                                 RequestVote.Response.self])
        let node = BootstrapNode(group: group, client: service, configuration: config)
        lifecycle.register(label: "maelstrom", start: .sync {
            detach {
                try? await service.start(messageProvider: node)
            }
        }, shutdown: .sync {
            detach {
                await service.stop()
            }
            try group.syncShutdownGracefully()
        })

        try lifecycle.startAndWait()
    }
}

if #available(macOS 9999, *) {
    try App().run()
} else {
    print("Unsupported MacOS version")
    exit(1)
}
