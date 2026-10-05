//
//  MainThreadCallbacks.swift
//  Project: Floe
//
//  Copyright (Floe) © 2026 René Jiménez
//  Licensed under the GNU AGPLv3

import Foundation

extension NotificationCenter {
    /// Observes a notification on the main queue with a block that may touch main actor state.
    func addMainObserver(forName name: Notification.Name, object: Any?, using block: @escaping @MainActor () -> Void) -> NSObjectProtocol {
        addObserver(forName: name, object: object, queue: .main) { _ in
            // Safe: an observer given the main queue is called on the main thread.
            MainActor.assumeIsolated(block)
        }
    }
}

extension Timer {
    /// A timer on the main run loop whose block may touch main actor state.
    static func scheduledOnMain(withTimeInterval interval: TimeInterval, repeats: Bool, block: @escaping @MainActor () -> Void) -> Timer {
        scheduledTimer(withTimeInterval: interval, repeats: repeats) { _ in
            // Safe: this is scheduled from the main actor, so it fires on the main run loop.
            MainActor.assumeIsolated(block)
        }
    }
}
