// SPDX-License-Identifier: MIT
// Copyright © 2021 makadaw


import XCTest
import Logging
import NIO
import RaftNIO
@testable import MaelstromRaft

class MaelstromRPCTests: XCTestCase {

    var group: MultiThreadedEventLoopGroup! = nil

    let producerID = "31"
    let consumerID = "42"

    var producer: MaelstromRPC!
    var consumer: MaelstromRPC!

    override func setUp() {
        self.group = .init(numberOfThreads: 1)
        // We create 2 pipes, but it's important to use them and close inside the test, or it will not be closed
        // MaelstromRPC get ownership on this descriptors and will close it on close call
        XCTAssertNoThrow(try withPipe { pipe1Read, pipe1Write in
            try withPipe({ pipe2Read, pipe2Write in
                let producer = try MaelstromRPC(
                    group: group,
                    logger: {
                        var logger = Logger(label: "PRODUCER")
                        logger.logLevel = .trace
                        return logger
                    }(),
                    messageProvider: EchoProvider())
                _ = try producer.innerStart(inputDescriptor: FileHandle(fileDescriptor: try pipe1Read.takeDescriptorOwnership(), closeOnDealloc: false).fileDescriptor,
                                            outputDescriptor: FileHandle(fileDescriptor: try pipe2Write.takeDescriptorOwnership(), closeOnDealloc: false).fileDescriptor)
                    .wait()

                let consumer = try MaelstromRPC(
                    group: group,
                    logger: {
                        var logger = Logger(label: "CONSUMER")
                        logger.logLevel = .trace
                        return logger
                    }(),
                    messageProvider: EchoProvider())
                _ = try consumer.innerStart(inputDescriptor: FileHandle(fileDescriptor: try pipe2Read.takeDescriptorOwnership(), closeOnDealloc: false).fileDescriptor,
                                            outputDescriptor: FileHandle(fileDescriptor: try pipe1Write.takeDescriptorOwnership(), closeOnDealloc: false).fileDescriptor)
                    .wait()


                // Force set a node IDs, so it will use it to send requests
                producer.messageHandler.nodeID = producerID
                consumer.messageHandler.nodeID = consumerID

                self.producer = producer
                self.consumer = consumer
                return []
            })
            return []
        })
    }

    override func tearDown() {
        producer.stop()
        consumer.stop()
        XCTAssertNoThrow(try self.group.syncShutdownGracefully())
    }

    func testSendMessage() throws {
        // Send a echo request to the consumer
        let response = try producer.send(Maelstrom.Echo(echo: "Text 61"), dest: consumerID).wait()
        // Validate that consumer response with a `echo_ok` message
        XCTAssertEqual(response as? Maelstrom.EchoOk, Maelstrom.EchoOk(echo: "Text 61"))
    }

    func testNotSupportedMessages() throws {
        XCTAssertThrowsError(try producer.send(NotSupportedMessage(), dest: consumerID).wait(),
                             "We should got an error on not supported message")
        { error in
            XCTAssertEqual(error as? Maelstrom.Error, .notSupported)
        }
    }
}

struct NotSupportedMessage: Message {
    static var type: String = "not_supported"
}
