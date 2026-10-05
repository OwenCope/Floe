//
//  AIConversation.swift
//  Project: Floe
//
//  Copyright (Floe) © 2026 René Jiménez
//  Licensed under the GNU AGPLv3

import Foundation

/// A question and the exchange before it, as a source is handed them. It is a value in memory:
/// nothing here is saved or logged, and an extension's prompt is one of these with no earlier turns.
nonisolated struct AIConversation: Sendable, Equatable {
    /// A question that was answered.
    struct Turn: Sendable, Equatable {
        let question: String
        let answer: String

        /// In UTF-8 bytes, which follow a model's tokens across languages and cost nothing to count.
        var size: Int {
            question.utf8.count + answer.utf8.count
        }
    }

    /// How much of the earlier exchange is sent again with a question.
    struct Limit: Sendable, Equatable {
        var turns: Int
        /// Counted as `Turn.size` counts them.
        var characters: Int

        /// About 3,000 tokens: inside the 4,096 a local server starts with, and little to pay for on an API.
        static let standard = Limit(turns: 8, characters: 12000)
        /// Apple Intelligence has 4,096 tokens for the earlier turns, the question and its answer together.
        static let appleIntelligence = Limit(turns: 8, characters: 6000)

        static func limit(for source: AISource) -> Limit {
            switch source {
            case .appleIntelligence: appleIntelligence
            case .tools, .api: standard
            }
        }
    }

    /// The shortest marker between the parts of a replayed prompt; `mark(for:)` makes it longer when the text needs it.
    static let shortestMark = 5

    /// Oldest first.
    var earlier: [Turn] = []
    var question: String

    /// The newest of `turns` that fit the limit, in order, and how many older ones were left out.
    /// A turn is sent whole or not at all, so a source never reads half an answer as all of it.
    static func fitting(_ turns: [Turn], limit: Limit) -> (kept: [Turn], dropped: Int) {
        var size = 0
        var kept = 0
        for turn in turns.reversed() {
            guard kept < limit.turns, size + turn.size <= limit.characters else { break }
            size += turn.size
            kept += 1
        }
        return (Array(turns.suffix(kept)), turns.count - kept)
    }

    /// The earlier turns as chat messages for an API: each question from the user, each answer from the assistant.
    var earlierMessages: [[String: String]] {
        earlier.flatMap { [["role": "user", "content": $0.question], ["role": "assistant", "content": $0.answer]] }
    }

    /// What a command line tool reads: the question alone, or the earlier turns and then the question.
    /// A tool starts fresh each time and keeps no session, so the exchange is written out for it.
    var replayedPrompt: String {
        guard !earlier.isEmpty else { return question }
        let mark = Self.mark(for: earlier.flatMap { [$0.question, $0.answer] } + [question])
        var lines = [
            "Earlier questions and answers from this conversation come first, for context. "
                + "Answer only the new question at the end. Each part starts on the line after one that begins with \(mark).",
            "",
        ]
        for (index, turn) in earlier.enumerated() {
            lines += ["\(mark) Question \(index + 1)", turn.question, "\(mark) Answer \(index + 1)", turn.answer]
        }
        lines += ["\(mark) New question", question]
        return lines.joined(separator: "\n")
    }

    /// A run of "=" longer than any that starts a line of `texts`, so no line of theirs reads as a marker.
    static func mark(for texts: [String]) -> String {
        var longest = 0
        for text in texts {
            for line in text.split(whereSeparator: \.isNewline) {
                longest = max(longest, line.drop(while: \.isWhitespace).prefix { $0 == "=" }.count)
            }
        }
        return String(repeating: "=", count: max(shortestMark, longest + 1))
    }
}
