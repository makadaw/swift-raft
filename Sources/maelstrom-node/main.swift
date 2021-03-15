// SPDX-License-Identifier: MIT
// Copyright © 2021 makadaw


import MaelstromRaft
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

        let rpc = MaelstromRPC(group: group, logger: logger, messageProvider: RaftProvider(logger: logger))
        lifecycle.register(label: "maelstrom", start: .sync {
            _ = try rpc.start()
        }, shutdown: .sync {
            rpc.stop()
        })

        try lifecycle.startAndWait()
    }
}

try App().run()
