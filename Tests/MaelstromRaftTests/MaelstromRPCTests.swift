// SPDX-License-Identifier: MIT
// Copyright © 2021 makadaw


import XCTest
import Logging
import NIO
import RaftNIO
@testable import MaelstromRaft

@available(macOS 9999, *)
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
                runAsyncTestAndBlock {
                    let producer = try MaelstromRPC(
                        group: self.group,
                        logger: {
                            var logger = Logger(label: "PRODUCER")
                            logger.logLevel = .trace
                            return logger
                        }())

                    try await producer.innerStart(messageProvider: EchoProvider(),
                                                  inputDescriptor: FileHandle(fileDescriptor: try pipe1Read.takeDescriptorOwnership(), closeOnDealloc: false).fileDescriptor,
                                                  outputDescriptor: FileHandle(fileDescriptor: try pipe2Write.takeDescriptorOwnership(), closeOnDealloc: false).fileDescriptor)

                    let consumer = try MaelstromRPC(
                        group: self.group,
                        logger: {
                            var logger = Logger(label: "CONSUMER")
                            logger.logLevel = .trace
                            return logger
                        }())
                    try await consumer.innerStart(messageProvider: EchoProvider(),
                                                  inputDescriptor: FileHandle(fileDescriptor: try pipe2Read.takeDescriptorOwnership(), closeOnDealloc: false).fileDescriptor,
                                                  outputDescriptor: FileHandle(fileDescriptor: try pipe1Write.takeDescriptorOwnership(), closeOnDealloc: false).fileDescriptor)

                    // Force set a node IDs, so it will use it to send requests
                    await producer.setTestNodeId(self.producerID)
                    await consumer.setTestNodeId(self.consumerID)

                    self.producer = producer
                    self.consumer = consumer
                }
                return []
            })
            return []
        })
    }

    override func tearDown() {
        runAsyncTestAndBlock {
            await self.producer.stop()
            await self.consumer.stop()
            XCTAssertNoThrow(try self.group.syncShutdownGracefully())
        }
    }

    func testSendMessage() throws {
        runAsyncTestAndBlock {
            // Send a echo request to the consumer
            let response = try await self.producer.send(Maelstrom.Echo(echo: "Text 61"), dest: self.consumerID)
            // Validate that consumer response with a `echo_ok` message
            XCTAssertEqual(response as? Maelstrom.EchoOk, Maelstrom.EchoOk(echo: "Text 61"))
        }

    }

    func testNotSupportedMessages() throws {
        runAsyncTestAndBlock {
            do {
                _ = try await self.producer.send(NotSupportedMessage(), dest: self.consumerID)
                XCTFail("We should got an error on not supported message")
            } catch {
                XCTAssertEqual(error as? Maelstrom.Error, .notSupported)
            }
        }
    }
}

@available(macOS 9999, *)
extension MaelstromRPC {
    func setTestNodeId(_ nodeID: String) async {
        messageHandler?.nodeID = nodeID
    }
}

struct NotSupportedMessage: Message {
    static var messageType: String = "not_supported"
}
