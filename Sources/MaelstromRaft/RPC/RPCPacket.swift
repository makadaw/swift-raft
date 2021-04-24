// SPDX-License-Identifier: MIT
// Copyright © 2021 makadaw


import Foundation
import Logging
import NIO
import NIOFoundationCompat

public protocol Message: Codable, Sendable {
    static var messageType: String { get }
}

public struct Maelstrom {

    // RPC error representation
    public enum Error: Int, Swift.Error, Message {
        public static var messageType = "error"

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

    public struct `Init`: Message, Equatable {
        public static let messageType = "init"
        public let nodeID: String
        public let nodeIDs: [String]

        enum CodingKeys: CodingKey {
            case nodeId, nodeIds
        }

        init(nodeID: String, nodeIDs: [String]) {
            self.nodeID = nodeID
            self.nodeIDs = nodeIDs
        }

        public init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            nodeID = try container.decode(String.self, forKey: .nodeId)
            nodeIDs = try container.decode([String].self, forKey: .nodeIds)
        }

        public func encode(to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode(nodeID, forKey: .nodeId)
            try container.encode(nodeIDs, forKey: .nodeIds)
        }
    }

    public struct InitOk: Message, Equatable {
        public static let messageType = "init_ok"
    }

    public struct Echo: Message, Equatable {
        public static let messageType = "echo"
        public let echo: String
    }

    public struct EchoOk: Message, Equatable {
        public static let messageType = "echo_ok"
        public let echo: String
    }

    public struct Read: Message {
        public static let messageType = "read"
        let key: Int
    }

    public struct ReadOk: Message {
        public static let messageType = "read_ok"
        let value: Int
    }

    public struct Write: Message {
        public static let messageType = "write"
        let key: Int
        let value: Int
    }

    public struct WriteOk: Message {
        public static let messageType = "write_ok"
    }

    public struct Cas: Message {
        public static let messageType = "cas"
        let key: Int
        let from: Int
        let to: Int
    }

    public struct CasOk: Message {
        public static let messageType = "cas_ok"
    }
}

struct RPCPacket: Sendable {
    // Decoder user info key. Use to store a mapping
    static let key: CodingUserInfoKey = CodingUserInfoKey(rawValue: "MessageMapping")!

    enum CodingError: Swift.Error {
        case typeAlreadyRegistered(type: String)
        case coderMissTypeMapper
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
}

extension RPCPacket: Codable {
    /// Use "smart" struct to get msgID, replyID from message body
    struct ParseMessage: Codable, Sendable {
        let body: Message
        let msgId: Int?
        let inReplyTo: Int?

        enum CodingKeys: String, CodingKey {
            case type, msgId, inReplyTo
        }

        init(body: Message, msgId: Int?, inReplyTo: Int?) {
            self.body = body
            self.msgId = msgId
            self.inReplyTo = inReplyTo
        }

        init(from decoder: Decoder) throws {
            guard let mapping = decoder.userInfo[RPCPacket.key] as? [String: Message.Type] else {
                throw CodingError.coderMissTypeMapper
            }
            let container = try decoder.container(keyedBy: CodingKeys.self)
            let type = try container.decode(String.self, forKey: .type)

            // In case we don't know this message, parse as error
            self.init(body: try mapping[type].map({ try $0.init(from: decoder) }) ?? Maelstrom.Error.notSupported,
                      msgId: try container.decodeIfPresent(Int.self, forKey: .msgId),
                      inReplyTo: try container.decodeIfPresent(Int.self, forKey: .inReplyTo))
        }

        func encode(to encoder: Encoder) throws {
            // Encode message to the container
            try body.encode(to: encoder)
            var container = encoder.container(keyedBy: CodingKeys.self)
            // Encode default fields to the container
            try container.encode(type(of: body).messageType, forKey: .type)
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
        if body is Maelstrom.Init {
            return true
        }
        return false
    }

    var initNodeID: String? {
        guard let body = self.body as? Maelstrom.Init else {
            return nil
        }
        return body.nodeID
    }
}

class RPCPacketCoder: ByteToMessageDecoder, MessageToByteEncoder {
    typealias InboundOut = RPCPacket
    typealias OutboundIn = RPCPacket

    private let logger: Logger
    private let jsonDecoder: JSONDecoder
    private let jsonEncoder: JSONEncoder

    init(logger: Logger) {
        self.logger = logger
        self.jsonDecoder = JSONDecoder()
        self.jsonDecoder.keyDecodingStrategy = .convertFromSnakeCase
        self.jsonDecoder.userInfo[RPCPacket.key] = [:]
        self.jsonEncoder = JSONEncoder()
        self.jsonEncoder.keyEncodingStrategy = .convertToSnakeCase
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
            return try decode(data: line)
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
            let body = try encode(packet: data)
            logger.trace("Send JSON \(String(data: body, encoding: .utf8)!)")
            out.writeData(body)
            out.writeString("\n")
        } catch {
            logger.error("Failed to parse response")
            throw error
        }
    }

    // MARK: Messages registry
    private var register: [String: Message.Type] {
        get {
            // swiftlint:disable:next force_cast
            self.jsonDecoder.userInfo[RPCPacket.key] as! [String: Message.Type]
        }
        set {
            self.jsonDecoder.userInfo[RPCPacket.key] = newValue
        }
    }

    func registerMessage(_ message: Message.Type) throws {
        guard register[message.messageType] == nil else {
            throw RPCPacket.CodingError.typeAlreadyRegistered(type: message.messageType)
        }
        register[message.messageType] = message.self
    }

    func decode(data: Data) throws -> RPCPacket {
        try jsonDecoder.decode(RPCPacket.self, from: data)
    }

    func encode(packet: RPCPacket) throws -> Data {
        try jsonEncoder.encode(packet)
    }
}
