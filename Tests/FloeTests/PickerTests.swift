//
//  PickerTests.swift
//  Project: Floe
//
//  Copyright (Floe) © 2026 René Jiménez
//  Licensed under the GNU AGPLv3

@testable import Floe
import Foundation
import Testing

struct PickListTests {
    private func texts(_ items: [PickItem]) -> [String] {
        items.map(\.text)
    }

    @Test func eachLineOfTheInputIsAnItem() {
        let items = PickList.items(from: "alpha\nbeta\ngamma\n")
        #expect(texts(items) == ["alpha", "beta", "gamma"])
        #expect(items.map(\.index) == [0, 1, 2])
    }

    @Test func blankLinesAreDroppedAndTheOthersKeepTheirPlaceInTheInput() {
        let items = PickList.items(from: "alpha\n\n   \nbeta\n\t\ngamma")
        #expect(texts(items) == ["alpha", "beta", "gamma"])
        #expect(items.map(\.index) == [0, 3, 5])
    }

    @Test func aLineKeepsItsOwnSpaces() {
        #expect(texts(PickList.items(from: "  two words  \n")) == ["  two words  "])
    }

    @Test func windowsLineEndingsSplitLikeAnyOther() {
        #expect(texts(PickList.items(from: "alpha\r\nbeta\r\n")) == ["alpha", "beta"])
    }

    @Test(arguments: ["", "\n", "\n\n  \n"])
    func inputWithNothingButBlankLinesHasNoItems(input: String) {
        #expect(PickList.items(from: input).isEmpty)
    }

    @Test func anEmptyQueryListsEverythingInInputOrder() {
        let items = PickList.items(from: "zeta\nalpha\nmid")
        #expect(PickList.matches(items, query: "") == items)
    }

    @Test func aQueryKeepsOnlyWhatMatchesBestFirst() {
        let items = PickList.items(from: "my notes\nnotes\nphotos\nkeynote")
        #expect(texts(PickList.matches(items, query: "note")) == ["notes", "my notes", "keynote"])
    }

    @Test func equalScoresKeepInputOrder() {
        let items = PickList.items(from: "bcd\nacd\nxcd\nccd")
        // All four only contain "cd", so nothing but their place in the input tells them apart.
        #expect(texts(PickList.matches(items, query: "cd")) == ["bcd", "acd", "xcd", "ccd"])
    }

    @Test func aQueryThatMatchesNothingLeavesNothing() {
        #expect(PickList.matches(PickList.items(from: "alpha\nbeta"), query: "xyz").isEmpty)
    }

    @Test func tenThousandLinesAreFilteredInInputOrder() {
        let items = PickList.items(from: (0 ..< 10000).map { "item \($0)" }.joined(separator: "\n"))
        let matches = PickList.matches(items, query: "item 99")
        #expect(items.count == 10000)
        #expect(matches.prefix(4).map(\.text) == ["item 99", "item 990", "item 991", "item 992"])
        #expect(matches.count < items.count)
    }

    @Test func aChoicePrintsItsTextOrItsPlaceInTheInput() {
        let item = PickItem(index: 3, text: "beta")
        #expect(PickList.output(for: item, printsIndex: false) == "beta")
        #expect(PickList.output(for: item, printsIndex: true) == "3")
    }

    @Test(arguments: [(0, 1, 1), (0, -1, 0), (3, 9, 4), (4, 1, 4), (2, Int.max / 2, 4), (2, -(Int.max / 2), 0)])
    func theSelectionStaysInsideTheList(from: Int, delta: Int, expected: Int) {
        #expect(PickList.selection(from, movedBy: delta, count: 5) == expected)
    }

    @Test func theSelectionOfAnEmptyListIsTheFirstRow() {
        #expect(PickList.selection(0, movedBy: 1, count: 0) == 0)
    }

    @Test func theCountSaysHowMuchOfTheInputStillMatches() {
        #expect(PickList.countLabel(shown: 1, total: 1, isFiltered: false) == "1 item")
        #expect(PickList.countLabel(shown: 12, total: 12, isFiltered: false) == "12 items")
        #expect(PickList.countLabel(shown: 3, total: 12, isFiltered: true) == "3 of 12")
    }

    @Test func theExitCodesAreTheOnesScriptsRelyOn() {
        #expect(PickExit.chosen.rawValue == 0)
        #expect(PickExit.cancelled.rawValue == 1)
        #expect(PickExit.usage.rawValue == 64)
    }
}

struct PickSessionTests {
    private func makeSession(_ input: String, query: String = "") -> PickSession {
        PickSession(items: PickList.items(from: input), prompt: "Pick", query: query)
    }

    @Test func theStartingQueryFiltersBeforeAnythingIsTyped() {
        let session = makeSession("alpha\nbeta\ngamma", query: "ga")
        #expect(session.results.map(\.text) == ["gamma"])
        #expect(session.selected?.text == "gamma")
    }

    @Test func typingMovesTheSelectionBackToTheBestMatch() {
        let session = makeSession("alpha\nbeta\ngamma")
        session.move(by: 2)
        #expect(session.selected?.text == "gamma")
        session.query = "a"
        #expect(session.selected?.text == "alpha")
    }

    @Test func choosingHandsOverTheSelectedItem() {
        let session = makeSession("alpha\nbeta")
        var chosen: [PickItem?] = []
        session.finish = { chosen.append($0) }
        session.move(by: 1)
        session.choose()
        #expect(chosen == [PickItem(index: 1, text: "beta")])
    }

    @Test func choosingWithNothingMatchingDoesNothing() {
        let session = makeSession("alpha\nbeta", query: "xyz")
        var finished = false
        session.finish = { _ in finished = true }
        session.choose()
        #expect(session.selected == nil)
        #expect(finished == false)
    }

    @Test func clickingARowSelectsIt() {
        let session = makeSession("alpha\nbeta\ngamma")
        session.select(PickItem(index: 2, text: "gamma"))
        #expect(session.selection == 2)
    }
}
