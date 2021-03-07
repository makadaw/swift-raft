// SPDX-License-Identifier: MIT
// Copyright © 2021 makadaw


import SwiftRaft
import Foundation

struct ArrayLog<T: LogData>: Log {
    typealias Data = T
    typealias Iterator = Array<LogElement<Data>>.Iterator

    __consuming func makeIterator() -> Iterator {
        return storage.makeIterator()
    }

    var startIndex: UInt = 1
    var endIndex: UInt = 1

    var logStartIndex: UInt {
        startIndex
    }

    var logLastIndex: UInt {
        Swift.max(0, startIndex + UInt(storage.count) - 1)
    }

    var count: Int {
        storage.count
    }

    var storage: Array<LogElement<Data>> = .init()

    /// Runtime safe get method
    func entry(at position: UInt) throws -> LogElement<Data> {
        let real = _position(offsetBy: position)
        guard !(real < 0 || real >= storage.count) else {
            throw LogError.outOfRange
        }
        return storage[real]
    }

    /// return real entry position in the storage
    private func _position(offsetBy position: UInt) -> Int {
        Int(position) - Int(startIndex)
    }

    mutating func append(_ entries: [LogElement<Data>]) -> ClosedRange<UInt> {
        let firstIndex = startIndex + UInt(storage.count)
        let lastIndex = firstIndex + UInt(entries.count)
        storage.append(contentsOf: entries)
        endIndex = lastIndex
        return ClosedRange(firstIndex..<lastIndex)
    }

    mutating func truncatePrefix(_ firstIndex: UInt) {
        if (firstIndex > startIndex) {
            // remove log entries in range startIndex..<firstIndex
            let end = storage.index(storage.startIndex,
                                    offsetBy: Swift.min(Int(firstIndex - startIndex), storage.count))
            storage.removeSubrange(storage.startIndex..<end)
            self.startIndex = firstIndex
        }
    }

    mutating func truncateSuffix(_ lastIndex: UInt) {
        if lastIndex < startIndex {
            storage.removeAll()
        } else if Int(lastIndex) < Int(startIndex) - 1 + storage.count {
            storage.removeLast(storage.count - Int(lastIndex) - Int(startIndex) + 1)
        }
    }

    /// Memory log do not write metadata to any storage
    var metadata = LogMetadata()
}

// Use string as dummy application data
extension String: LogData {

    public init?(data: Data) {
        self.init(data: data, encoding: .utf8)
    }

    public var size: Int {
        self.data(using: .utf8)?.count ?? 0
    }
}
