// SPDX-License-Identifier: MIT
// Copyright © 2021 makadaw


import SwiftRaft
import NIO
import Logging
import enum Dispatch.DispatchTimeInterval

// Node that connect time operations with a Raft logic.
// We use NIO EvenLoop to schedule election and heartbeat timers.
// This actor is time depend, and should be used in the real code.
@available(macOS 9999, *)
open actor Node<ApplicationLog> where ApplicationLog: Log {

    let group: EventLoopGroup
    let config: Configuration

    public var logger: Logger {
        config.logger
    }

    /// Application log, used to store messages
    var log: ApplicationLog
    /// Raft logic node
    var raft: Raft<ApplicationLog>!

    public init(group: EventLoopGroup, configuration: Configuration, log: ApplicationLog) {
        self.group = group
        self.config = configuration
        self.log = log
    }

    public func startNode(peers: [SwiftRaft.Peer]) async {
        raft = Raft(config: config,
                    peers: peers,
                    log: log)

        // TODO Get this command from a Raft node. Maybe create a start method
        await onElectionCommand(.scheduleNextTimer(delay: config.protocol.nextElectionTimeout))
    }

    // MARK: Leader election
    var electionTimer: Scheduled<Void>?
    private func resetElectionTimeout(next delay: DispatchTimeInterval) {
        electionTimer?.cancel()
        electionTimer = eventLoop.scheduleDetachedTask(in: delay, {
            await self.electionTimeout()
        })
    }

    func electionTimeout() async {
        await onElectionCommand(await raft.onElectionTimeout())
    }

    func onElectionCommand(_ command: Raft<ApplicationLog>.ElectionCommand) async {
        switch command {
            case .startPreVote:
                await onElectionCommand(await raft.startPreVote())

            case .startVote:
                await onElectionCommand(await raft.startVote())

            case .startToBeALeader:
                await onRaftCommands(await raft.onBecomeLeader())

            case .stopTimer:
                electionTimer?.cancel()
                electionTimer = nil

            case let .scheduleNextTimer(delay):
                resetElectionTimeout(next: delay)
        }
    }

    // MARK: Message send
    var heartbeatTask: RepeatedTask?
    func onRaftCommands(_ commands: [Raft<ApplicationLog>.EntriesCommand]) async {
        for command in commands {
            switch command {
                case let .resetElectionTimer(delay):
                    resetElectionTimeout(next: delay)

                case .sendHeartBeat:
                    await onRaftCommands(await raft.sendHeartBeat())

                case .stepDown:
                    heartbeatTask?.cancel()
                    heartbeatTask = nil

                case let .scheduleHeartBeatTask(delay):
                    heartbeatTask?.cancel()
                    heartbeatTask = eventLoop.scheduleRepeatedAsyncTask(
                        initialDelay: .zero,
                        delay: delay) {
                        await self.sendHeartBeat()
                    }
            }
        }
    }

    func sendHeartBeat() async {
        await onRaftCommands(await raft.sendHeartBeat())
    }

    var eventLoop: EventLoop {
        group.next()
    }
}

// Proxy methods for non actors wrappers
@available(macOS 9999, *)
public extension Node {
    func onVoteRequest(_ request: RequestVote.Request) async -> RequestVote.Response {
        await raft.onVoteRequest(request)
    }

    func onAppendEntries<T>(_ request: AppendEntries.Request<T>) async -> AppendEntries.Response where T == ApplicationLog.Data {
        let response = await raft.onAppendEntries(request)
        await onRaftCommands(response.commands)
        return response.response
    }
}
