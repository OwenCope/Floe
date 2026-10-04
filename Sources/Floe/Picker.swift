//
//  Picker.swift
//  Project: Floe
//
//  Copyright (Floe) © 2026 René Jiménez
//  Licensed under the GNU AGPLv3

import Foundation

/// One line of the picker's input, with the place it had there.
struct PickItem: Identifiable, Equatable {
    /// Zero-based position among every line of the input, blank ones included.
    let index: Int
    let text: String

    var id: Int {
        index
    }
}

/// How `Floe --pick` ends, as the exit status the calling script sees.
enum PickExit: Int32 {
    case chosen = 0
    case cancelled = 1
    /// sysexits' EX_USAGE: the command was called the wrong way.
    case usage = 64
}

/// The picker without its window: what the input holds, what a query leaves of it, and what a choice prints.
enum PickList {
    static let usage = "Floe --pick reads the items to choose from on standard input, one per line: ls | Floe --pick"

    /// A line of nothing but spaces is blank too. The text is kept as it came, so the caller gets its own line back.
    static func items(from input: String) -> [PickItem] {
        input.split(omittingEmptySubsequences: false, whereSeparator: \.isNewline)
            .enumerated()
            .compactMap { index, line in
                line.allSatisfy(\.isWhitespace) ? nil : PickItem(index: index, text: String(line))
            }
    }

    /// No query lists everything in input order. With one, the best match comes first and equal scores keep input order.
    static func matches(_ items: [PickItem], query: String) -> [PickItem] {
        guard !query.isEmpty else { return items }
        let scored: [(item: PickItem, score: Int)] = items.compactMap { item in
            Fuzzy.score(query, item.text).map { (item, $0) }
        }
        // The position breaks ties, so the order does not depend on the sort being stable.
        let ordered = scored.sorted { first, second in
            first.score == second.score ? first.item.index < second.item.index : first.score > second.score
        }
        return ordered.map(\.item)
    }

    static func output(for item: PickItem, printsIndex: Bool) -> String {
        printsIndex ? String(item.index) : item.text
    }

    /// The bottom bar's count: everything while there is no query, then how much of it still matches.
    static func countLabel(shown: Int, total: Int, isFiltered: Bool) -> String {
        if isFiltered {
            return "\(shown) of \(total)"
        }
        return total == 1 ? "1 item" : "\(total) items"
    }

    /// The selection after an arrow, page or home/end key, kept inside the list.
    static func selection(_ selection: Int, movedBy delta: Int, count: Int) -> Int {
        max(0, min(count - 1, selection + delta))
    }
}
