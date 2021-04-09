// SPDX-License-Identifier: MIT
// Copyright © 2021 makadaw


import DequeModule

public struct MemoryLog<T: LogData>: Log {
    public typealias Data = T
    public typealias Iterator = Deque<LogElement<Data>>.Iterator

    public init() {}

    public __consuming func makeIterator() -> Iterator {
        return storage.makeIterator()
    }

    var startIndex: UInt = 1
    var endIndex: UInt = 1

    public var logStartIndex: UInt {
        startIndex
    }

    public var logLastIndex: UInt {
        Swift.max(0, startIndex + UInt(storage.count) - 1)
    }

    public var count: Int {
        storage.count
    }

    var storage: Deque<LogElement<Data>> = .init()

    /// Runtime safe get method
    public func entry(at position: UInt) throws -> LogElement<Data> {
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

    public mutating func append(_ entries: [LogElement<Data>]) -> ClosedRange<UInt> {
        let firstIndex = startIndex + UInt(storage.count)
        let lastIndex = firstIndex + UInt(entries.count)
        storage.append(contentsOf: entries)
        endIndex = lastIndex
        return ClosedRange(firstIndex..<lastIndex)
    }

    public mutating func truncatePrefix(_ firstIndex: UInt) {
        if firstIndex > startIndex {
            // remove log entries in range startIndex..<firstIndex
            let end = storage.index(storage.startIndex,
                                    offsetBy: Swift.min(Int(firstIndex - startIndex), storage.count))
            storage.removeSubrange(storage.startIndex..<end)
            self.startIndex = firstIndex
        }
    }

    public mutating func truncateSuffix(_ lastIndex: UInt) {
        if lastIndex < startIndex {
            storage.removeAll()
        } else if Int(lastIndex) < Int(startIndex) - 1 + storage.count {
            storage.removeLast(storage.count - Int(lastIndex) - Int(startIndex) + 1)
        }
    }

    /// Memory log do not write metadata to any storage
    public var metadata = LogMetadata()
}

extension Deque: UnsafeConcurrentValue {}
