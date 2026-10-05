//
//  QuicklinkSearchProvider.swift
//  Project: Floe
//
//  Copyright (Floe) © 2026 René Jiménez
//  Licensed under the GNU AGPLv3

import Foundation

/// Quicklinks three ways: by name or keyword among the ranked rows, as `keyword rest` on top,
/// and as fallbacks at the bottom.
struct QuicklinkSearchProvider: SearchProvider {
    func contribution(for context: SearchContext) -> SearchContribution {
        let text = context.trimmed
        guard !text.isEmpty else { return SearchContribution() }
        let links = context.quicklinks
        return SearchContribution(
            // Names and keywords rank alongside everything else, through the keyword alias.
            ranked: links.map { RootItem.quicklink($0, queryText: text, fallback: false, keywordSearch: false) },
            pinned: Self.keywordSearchResult(query: text, links: links).map { [$0] } ?? [],
            // Enabled fallbacks in user order.
            appended: links.filter(\.isFallback).map { link in
                RootResult(item: .quicklink(link, queryText: text, fallback: true, keywordSearch: false), section: String(localized: "Fallbacks", bundle: .floe, comment: "A section title above the searches offered when nothing else matches."))
            }
        )
    }

    /// The `keyword rest` row for a query starting with a quicklink's keyword and a space, if any:
    /// `gh floe` offers Search GitHub for "floe" first.
    static func keywordSearchResult(query: String, links: [Quicklink]) -> RootResult? {
        guard let match = links.first(where: { query.hasPrefix($0.keyword + " ") }) else { return nil }
        let rest = String(query.dropFirst(match.keyword.count + 1))
        return RootResult(item: .quicklink(match, queryText: rest, fallback: false, keywordSearch: true), section: nil)
    }
}
