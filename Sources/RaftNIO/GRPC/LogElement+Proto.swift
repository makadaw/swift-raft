// SPDX-License-Identifier: MIT
// Copyright © 2021 makadaw


import Foundation
import SwiftRaft

extension LogElement {
    init?(_ raftLog: Raft_Entry) {
        switch raftLog.type {
            case .configuration:
                self = LogElement.configuration(termId: raftLog.term, index: raftLog.index)
            case .data:
                guard let content = T.init(data: raftLog.data) else {
                    return nil
                }

                self = LogElement.data(termId: raftLog.term, index: raftLog.index, content: content)
            default:
                return nil
        }
    }
}
