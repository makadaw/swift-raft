// SPDX-License-Identifier: MIT
// Copyright © 2021 makadaw


import MaelstromRaft
import SwiftRaft
import NIO
import Logging
import Lifecycle


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
        let service = MaelstromRPC(group: group, logger: logger, messageProvider: KvNode(configuration: config))
        lifecycle.register(label: "maelstrom", start: .sync {
            _ = try service.start()
        }, shutdown: .sync {
            service.stop()
        })

        try lifecycle.startAndWait()
    }
}

try App().run()
