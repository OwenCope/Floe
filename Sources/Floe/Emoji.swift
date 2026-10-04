//
//  Emoji.swift
//  Project: Floe
//
//  Copyright (Floe) © 2026 René Jiménez
//  Licensed under the GNU AGPLv3

import Foundation

/// One emoji or symbol: the character to paste and its display name.
struct EmojiResult: Sendable {
    let character: String
    let name: String

    var id: String {
        Self.id(for: character)
    }

    static func id(for character: String) -> String {
        "emoji:\(character)"
    }
}

/// The emoji and symbol catalog. Entries come from Unicode scalar properties, not bundled data:
/// every named symbol scalar (which covers the pictographic emoji) becomes a searchable entry.
/// The table is built once, in the background; searches before it finishes find nothing yet.
enum EmojiCatalog {
    struct Entry: Sendable {
        let character: String
        let name: String
        let searchText: String
        let keywords: [String]
    }

    private static let lock = NSLock()
    private static var cached: [Entry]?
    private static var preloadStarted = false

    /// Starts building the table off the caller's thread; safe to call more than once.
    static func preload() {
        lock.lock()
        defer { lock.unlock() }
        guard !preloadStarted else { return }
        preloadStarted = true
        DispatchQueue.global(qos: .utility).async {
            _ = entries()
        }
    }

    static func entries() -> [Entry] {
        lock.lock()
        if let cached {
            lock.unlock()
            return cached
        }
        lock.unlock()
        let built = build()
        lock.lock()
        defer { lock.unlock() }
        if let cached {
            return cached
        }
        cached = built
        return built
    }

    /// With an empty term: recent picks first, then common standbys. Otherwise the best
    /// name and keyword matches, nudged by how often and how recently each was used.
    static func search(term: String, frecency: (String) -> Double, limit: Int = 8) -> [EmojiResult] {
        let all = entries()
        let needle = term.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !needle.isEmpty else {
            let recent = all
                .filter { frecency($0.character) > 0 }
                .sorted { frecency($0.character) > frecency($1.character) }
                .prefix(limit)
            let seen = Set(recent.map(\.character))
            let fill = commonCharacters
                .compactMap { character in all.first(where: { $0.character == character }) }
                .filter { !seen.contains($0.character) }
                .prefix(max(0, limit - recent.count))
            return (recent + fill).map { EmojiResult(character: $0.character, name: $0.name) }
        }
        return all
            .compactMap { entry -> (Entry, Double)? in
                guard let match = score(needle: needle, entry: entry) else { return nil }
                return (entry, Double(match) + min(20, frecency(entry.character) * 2))
            }
            .sorted { $0.1 > $1.1 }
            .prefix(limit)
            .map { EmojiResult(character: $0.0.character, name: $0.0.name) }
    }

    private static func score(needle: String, entry: Entry) -> Int? {
        // An exact keyword wins outright, so common names beat longer Unicode names.
        if entry.keywords.contains(needle) {
            return 1000
        }
        var best = Fuzzy.score(needle, entry.searchText)
        for keyword in entry.keywords {
            if let keywordScore = Fuzzy.score(needle, keyword) {
                best = max(best ?? 0, keywordScore)
            }
        }
        return best
    }

    private static func build() -> [Entry] {
        let symbols = CharacterSet.symbols
        var out: [Entry] = []
        out.reserveCapacity(8192)
        for value in UInt32(0) ... 0x10FFFF {
            guard let scalar = Unicode.Scalar(value), symbols.contains(scalar) else { continue }
            guard let rawName = scalar.properties.name else { continue }
            let character = String(scalar)
            out.append(Entry(
                character: character,
                name: rawName.capitalized,
                searchText: rawName.lowercased(),
                keywords: extraKeywords[character] ?? []
            ))
        }
        return out
    }

    /// Standbys shown for an empty query when there are no recents yet. Every one is a single
    /// named symbol scalar, so each is guaranteed to be in the table once it is built.
    private static let commonCharacters: [String] = [
        "🔥", "❤", "😀", "👍", "🎉", "✅", "❌", "⭐",
    ]

    /// Extra search words for common entries, keyed by character. The Unicode names alone miss
    /// the words people type ("fire" is covered by the FIRE scalar's name; "flame" is not).
    private static let extraKeywords: [String: [String]] = [
        "🔥": ["fire", "flame", "hot", "lit"],
        "❤": ["heart", "love"],
        "😀": ["smile", "happy", "grin", "grinning"],
        "👍": ["thumbs up", "thumbsup", "like", "approve", "yes"],
        "🎉": ["party", "celebrate", "celebration", "tada", "congrats"],
        "✅": ["check", "checkmark", "done", "yes", "tick"],
        "❌": ["cross", "x", "no", "wrong", "delete"],
        "⭐": ["star", "favorite", "favourite"],
        "©": ["copyright"],
        "®": ["registered"],
        "™": ["trademark", "tm"],
        "→": ["arrow", "right", "rightarrow"],
        "←": ["arrow", "left", "leftarrow"],
        "↑": ["arrow", "up", "uparrow"],
        "↓": ["arrow", "down", "downarrow"],
        "✓": ["check", "checkmark", "tick"],
        "♥": ["heart", "suit", "hearts"],
        "☀": ["sun", "sunny", "weather"],
        "⚡": ["lightning", "bolt", "zap", "fast"],
        "€": ["euro", "money", "currency"],
    ]
}
