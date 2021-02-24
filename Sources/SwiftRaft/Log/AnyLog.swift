// SPDX-License-Identifier: MIT
// Copyright © 2021 makadaw


/// Base class for Log type eraser to make Raft non-generic
class BaseLog {

    var logLastIndex: UInt {
        fatalError("Abstract class")
    }

    var metadata: LogMetadata {
        fatalError("Abstract class")
    }

}

class AnyLog<ApplicationLog>: BaseLog where ApplicationLog: Log {
    private var log: ApplicationLog

    init(log: ApplicationLog) {
        self.log = log
    }

    override var logLastIndex: UInt {
        log.logLastIndex
    }

    override var metadata: LogMetadata {
        log.metadata
    }
}
