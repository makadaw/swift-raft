// SPDX-License-Identifier: MIT
// Copyright © 2021 makadaw


import enum Dispatch.DispatchTimeInterval

public extension DispatchTimeInterval {

    /// Convert time interval into nanoseconds. Use it inside for comprising and most of the implementation will need it also
    var nanoseconds: Int64 {
        switch self {
        case .nanoseconds(let ns): return Int64(ns)
        case .microseconds(let us): return Int64(us) * 1000
        case .milliseconds(let ms): return Int64(ms) * 1_000_000
        case .seconds(let s): return Int64(s) * 1_000_000_000
        default: return .max
        }
    }
}
