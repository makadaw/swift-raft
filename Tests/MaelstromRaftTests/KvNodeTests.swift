// SPDX-License-Identifier: MIT
// Copyright © 2021 makadaw


import XCTest
import Logging
import NIO
import _Concurrency
@testable import MaelstromRaft

class KvNodeTests: XCTestCase {

    func testInit() throws {
        let raft = KvNode(configuration: .init(id: 22))

        runAsyncTestAndBlock {
            let onInit = try await raft.onMessage(Maelstrom.Init(nodeID: "1", nodeIDs: ["1", "2"]))
            XCTAssertEqual(onInit as? Maelstrom.InitOk, Maelstrom.InitOk())
        }
    }

    func testNonExistingRead() throws {
        let raft = KvNode(configuration: .init(id: 22))

        runAsyncTestAndBlock {
            let onInit = try await raft.onMessage(Maelstrom.Init(nodeID: "1", nodeIDs: ["1", "2"]))
            XCTAssertEqual(onInit as? Maelstrom.InitOk, Maelstrom.InitOk())
            do {
                _ = try await raft.onMessage(Maelstrom.Read(key: 123))
                XCTFail("Read non existing key should throw an error")
            } catch {
                XCTAssertEqual(error as? Maelstrom.Error, .keyDoesNotExist)
            }
        }
    }
}

/// Replace deprecated `runAsyncAndBlock` until XCTest support async
func runAsyncTestAndBlock(closure: @escaping () async throws -> Void) {
    let group = DispatchGroup()
    group.enter()

    _ = Task.runDetached {
        do {
            try await closure()
        } catch {
            XCTFail("\(error)")
        }
        group.leave()
    }

    group.wait()
}
