// SPDX-License-Identifier: MIT
// Copyright © 2021 makadaw

import Foundation

extension Path {
    var toURL: URL {
        URL(fileURLWithPath: absolutePath)
    }
}
