//
//  RankingTests.swift
//  Project: Floe
//
//  Copyright (Floe) © 2026 René Jiménez
//  Licensed under the GNU GPLv3

@testable import Floe
import Foundation
import Testing

struct FuzzyTests {
    @Test func prefixBeatsWordPrefixBeatsAcronymBeatsSubstringBeatsSubsequence() throws {
        let prefix = try #require(Fuzzy.score("saf", "Safari"))
        let wordPrefix = try #require(Fuzzy.score("mon", "Activity Monitor"))
        let acronym = try #require(Fuzzy.score("vsc", "Visual Studio Code"))
        let substring = try #require(Fuzzy.score("tivi", "Activity Monitor"))
        let subsequence = try #require(Fuzzy.score("sfr", "Safari"))
        #expect(prefix > wordPrefix)
        #expect(wordPrefix > acronym)
        #expect(acronym > substring)
        #expect(substring > subsequence)
    }

    @Test(arguments: [("xyz", "Safari"), ("iras", "Safari"), ("safarii", "Safari")])
    func charactersOutOfOrderOrMissingDoNotMatch(query: String, candidate: String) {
        #expect(Fuzzy.score(query, candidate) == nil)
    }

    @Test func matchingIgnoresCase() {
        #expect(Fuzzy.score("SAF", "safari") == Fuzzy.score("saf", "Safari"))
    }

    @Test func shorterCandidateWinsForTheSamePrefix() throws {
        let short = try #require(Fuzzy.score("cal", "Calendar"))
        let long = try #require(Fuzzy.score("cal", "Calculator and More Things"))
        #expect(short > long)
    }

    @Test func prefixPenaltyStopsAtTwentyCharacters() {
        let padded = "a" + String(repeating: "b", count: 60)
        #expect(Fuzzy.score("a", padded) == 80)
    }
}

struct RankingTests {
    private let items: [RootItem] = [
        .command(Fixture.command("frontpage", extension: "hacker-news", title: "Hacker News")),
        .command(Fixture.command("planets", extension: "hello", title: "Browse Planets")),
        Fixture.app("Calculator"),
        Fixture.app("Calendar"),
        Fixture.app("Notes"),
        .menuBarSearch,
        .settings,
    ]

    private func id(_ title: String) -> String {
        items.first { $0.title == title }!.id
    }

    @Test(arguments: [
        (0.0, 4.0),
        (3599, 4),
        (3600, 2),
        (86399, 2),
        (86400, 1),
        (604_799, 1),
        (604_800, 0.5),
        (2_591_999, 0.5),
        (2_592_000, 0.25),
        (1e9, 0.25)
    ])
    func frecencyWeightFallsOffWithAge(age: TimeInterval, weight: Double) {
        #expect(Ranking.frecency(count: 1, age: age) == weight)
        #expect(Ranking.frecency(count: 3, age: age) == weight * 3)
    }

    @Test func exactAliasOutranksEverything() {
        #expect(Ranking.score(query: "hn", title: "Hacker News", alias: "hn") == 1000)
        #expect(Ranking.score(query: "HN", title: "Hacker News", alias: "hn") == 1000, "aliases match without regard to case")
    }

    @Test func aliasPrefixRanksAtLeastAsWellAsATitlePrefix() {
        #expect(Ranking.score(query: "ca", title: "Zebra", alias: "cal") == 95)
        #expect(Ranking.score(query: "ca", title: "Ca", alias: "cal") == 100, "a better title score is kept")
    }

    @Test func aliasThatDoesNotMatchFallsBackToTheTitle() {
        #expect(Ranking.score(query: "saf", title: "Safari", alias: "web") == Fuzzy.score("saf", "Safari"))
        #expect(Ranking.score(query: "saf", title: "Safari", alias: "") == Fuzzy.score("saf", "Safari"))
        #expect(Ranking.score(query: "zzz", title: "Safari", alias: nil) == nil)
    }

    @Test func browsingListsFavoritesThenSuggestionsThenCommandsThenApplications() {
        let usage = [id("Calendar"): 5.0, id("Hacker News"): 2.0]
        let results = Ranking.browse(items, favorites: [id("Notes")], frecency: { usage[$0] ?? 0 })

        #expect(results.map(\.item.title) == [
            "Notes",
            "Calendar",
            "Hacker News",
            "Browse Planets",
            "Search Menu Bar Items",
            "Floe Settings",
            "Calculator",
        ])
        #expect(results.map(\.section) == ["Favorites", "Suggestions", "Suggestions", "Commands", "Commands", "Commands", "Applications"])
    }

    @Test func browsingKeepsFavoritesInTheirSavedOrderAndOutOfSuggestions() {
        let favorites = [id("Calendar"), id("Notes"), "app:/Applications/Gone.app"]
        let results = Ranking.browse(items, favorites: favorites, frecency: { $0 == self.id("Calendar") ? 9 : 0 })

        #expect(results.prefix(2).map(\.item.title) == ["Calendar", "Notes"])
        #expect(results.filter { $0.section == "Suggestions" }.isEmpty, "a favorite is not suggested again")
        #expect(results.count == items.count, "a favorite that no longer exists is dropped, nothing else")
    }

    @Test func browsingSuggestsAtMostFiveItems() {
        let results = Ranking.browse(items, favorites: [], frecency: { _ in 1 })
        #expect(results.filter { $0.section == "Suggestions" }.count == 5)
    }

    @Test func searchingOrdersByMatchThenUsage() {
        let unused = Ranking.search(items, query: "cal", favorites: [], alias: { _ in nil }, frecency: { _ in 0 })
        #expect(unused.map(\.item.title) == ["Calendar", "Calculator"])
        #expect(unused.allSatisfy { $0.section == nil })

        let usage = [id("Calculator"): 6.0]
        let used = Ranking.search(items, query: "cal", favorites: [], alias: { _ in nil }, frecency: { usage[$0] ?? 0 })
        #expect(used.map(\.item.title) == ["Calculator", "Calendar"])
    }

    @Test func usageBoostIsCappedSoAnExactAliasStillWins() {
        let results = Ranking.search(
            items,
            query: "c",
            favorites: [],
            alias: { $0.title == "Hacker News" ? "c" : nil },
            frecency: { $0 == self.id("Calculator") ? 1_000_000 : 0 }
        )
        #expect(results.first?.item.title == "Hacker News")
    }

    @Test func favoritesGetASmallBoostInSearch() {
        let results = Ranking.search(items, query: "cal", favorites: [id("Calculator")], alias: { _ in nil }, frecency: { _ in 0 })
        #expect(results.map(\.item.title) == ["Calculator", "Calendar"])
    }

    @Test func searchRespectsTheLimit() {
        let many = (0 ..< 60).map { Fixture.app("App \($0)") }
        #expect(Ranking.search(many, query: "app", favorites: [], alias: { _ in nil }, frecency: { _ in 0 }).count == 40)
        #expect(Ranking.search(many, query: "app", favorites: [], alias: { _ in nil }, frecency: { _ in 0 }, limit: 3).count == 3)
    }

    @Test func menuBarItemsMatchOnNameAndLessStronglyOnOwner() throws {
        let byName = try #require(Ranking.menuBarScore(query: "tail", name: "Tailscale", owner: "Tailscale"))
        let byOwner = try #require(Ranking.menuBarScore(query: "codex", name: "Usage 86%", owner: "CodexBar"))
        #expect(byName > byOwner)
        #expect(byOwner == Fuzzy.score("codex", "CodexBar")! - 10)
        #expect(Ranking.menuBarScore(query: "zzz", name: "Tailscale", owner: "Tailscale") == nil)
    }
}
