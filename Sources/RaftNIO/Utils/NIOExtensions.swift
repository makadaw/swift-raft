// SPDX-License-Identifier: MIT
// Copyright © 2021 makadaw


import NIO
import enum Dispatch.DispatchTimeInterval

extension DispatchTimeInterval {
    var timeAmount: TimeAmount {
        .nanoseconds(nanoseconds)
    }
}

@available(macOS 9999, *)
extension EventLoop {
    func scheduleDetachedTask(in interval: DispatchTimeInterval, _ task: @escaping @Sendable () async -> Void) -> NIO.Scheduled<Void> {
        scheduleTask(in: interval.timeAmount) {
            detach {
                await task()
            }
        }
    }

    func scheduleRepeatedAsyncTask(initialDelay: TimeAmount,
                                   delay: DispatchTimeInterval,
                                   _ task: @escaping @Sendable () async -> Void) -> RepeatedTask {
        scheduleRepeatedTask(initialDelay: initialDelay,
                             delay: delay.timeAmount) { _ in
            detach {
                await task()
            }
        }
    }
}
