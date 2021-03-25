// SPDX-License-Identifier: MIT
// Copyright © 2021 makadaw


import Foundation
import SwiftRaft

// Use string as dummy application data
extension String: LogData {

    public init?(data: Data) {
        self.init(data: data, encoding: .utf8)
    }

    public var size: Int {
        self.data(using: .utf8)?.count ?? 0
    }
}
