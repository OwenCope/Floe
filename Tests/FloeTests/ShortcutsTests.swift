//
//  ShortcutsTests.swift
//  Project: Floe
//
//  Copyright (Floe) © 2026 René Jiménez
//  Licensed under the GNU AGPLv3

import AppKit
@testable import Floe
import Testing

struct ShortcutsTests {
    @Test(arguments: [(125, 1), (126, -1), (121, 9), (116, -9)] as [(UInt16, Int)])
    func arrowAndPageKeysMoveTheSelection(keyCode: UInt16, delta: Int) {
        #expect(Shortcuts.navigationDelta(keyCode) == delta)
    }

    @Test func homeAndEndJumpFarEnoughToReachEitherEndWithoutOverflowing() throws {
        let end = try #require(Shortcuts.navigationDelta(119))
        let home = try #require(Shortcuts.navigationDelta(115))
        #expect(end > 1_000_000)
        #expect(home < -1_000_000)
        #expect(ViewState.clamp(5 + end, count: 10) == 9)
        #expect(ViewState.clamp(5 + home, count: 10) == 0)
    }

    @Test(arguments: [36, 53, 40, 0] as [UInt16])
    func otherKeysAreNotNavigation(keyCode: UInt16) {
        #expect(Shortcuts.navigationDelta(keyCode) == nil)
    }

    @Test func modifierNamesMapToFlags() {
        #expect(Shortcuts.flags(["cmd", "shift"]) == [.command, .shift])
        #expect(Shortcuts.flags(["opt"]) == .option)
        #expect(Shortcuts.flags(["alt"]) == .option)
        #expect(Shortcuts.flags(["ctrl"]) == .control)
        #expect(Shortcuts.flags(["hyper"]).isEmpty)
        #expect(Shortcuts.flags([]).isEmpty)
    }

    @Test func aShortcutMatchesItsKeyWithExactlyItsModifiers() {
        let copy: [String: Any] = ["modifiers": ["cmd", "shift"], "key": "c"]
        #expect(Shortcuts.matches(copy, key: "c", flags: [.command, .shift]))
        #expect(Shortcuts.matches(copy, key: "C", flags: [.command, .shift]), "the key is compared without regard to case")
        #expect(Shortcuts.matches(copy, key: "c", flags: .command) == false)
        #expect(Shortcuts.matches(copy, key: "c", flags: [.command, .shift, .option]) == false)
        #expect(Shortcuts.matches(copy, key: "x", flags: [.command, .shift]) == false)
        #expect(Shortcuts.matches(copy, key: nil, flags: [.command, .shift]) == false)
    }

    @Test func aShortcutWithoutModifiersMatchesTheBareKey() {
        #expect(Shortcuts.matches(["key": "r"], key: "r", flags: []))
    }

    @Test(arguments: [nil, "cmd+c", ["modifiers": ["cmd"]]] as [Any?])
    func malformedShortcutsNeverMatchAndHaveNoLabel(shortcut: Any?) {
        #expect(Shortcuts.matches(shortcut, key: "c", flags: .command) == false)
        #expect(Shortcuts.label(shortcut) == nil)
    }

    @Test func labelsShowModifierSymbolsThenTheKey() {
        #expect(Shortcuts.label(["modifiers": ["cmd", "shift"], "key": "c"]) == "⌘⇧C")
        #expect(Shortcuts.label(["modifiers": ["ctrl", "opt"], "key": "x"]) == "⌃⌥X")
        #expect(Shortcuts.label(["modifiers": ["alt", "unknown"], "key": "k"]) == "⌥K")
        #expect(Shortcuts.label(["key": "r"]) == "R")
    }
}
