//
//  TypingSettleTests.swift
//  Project: Floe
//
//  Copyright (Floe) © 2026 René Jiménez
//  Licensed under the GNU AGPLv3

@testable import Floe
import Foundation
import Testing

struct TypingSettleTests {
    /// A clock and a timer the test moves by hand.
    private final class Time {
        var now: TimeInterval = 100
        var timers: [(fire: TimeInterval, work: DispatchWorkItem)] = []

        func settle(window: TimeInterval) -> TypingSettle {
            let settle = TypingSettle(now: { self.now }, later: { self.timers.append((self.now + $0, $1)) })
            settle.window = window
            return settle
        }

        func advance(to time: TimeInterval) {
            now = time
            for timer in timers where timer.fire <= time && !timer.work.isCancelled {
                timer.work.perform()
            }
            timers.removeAll { $0.fire <= time }
        }
    }

    @Test func withNoWindowEveryKeyIsAnsweredAtOnce() {
        let settle = Time().settle(window: 0)
        var answers: [String] = []
        for text in ["s", "sa", "saf"] {
            settle.changed { answers.append(text) }
        }
        #expect(answers == ["s", "sa", "saf"])
        #expect(!settle.isWaiting)
    }

    @Test func theFirstKeyIsAnsweredAtOnceAndABurstAfterItOnce() {
        let time = Time()
        let settle = time.settle(window: 0.05)
        var answers: [String] = []

        settle.changed { answers.append("s") }
        #expect(answers == ["s"], "no wait before the first key's results")

        time.now += 0.01
        settle.changed { answers.append("sa") }
        time.now += 0.01
        settle.changed { answers.append("saf") }
        #expect(answers == ["s"])
        #expect(settle.isWaiting)

        time.advance(to: time.now + 0.05)
        #expect(answers == ["s", "saf"], "one answer for the burst, with the latest text")
        #expect(!settle.isWaiting)
    }

    @Test func aHeldKeyIsAnsweredEveryWindowAndNotOnlyWhenItIsLetGo() {
        let time = Time()
        let settle = time.settle(window: 0.05)
        var answers = 0
        let start = time.now
        for step in 0 ..< 20 {
            time.advance(to: start + Double(step) * 0.03)
            settle.changed { answers += 1 }
        }
        #expect(answers >= 8, "about one answer per window over 0.6 s, got \\(answers)")
        #expect(answers < 20, "fewer answers than keys")
    }

    @Test func aKeyTypedAfterAPauseIsAnsweredAtOnce() {
        let time = Time()
        let settle = time.settle(window: 0.05)
        var answers: [String] = []
        settle.changed { answers.append("a") }
        time.advance(to: time.now + 0.2)
        settle.changed { answers.append("ab") }
        #expect(answers == ["a", "ab"])
    }

    @Test func flushingAnswersWhatIsWaitingOnceAndCancelsItsTimer() {
        let time = Time()
        let settle = time.settle(window: 0.05)
        var answers: [String] = []
        settle.changed { answers.append("a") }
        settle.changed { answers.append("ab") }

        settle.flush()
        #expect(answers == ["a", "ab"])

        time.advance(to: time.now + 1)
        settle.flush()
        #expect(answers == ["a", "ab"], "nothing is answered twice")
    }
}
