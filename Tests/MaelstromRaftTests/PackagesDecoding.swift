// SPDX-License-Identifier: MIT
// Copyright © 2021 makadaw


import XCTest
import Logging
@testable import MaelstromRaft

class PackagesDecoding: XCTestCase {
    let logger: Logger = .init(label: "tests")
    var coder: RPCPacketCoder {
        RPCPacketCoder(logger: logger)
    }

    func testInitMessageDecoding() throws {
        let message = """
{"src": "c1", "dest": "n1", "id": 0, "body": {"msg_id": 1, "type": "init", "node_id": "n1", "node_ids": ["n1"]}}
"""
        let coder = self.coder
        try coder.registerMessage(Maelstrom.Init.self)
        let packet = try coder.decode(string: message)
        XCTAssertEqual(packet.src, "c1")
        XCTAssertEqual(packet.dest, "n1")
        XCTAssertEqual(packet.body as? Maelstrom.Init, Maelstrom.Init(nodeID: "n1", nodeIDs: ["n1"]))
    }

    func testInitOkMessageEncoding() throws {
        let response = RPCPacket(src: "n1", dest: "n2", id: 0, body: Maelstrom.InitOk())
        let str = try coder.encodeToString(packet: response)
        XCTAssertEqual(str, "{\"dest\":\"n2\",\"id\":0,\"body\":{\"type\":\"init_ok\"},\"src\":\"n1\"}")
    }

    func testEchoCoding() throws {
        let message = """
{"dest":"n1","body":{"echo":"Please echo 106","type":"echo","msg_id":1},"src":"c2","id":2}
"""
        let coder = self.coder
        try coder.registerMessage(Maelstrom.Echo.self)
        let packet = try coder.decode(string: message)
        XCTAssertEqual(packet.body as? Maelstrom.Echo, Maelstrom.Echo(echo: "Please echo 106"))
    }

    func testEchoEncoding() throws {
        let response = RPCPacket(src: "n1", dest: "n2", id: 0, body: Maelstrom.EchoOk(echo: "Please echo 106"))
        let str = try coder.encodeToString(packet: response)
        XCTAssertEqual(str, "{\"dest\":\"n2\",\"id\":0,\"body\":{\"type\":\"echo_ok\",\"echo\":\"Please echo 106\"},\"src\":\"n1\"}")
    }

    func testErrorEncoding() throws {
        let response = RPCPacket(src: "n1", dest: "n2", id: 0, body: Maelstrom.Error.crash)
        let str = try coder.encodeToString(packet: response)
        XCTAssertEqual(str, "{\"dest\":\"n2\",\"id\":0,\"body\":{\"type\":\"error\",\"code\":13},\"src\":\"n1\"}")
    }
}

extension RPCPacketCoder {
    func decode(string: String) throws -> RPCPacket {
        guard let data = string.trimmingCharacters(in: .newlines).data(using: .utf8) else {
            // Throw random decoder error
            throw DecodingError.dataCorrupted(.init(codingPath: [], debugDescription: ""))
        }
        return try decode(data: data)
    }

    func encodeToString(packet: RPCPacket) throws -> String {
        guard let str = String(data: try self.encode(packet: packet), encoding: .utf8) else {
            // Throw random error
            throw DecodingError.dataCorrupted(.init(codingPath: [], debugDescription: ""))
        }
        return str
    }
}
