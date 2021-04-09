// SPDX-License-Identifier: MIT
// Copyright © 2021 makadaw


import XCTest
import Logging
import NIO
@testable import MaelstromRaft

class KvNodeTests: XCTestCase {

    func testInit() throws {
        let service = BootstrapNode(group: MultiThreadedEventLoopGroup(numberOfThreads: 1), client: TestClient(), configuration: .init(id: 22))

        runAsyncTestAndBlock {
            let onInit = try await service.onMessage(Maelstrom.Init(nodeID: "1", nodeIDs: ["1", "2"]))
            XCTAssertEqual(onInit as? Maelstrom.InitOk, Maelstrom.InitOk())
        }
    }
}

class TestClient: PeerClient {
    func send(_ message: Message, dest: String) async throws -> Message {
        fatalError("Not Implemented")
    }
}
