//
//  MainThreadCallbacksTests.swift
//  Project: Floe
//
//  Copyright (Floe) © 2026 René Jiménez
//  Licensed under the GNU AGPLv3

@testable import Floe
import Foundation
import Testing

@MainActor struct MainThreadCallbacksTests {
    @Test func anObserverIsCalledForItsNotificationUntilItIsRemoved() {
        let center = NotificationCenter()
        let name = Notification.Name("floe-main-observer-test")
        var calls = 0
        let observer = center.addMainObserver(forName: name, object: nil) { calls += 1 }

        // Posted on the main thread to an observer on the main queue, so the block has run when `post` returns.
        center.post(name: name, object: nil)
        center.post(name: Notification.Name("floe-another-name"), object: nil)
        #expect(calls == 1)

        center.removeObserver(observer)
        center.post(name: name, object: nil)
        #expect(calls == 1)
    }

    @Test func aTimerRunsItsBlockWhenItFires() {
        var calls = 0
        let timer = Timer.scheduledOnMain(withTimeInterval: 3600, repeats: false) { calls += 1 }
        #expect(timer.isValid)

        timer.fire()
        #expect(calls == 1)
        #expect(!timer.isValid)
    }
}
