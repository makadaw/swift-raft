// SPDX-License-Identifier: MIT
// Copyright © 2021 makadaw


import Foundation
import Logging
import NIO
import NIOFoundationCompat

public struct RPCPacket: ConcurrentValue {
    // Simple error representation
    public enum Error: Int, Swift.Error, Codable, ConcurrentValue {

        // Indicates that the requested operation could not be completed within a timeout.
        case timeout = 0
        // Thrown when a client sends an RPC request to a node which does not exist.
        case nodeNotFound = 1
        // Use this error to indicate that a requested operation is not supported by the current implementation.
        case notSupported = 10
        // Indicates that the operation definitely cannot be performed at this time--perhaps because the server is in a read-only state,
        // has not yet been initialized, believes its peers to be down, and so on.
        // Do not use this error for indeterminate cases, when the operation may actually have taken place.
        case temporarilyUnavailable = 11
        // The client's request did not conform to the server's expectations, and could not possibly have been processed.
        case malformedRequest = 12
        // Indicates that some kind of general, indefinite error occurred.
        case crash = 13
        // Indicates that some kind of general, definite error occurred.
        case abort = 14
        // The client requested an operation on a key which does not exist (assuming the operation should not automatically create missing keys).
        case keyDoesNotExist = 20
        // The client requested the creation of a key which already exists, and the server will not overwrite it.
        case keyAlreadyExists = 21
        // The requested operation expected some conditions to hold, and those conditions were not met.
        case preconditionFailed = 22
        // The requested transaction has been aborted because of a conflict with another transaction.
        case txnConflict = 23

        // All users error goes here
        case undefined = 1000

        enum CodingKeys: CodingKey {
            case code
        }

        public init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            guard let error = Error(rawValue: try container.decode(Int.self, forKey: .code)) else {
                self = .undefined
                return
            }
            self = error
        }

        public func encode(to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode(rawValue, forKey: .code)
        }
    }

    public enum Message: Equatable, ConcurrentValue {
        case error(Error)
        case `init`(nodeID: String, nodeIDs: [String])
        case initOk

        // Echo messages
        case echo(String)
        case echoOk(String)

        // Raft messages
        case read(key: Int)
        case readOk(value: Int)
        case write(key: Int, value: Int)
        case writeOk
        case cas(key: Int, from: Int, to: Int)
        case casOk
    }

    let src: String
    let dest: String
    let id: Int
    var body: Message {
        internalBody.body
    }
    var msgID: Int? {
        internalBody.msgId
    }

    let internalBody: ParseMessage

    init(src: String, dest: String, id: Int, body: Message, msgID: Int? = nil, inReplyTo: Int? = nil) {
        self.src = src
        self.dest = dest
        self.id = id
        self.internalBody = ParseMessage(body: body, msgId: msgID, inReplyTo: inReplyTo)
    }

    static var decoder: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return decoder
    }

    static var encoder: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.keyEncodingStrategy = .convertToSnakeCase
        return encoder
    }
}

extension RPCPacket: Codable {

    struct ParseMessage: Codable, ConcurrentValue {
        let body: Message
        let msgId: Int?
        let inReplyTo: Int?

        enum CodingKeys: String, CodingKey {
            case msgId, inReplyTo
        }

        init(body: Message, msgId: Int?, inReplyTo: Int?) {
            self.body = body
            self.msgId = msgId
            self.inReplyTo = inReplyTo
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)

            self.init(body: try Message(from: decoder),
                      msgId: try container.decodeIfPresent(Int.self, forKey: .msgId),
                      inReplyTo: try container.decodeIfPresent(Int.self, forKey: .inReplyTo))
        }

        func encode(to encoder: Encoder) throws {
            try body.encode(to: encoder)
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encodeIfPresent(msgId, forKey: .msgId)
            try container.encodeIfPresent(inReplyTo, forKey: .inReplyTo)
        }
    }

    enum CodingKeys: String, CodingKey {
        case src, dest, id
        case internalBody = "body"
    }

}

extension RPCPacket {
    var isInit: Bool {
        if case .`init` = body {
            return true
        }
        return false
    }

    var initNodeID: String? {
        if case let .`init`(nodeID, _) = body {
            return nodeID
        }
        return nil
    }
}

extension RPCPacket.Message: Codable {
    enum CodingKeys: String, CodingKey {
        case type, code, nodeId, nodeIds
        case echo, key, value, from, to
    }

