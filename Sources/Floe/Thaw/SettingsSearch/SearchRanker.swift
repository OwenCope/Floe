//
//  SearchRanker.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3
//
//  Floe changes © 2026 René Jiménez, under the same license.
//
//  Thaw 3's field weights and relevance sort (Settings/Search/SearchRanker.swift). Thaw scores
//  with Ifrit's Fuse; Floe has no such dependency, so diffScore here derives the same kind of
//  score from Floe's own Fuzzy matcher in Ranking.swift.

// MARK: - SearchWeights

/// Field weights for the settings search.
///
/// A diff score gets worse (higher) as weight increases, so a lower weight means a match in
/// that field ranks the result higher.
struct SearchWeights {
    let title: Double
    let keywords: Double
    let description: Double

    /// A title match ranks above a keywords match, which ranks above a description match.
    static let settings = SearchWeights(title: 0.3, keywords: 0.6, description: 1.0)
}

// MARK: - SearchRanker

enum SearchRanker {
    /// Fuzzy's score for a query found inside a candidate as one run of characters. Anything
    /// lower is a scattered subsequence, which the root search accepts for app names but is
    /// too loose here: a few letters appear in order in almost any setting's title or description.
    static let substringScore = 55

    /// How far an entry is from the query: 0.3 for a title that starts with it, growing with
    /// weaker matches and less important fields. Nil means the entry does not match.
    ///
    /// The whole query is tried first. If it matches nowhere, each of its words must match
    /// some field, and the weakest word decides the score, so "raycast extensions" still finds
    /// "Include extensions installed in Raycast".
    static func diffScore(
        query: String,
        title: String,
        keywords: [String],
        description: String?,
        weights: SearchWeights = .settings
    ) -> Double? {
        func best(_ text: String) -> Double? {
            var candidates = [wordScore(text, title).map { diff($0, weight: weights.title) }]
            candidates += keywords.map { keyword in wordScore(text, keyword).map { diff($0, weight: weights.keywords) } }
            if let description {
                candidates.append(wordScore(text, description).map { diff($0, weight: weights.description) })
            }
            return candidates.compactMap(\.self).min()
        }
        if let whole = best(query) {
            return whole
        }
        let words = query.split(separator: " ").map(String.init)
        guard words.count > 1 else { return nil }
        let perWord = words.map(best)
        guard !perWord.contains(where: { $0 == nil }) else { return nil }
        return perWord.compactMap(\.self).max()
    }

    /// Fuzzy's score without its subsequence fallback.
    private static func wordScore(_ query: String, _ candidate: String) -> Int? {
        Fuzzy.score(query, candidate).flatMap { $0 >= substringScore ? $0 : nil }
    }

    /// Turns Fuzzy's score (higher is better, 100 at most) into a diff score (lower is better),
    /// scaled so every match in one field ranks ahead of every match in the next.
    private static func diff(_ score: Int, weight: Double) -> Double {
        weight * (2 - Double(score) / 100)
    }

    /// Pure relevance sort: a diff score is lowest for the best match and grows with worse ones.
    ///
    /// Equal scores keep their input order. sorted(by:) is not documented as stable, and ties
    /// are common, so without the tiebreak results could permute between runs.
    static func sortedByRelevance<T>(_ items: [(item: T, diffScore: Double)]) -> [T] {
        items.enumerated()
            .sorted { lhs, rhs in
                lhs.element.diffScore == rhs.element.diffScore
                    ? lhs.offset < rhs.offset
                    : lhs.element.diffScore < rhs.element.diffScore
            }
            .map(\.element.item)
    }
}
