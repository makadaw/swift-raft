// SPDX-License-Identifier: MIT
// Copyright © 2021 makadaw


import XCTest
@testable import MaelstromRaft

class PackagesDecoding: XCTestCase {
    
    func testInitMessageDecoding() throws {
        let message = """
{"src": "c1", "dest": "n1", "id": 0, "body": {"msg_id": 1, "type": "init", "node_id": "n1", "node_ids": ["n1"]}}
"""
        let packet = try RPCPacket.decoder.decode(RPCPacket.self, from: message)
        XCTAssertEqual(packet.src, "c1")
        XCTAssertEqual(packet.dest, "n1")
        XCTAssertEqual(packet.body, .`init`(nodeID: "n1", nodeIDs: ["n1"]))
    }
    
    func testInitOkMessageEncoding() throws {
        let response: RPCPacket.Message = .initOk
        let str = String(data: try! RPCPacket.encoder.encode(response), encoding: .utf8)
        XCTAssertEqual(str, "{\"type\":\"init_ok\"}")
    }

    func testEchoCoding() throws {
        let message = """
{"dest":"n1","body":{"echo":"Please echo 106","type":"echo","msg_id":1},"src":"c2","id":2}
"""
        let packet = try RPCPacket.decoder.decode(RPCPacket.self, from: message)
        XCTAssertEqual(packet.body, .echo("Please echo 106"))
    }

    func testEchoEncoding() throws {
        let response = RPCPacket(src: "n1", dest: "n2", id: 0, body: .echoOk("Please echo 106"))
        let str = try RPCPacket.encoder.encodeAsString(response)
        XCTAssertEqual(str, "{\"dest\":\"n2\",\"id\":0,\"body\":{\"type\":\"echo_ok\",\"echo\":\"Please echo 106\"},\"src\":\"n1\"}")
    }

    func testErrorEncoding() throws {
        let response = RPCPacket(src: "n1", dest: "n2", id: 0, body: .error(.crash))
        let str = try RPCPacket.encoder.encodeAsString(response)
        XCTAssertEqual(str, "{\"dest\":\"n2\",\"id\":0,\"body\":{\"type\":\"error\",\"code\":13},\"src\":\"n1\"}")
    }
}

extension JSONDecoder {
    func decode<T: Decodable>(_ type: T.Type, from string: String) throws -> T {
        guard let data = string.trimmingCharacters(in: .newlines).data(using: .utf8) else {
            // Throw random error
            throw DecodingError.dataCorrupted(.init(codingPath: [], debugDescription: ""))
        }
        return try decode(T.self, from: data)
    }
}

extension JSONEncoder {
    func encodeAsString<T: Encodable>(_ value: T) throws -> String {
        guard let str = String(data: try self.encode(value), encoding: .utf8) else {
            // Throw random error
            throw DecodingError.dataCorrupted(.init(codingPath: [], debugDescription: ""))
        }
        return str
    }
}
