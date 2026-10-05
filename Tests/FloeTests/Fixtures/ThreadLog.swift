//
//  ThreadLog.swift
//  Project: Floe
//
//  Copyright (Floe) © 2026 René Jiménez
//  Licensed under the GNU AGPLv3

import Foundation
import Synchronization

/// Remembers, per label, whether a piece of work ran on the main thread.
final nonisolated class ThreadLog: Sendable {
    private let seen = Mutex<[String: Bool]>([:])

    /// Label to "ran on the main thread", for everything noted so far.
    var onMain: [String: Bool] {
        seen.withLock { $0 }
    }

    /// Called from inside the work itself, on whatever thread it was given.
    func note(_ label: String) {
        let onMain = Thread.isMainThread
        seen.withLock { $0[label] = onMain }
    }
}

/// Counts the jobs a task is handed away from its actor, for work with nothing inside to observe.
/// Code that stays on the main actor never comes here; code that leaves it does.
final nonisolated class CountingExecutor: TaskExecutor {
    private let queue = DispatchQueue(label: "floe.tests.counting-executor")
    private let handed = Mutex(0)

    var count: Int {
        handed.withLock { $0 }
    }

    func enqueue(_ job: consuming ExecutorJob) {
        handed.withLock { $0 += 1 }
        let job = UnownedJob(job)
        queue.async { job.runSynchronously(on: self.asUnownedTaskExecutor()) }
    }

    /// How many times `work` left the main actor while it ran.
    @MainActor
    static func departures(during work: @MainActor () async -> Void) async -> Int {
        let executor = CountingExecutor()
        await withTaskExecutorPreference(executor) { await work() }
        return executor.count
    }
}
