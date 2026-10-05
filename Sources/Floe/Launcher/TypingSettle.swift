//
//  TypingSettle.swift
//  Project: Floe
//
//  Copyright (Floe) © 2026 René Jiménez
//  Licensed under the GNU AGPLv3

import Foundation

/// Paces the search while keys arrive. The first key is answered at once; the keys that follow it share one
/// answer per window, so a held key or a paste draws one list of results and not one per character.
final class TypingSettle {
    /// How long the keys after the first are gathered. Zero answers every key at once, which tests and benchmarks want.
    var window: TimeInterval = 0

    private var lastAnswer = -TimeInterval.infinity
    private var waiting: (() -> Void)?
    private var timer: DispatchWorkItem?
    private let now: () -> TimeInterval
    private let later: (TimeInterval, DispatchWorkItem) -> Void

    init(
        now: @escaping () -> TimeInterval = { ProcessInfo.processInfo.systemUptime },
        later: @escaping (TimeInterval, DispatchWorkItem) -> Void = { DispatchQueue.main.asyncAfter(deadline: .now() + $0, execute: $1) }
    ) {
        self.now = now
        self.later = later
    }

    var isWaiting: Bool {
        waiting != nil
    }

    /// The text changed. `answer` runs now, or once with the latest text when the window closes.
    func changed(_ answer: @escaping () -> Void) {
        guard window > 0 else {
            answer()
            return
        }
        if waiting == nil, now() - lastAnswer >= window {
            lastAnswer = now()
            answer()
            return
        }
        let isFirstToWait = waiting == nil
        waiting = answer
        // Not restarted by each key: a held key still gets an answer every window.
        guard isFirstToWait else { return }
        let timer = DispatchWorkItem { [weak self] in self?.flush() }
        self.timer = timer
        later(window, timer)
    }

    /// Answers now if an answer is waiting: Return and the arrow keys act on the results of what was typed.
    func flush() {
        guard let answer = waiting else { return }
        timer?.cancel()
        timer = nil
        waiting = nil
        lastAnswer = now()
        answer()
    }
}
