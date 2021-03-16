// SPDX-License-Identifier: MIT
// Copyright © 2021 makadaw


import SwiftRaft
import Foundation

actor KvStateMachine: StateMachine {
    typealias Message = Int
    typealias Response = Int

    struct Entry {
        let key: Int
        let value: Int
    }

    enum Error: Swift.Error {
        case keyDoesNotExist
    }

    var storage: [Int: Int] = [:]

    //MARK: Client

    /// Read value for a message.
    func query(_ message: Message) async throws -> Response {
        guard let result = storage[message] else {
            throw Error.keyDoesNotExist
        }
        return result
    }

    //MARK: Server

    /// Apply entries from the log into state machine
    @discardableResult
    func apply(entry: Entry) async throws -> Bool {
        storage[entry.key] = entry.value
        return true
    }
}

extension KvStateMachine.Entry: LogData, Codable {

    static func decode(from data: Data) -> KvStateMachine.Entry? {
        try? JSONDecoder().decode(Self.self, from: data)
    }

    var size: Int {
        // Double a size of Int
        MemoryLayout<Int>.size * 2
    }


}
