// SPDX-License-Identifier: MIT
// Copyright © 2021 makadaw


import NIO
import enum Dispatch.DispatchTimeInterval

extension DispatchTimeInterval {
    var timeAmount: TimeAmount {
        .nanoseconds(nanoseconds)
    }
}

extension EventLoop {
    func scheduleDetachedTask(in interval: DispatchTimeInterval, _ task: @escaping @concurrent () async -> Void) -> NIO.Scheduled<Void> {
        scheduleTask(in: interval.timeAmount) {
            Task.runDetached {
                await task()
            }
        }
    }

    func scheduleRepeatedAsyncTask(initialDelay: TimeAmount,
                                   delay: DispatchTimeInterval,
                                   _ task: @escaping @concurrent () async -> Void) -> RepeatedTask {
        scheduleRepeatedTask(initialDelay: initialDelay,
                             delay: delay.timeAmount) { _ in
            Task.runDetached {
                await task()
            }
        }
    }
}

extension EventLoopFuture {
    public func get() async throws -> Value {
        return try await withUnsafeThrowingContinuation { cont in
            self.whenComplete { result in
                switch result {
                    case .success(let value):
                        cont.resume(returning: value)
                    case .failure(let error):
                        cont.resume(throwing: error)
                }
            }
        }
    }
}