    // swiftlint:disable:next cyclomatic_complexity
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        switch try container.decode(String.self, forKey: .type) {
            case "error":
                self = .error(try RPCPacket.Error(from: decoder))
            case "init":
                self = .`init`(nodeID: try container.decode(String.self, forKey: .nodeId),
                               nodeIDs: try container.decode([String].self, forKey: .nodeIds))
            case "init_ok":
                self = .initOk

            case "echo":
                self = .echo(try container.decode(String.self, forKey: .echo))
            case "echo_ok":
                self = .echoOk(try container.decode(String.self, forKey: .echo))

            case "read":
                self = .read(key: try container.decode(Int.self, forKey: .key))
            case "read_ok":
                self = .readOk(value: try container.decode(Int.self, forKey: .value))
            case "write":
                self = .write(key: try container.decode(Int.self, forKey: .key),
                              value: try container.decode(Int.self, forKey: .value))
            case "write_ok":
                self = .writeOk
            case "cas":
                self = .cas(key: try container.decode(Int.self, forKey: .key),
                            from: try container.decode(Int.self, forKey: .from),
                            to: try container.decode(Int.self, forKey: .to))
            case "cas_ok":
                self = .casOk

            default:
                throw RPCPacket.Error.notSupported
        }
    }

    // swiftlint:disable:next cyclomatic_complexity
    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
            case let .error(error):
                try container.encode("error", forKey: .type)
                try error.encode(to: encoder)
            case let .`init`(nodeId, nodeIds):
                try container.encode("init", forKey: .type)
                try container.encode(nodeId, forKey: .nodeId)
                try container.encode(nodeIds, forKey: .nodeIds)
            case .initOk:
                try container.encode("init_ok", forKey: .type)

            case let .echo(payload):
                try container.encode("echo", forKey: .type)
                try container.encode(payload, forKey: .echo)
            case let .echoOk(payload):
                try container.encode("echo_ok", forKey: .type)
                try container.encode(payload, forKey: .echo)

            case let .read(key: key):
                try container.encode("read", forKey: .type)
                try container.encode(key, forKey: .key)
            case let .readOk(value: value):
                try container.encode("read_ok", forKey: .type)
                try container.encode(value, forKey: .value)
            case let .write(key: key, value: value):
                try container.encode("read", forKey: .type)
                try container.encode(key, forKey: .key)
                try container.encode(value, forKey: .value)
            case .writeOk:
                try container.encode("write_ok", forKey: .type)
            case let .cas(key: key, from: from, to: to):
                try container.encode("cas", forKey: .type)
                try container.encode(key, forKey: .key)
                try container.encode(from, forKey: .from)
                try container.encode(to, forKey: .to)
            case .casOk:
                try container.encode("cas_ok", forKey: .type)
        }
    }
}


class RPCPacketCoder: ByteToMessageDecoder, MessageToByteEncoder {
    typealias InboundOut = RPCPacket
    typealias OutboundIn = RPCPacket

    let logger: Logger

    init(logger: Logger) {
        self.logger = logger
    }

    func decode(context: ChannelHandlerContext, buffer: inout ByteBuffer) throws -> DecodingState {
        if let packet = try scanNextPacket(buffer: &buffer) {
            logger.trace("Decoded RPCPacket: \(packet)")
            context.fireChannelRead(wrapInboundOut(packet))
            return .continue
        } else {
            return .needMoreData
        }
    }


    var decodedData: Data?
    private func scanNextPacket(buffer: inout ByteBuffer) throws -> RPCPacket? {
        guard let line = readLine(buffer: &buffer) else {
            return nil
        }
        do {
            logger.trace("Get JSON \(String(data: line, encoding: .utf8) ?? "")")
            return try RPCPacket.decoder.decode(RPCPacket.self, from: line)
        } catch {
            logger.error("Failed to parse RPC \(error)")
        }
        return nil
    }

    /// Not the most elegant way, but works for testing
    private func readLine(buffer: inout ByteBuffer) -> Data? {

        // Create a string buffer
        var stringBuffer = ""
        // Read by 1 length string from a buffer
        while let char = buffer.readString(length: 1) {
            if char == "\n" {
                if stringBuffer.isEmpty {
                    return nil
                }
                return stringBuffer.trimmingCharacters(in: .illegalCharacters).data(using: .utf8)
            }
            stringBuffer.append(char)
        }
        return nil
    }

    func encode(data: RPCPacket, out: inout ByteBuffer) throws {
        logger.trace("Encoding RPCPacket: \(data)")
        do {
            let body = try RPCPacket.encoder.encode(data)
            logger.trace("Response JSON \(String(data: body, encoding: .utf8)!)")
            out.writeData(body)
            out.writeString("\n")
        } catch {
            logger.error("Failed to parse response")
            throw error
        }
    }

}
