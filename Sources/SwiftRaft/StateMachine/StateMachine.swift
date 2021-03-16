// SPDX-License-Identifier: MIT
// Copyright © 2021 makadaw


public protocol StateMachine {
    associatedtype Message: ConcurrentValue
    associatedtype Response: ConcurrentValue
    associatedtype Entry: LogData

    /// Run a read-only query on the state machine and get a message response
    func query(_ message: Message) async throws -> Response

    /// Apply log entry to the state machine
    func apply(entry: Entry) async throws -> Bool
}
