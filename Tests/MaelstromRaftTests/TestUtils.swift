//===----------------------------------------------------------------------===//
//
// This source file is part of the SwiftNIO open source project
//
// Copyright (c) 2017-2018 Apple Inc. and the SwiftNIO project authors
// Licensed under Apache License v2.0
//
// See LICENSE.txt for license information
// See CONTRIBUTORS.txt for the list of SwiftNIO project authors
//
// SPDX-License-Identifier: Apache-2.0
//
//===----------------------------------------------------------------------===//

// Get from NIO project https://github.com/apple/swift-nio/blob/main/Tests/NIOTests/TestUtils.swift

import XCTest
import NIO
import _Concurrency


func withPipe(_ body: (NIO.NIOFileHandle, NIO.NIOFileHandle) throws -> [NIO.NIOFileHandle]) throws {
    var fds: [Int32] = [-1, -1]
    fds.withUnsafeMutableBufferPointer { ptr in
        XCTAssertEqual(0, pipe(ptr.baseAddress!))
    }
    let readFH = NIOFileHandle(descriptor: fds[0])
    let writeFH = NIOFileHandle(descriptor: fds[1])
    var toClose: [NIOFileHandle] = [readFH, writeFH]
    var error: Error? = nil
    do {
        toClose = try body(readFH, writeFH)
    } catch let err {
        error = err
    }
    try toClose.forEach { fh in
        XCTAssertNoThrow(try fh.close())
    }
    if let error = error {
        throw error
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
