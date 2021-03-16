// SPDX-License-Identifier: MIT
// Copyright © 2021 makadaw


import XCTest
import _Concurrency

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
