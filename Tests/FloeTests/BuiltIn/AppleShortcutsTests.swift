//
//  AppleShortcutsTests.swift
//  Project: Floe
//
//  Copyright (Floe) © 2026 René Jiménez
//  Licensed under the GNU AGPLv3

@testable import Floe
import Foundation
import os
import Testing

/// Holds callers back until a test lets them through, one per `open`.
private final class Gate: Sendable {
    private struct State {
        var permits = 0
        var waiting: [CheckedContinuation<Void, Never>] = []
    }

    private let state = OSAllocatedUnfairLock(initialState: State())

    func wait() async {
        await withCheckedContinuation { continuation in
            let mayPass = state.withLock { state in
                guard state.permits > 0 else {
                    state.waiting.append(continuation)
                    return false
                }
                state.permits -= 1
                return true
            }
            if mayPass {
                continuation.resume()
            }
        }
    }

    func open() {
        let next = state.withLock { state -> CheckedContinuation<Void, Never>? in
            guard !state.waiting.isEmpty else {
                state.permits += 1
                return nil
            }
            return state.waiting.removeFirst()
        }
        next?.resume()
    }
}

/// A Shortcuts tool that runs nothing: it writes down what it was asked and answers from a script.
/// With a gate, every call waits until the test opens it.
final class FakeShortcutsTool: Sendable {
    static let listing = ["list", "--show-identifiers"]

    private let log = OSAllocatedUnfairLock(initialState: [[String]]())
    private let answers: OSAllocatedUnfairLock<[String: ShortcutsToolResult]>
    private let asked = AsyncStream.makeStream(of: [String].self)
    private let gate: Gate?

    init(list: String = "", isGated: Bool = false) {
        answers = OSAllocatedUnfairLock(initialState: ["list": ShortcutsToolResult(succeeded: true, output: list)])
        gate = isGated ? Gate() : nil
    }

    var calls: [[String]] {
        log.withLock(\.self)
    }

    /// Each call as it starts, for a test that waits for one.
    var started: AsyncStream<[String]> {
        asked.stream
    }

    var tool: ShortcutsTool {
        ShortcutsTool { [self] arguments in
            log.withLock { $0.append(arguments) }
            asked.continuation.yield(arguments)
            await gate?.wait()
            return answers.withLock { $0[arguments.first ?? ""] } ?? ShortcutsToolResult(succeeded: true)
        }
    }

    /// What the tool says the next time it is asked for this subcommand.
    func answer(_ subcommand: String, with result: ShortcutsToolResult) {
        answers.withLock { $0[subcommand] = result }
    }

    func list(_ text: String) {
        answer("list", with: ShortcutsToolResult(succeeded: true, output: text))
    }

    /// Lets one waiting call through.
    func open() {
        gate?.open()
    }
}

enum ShortcutSample {
    static let mailID = "0C9A4E0B-2B0F-4B55-9C3F-0D1B5A6E7F01"
    static let focusID = "7E1D2C3B-4A5F-4E6D-8C7B-9A0F1E2D3C4B"
    static let resizeID = "A1B2C3D4-E5F6-4A7B-8C9D-0E1F2A3B4C5D"

    static let mail = AppleShortcut(name: "Mail Me the Notes", identifier: mailID)
    static let focus = AppleShortcut(name: "Keyboard Focus", identifier: focusID)
    static let resize = AppleShortcut(name: "Resize Image (Half)", identifier: resizeID)
    static let all = [mail, focus, resize]

    static let listing = all.map { "\($0.name) (\($0.identifier))" }.joined(separator: "\n") + "\n"
}

struct AppleShortcutListTests {
    @Test func aPlainNameIsReadWithItsIdentifier() {
        let parsed = AppleShortcutList.parse("Morning Routine (\(ShortcutSample.mailID))\n")
        #expect(parsed == [AppleShortcut(name: "Morning Routine", identifier: ShortcutSample.mailID)])
        #expect(parsed.first?.id == "shortcut:\(ShortcutSample.mailID)")
    }

    @Test func theIdentifierIsTheLastPairOfParentheses() {
        let parsed = AppleShortcutList.parse("Resize Image (Half) (\(ShortcutSample.resizeID))\nA (b) (c) d) (\(ShortcutSample.focusID))")
        #expect(parsed.map(\.name) == ["Resize Image (Half)", "A (b) (c) d)"])
        #expect(parsed.map(\.identifier) == [ShortcutSample.resizeID, ShortcutSample.focusID])
    }

    @Test func aNameThatIsItselfAnIdentifierInParenthesesKeepsIt() {
        let parsed = AppleShortcutList.parse("(\(ShortcutSample.mailID)) (\(ShortcutSample.focusID))")
        #expect(parsed == [AppleShortcut(name: "(\(ShortcutSample.mailID))", identifier: ShortcutSample.focusID)])
    }

    @Test func emojiAndOtherPunctuationStayInTheName() {
        let parsed = AppleShortcutList.parse("☕️ Café: 50% off, \"today\"! (\(ShortcutSample.mailID))\n日本語 (\(ShortcutSample.focusID))")
        #expect(parsed.map(\.name) == ["☕️ Café: 50% off, \"today\"!", "日本語"])
    }

    @Test func spacesAroundTheNameAndAfterTheIdentifierAreDropped() {
        let parsed = AppleShortcutList.parse("  Padded Name   (\(ShortcutSample.mailID))  \t\r\n")
        #expect(parsed == [AppleShortcut(name: "Padded Name", identifier: ShortcutSample.mailID)])
    }

    @Test(arguments: ["", "\n\n", "   \n"])
    func anEmptyListHasNoShortcuts(output: String) {
        #expect(AppleShortcutList.parse(output).isEmpty)
    }

    @Test func aLineWithoutAnIdentifierIsLeftOut() {
        let output = """
        Just a Name
        Resize Image (Half)
        Not an identifier (1234)
        (\(ShortcutSample.focusID))
        Kept (\(ShortcutSample.mailID))
        """
        #expect(AppleShortcutList.parse(output) == [AppleShortcut(name: "Kept", identifier: ShortcutSample.mailID)])
    }

    @Test func twoShortcutsWithOneNameAreBothKept() {
        let parsed = AppleShortcutList.parse("Twin (\(ShortcutSample.mailID))\nTwin (\(ShortcutSample.focusID))\nTwin (\(ShortcutSample.mailID))")
        #expect(parsed.map(\.name) == ["Twin", "Twin"])
        #expect(parsed.map(\.identifier) == [ShortcutSample.mailID, ShortcutSample.focusID], "one row per identifier")
        #expect(Set(parsed.map(\.id)).count == 2)
    }

    @Test func theOrderIsTheTools() {
        #expect(AppleShortcutList.parse(ShortcutSample.listing) == ShortcutSample.all)
    }
}

struct ShortcutsToolTests {
    @Test func theSystemToolIsTheOneThatComesWithMacOS() {
        #expect(ShortcutsTool.path == "/usr/bin/shortcuts")
    }

    @Test func listingAsksForIdentifiers() async {
        let fake = FakeShortcutsTool(list: ShortcutSample.listing)
        #expect(await fake.tool.list() == ShortcutSample.all)
        #expect(fake.calls == [["list", "--show-identifiers"]])
    }

    @Test func aListThatCouldNotBeReadIsNotAnEmptyOne() async {
        let fake = FakeShortcutsTool()
        fake.answer("list", with: ShortcutsToolResult(succeeded: false, errorOutput: "no such tool"))
        #expect(await fake.tool.list() == nil)
    }

    @Test func aRunNamesTheShortcutByItsIdentifierAndPassesNothingElse() async {
        let fake = FakeShortcutsTool()
        #expect(await fake.tool.run(ShortcutSample.resize) == nil, "a run that worked has nothing to say")
        #expect(fake.calls == [["run", ShortcutSample.resizeID]])
    }

    @Test func whatAShortcutPrintsIsNotShown() async {
        let fake = FakeShortcutsTool()
        fake.answer("run", with: ShortcutsToolResult(succeeded: true, output: "42\n", errorOutput: "a warning\n"))
        #expect(await fake.tool.run(ShortcutSample.mail) == nil)
    }

    @Test func aFailedRunSaysTheToolsLastLine() async {
        let fake = FakeShortcutsTool()
        fake.answer("run", with: ShortcutsToolResult(succeeded: false, errorOutput: "Starting\nError: The file could not be found.\n\n  \n"))
        #expect(await fake.tool.run(ShortcutSample.mail) == "Mail Me the Notes failed: Error: The file could not be found.")
    }

    @Test func aFailedRunWithoutALineSaysWhereToLook() async {
        let fake = FakeShortcutsTool()
        fake.answer("run", with: ShortcutsToolResult(succeeded: false))
        #expect(await fake.tool.run(ShortcutSample.mail) == "Mail Me the Notes failed. Open it in Shortcuts to see why.")
    }

    @Test func aLongLastLineIsCut() {
        let long = String(repeating: "x", count: 500)
        #expect(ShortcutsTool.lastLine("first\n\(long)\n") == String(repeating: "x", count: ShortcutsTool.failureLimit) + "…")
        #expect(ShortcutsTool.lastLine("short") == "short")
        #expect(ShortcutsTool.lastLine(" \n\n") == nil)
    }

    @Test func viewingNamesTheShortcutAfterTheEndOfTheOptions() async {
        let fake = FakeShortcutsTool()
        let dashed = AppleShortcut(name: "--help", identifier: ShortcutSample.mailID)
        #expect(await fake.tool.view(dashed) == nil)
        #expect(fake.calls == [["view", "--", "--help"]])
        fake.answer("view", with: ShortcutsToolResult(succeeded: false, errorOutput: "Error: not found\n"))
        #expect(await fake.tool.view(ShortcutSample.mail) == "Couldn't open Mail Me the Notes in Shortcuts: Error: not found")
        fake.answer("view", with: ShortcutsToolResult(succeeded: false))
        #expect(await fake.tool.view(ShortcutSample.mail) == "Couldn't open Mail Me the Notes in Shortcuts. Open the Shortcuts app and look for it there.")
    }
}

@MainActor
struct AppleShortcutLibraryTests {
    private func library(_ fake: FakeShortcutsTool) -> AppleShortcutLibrary {
        let library = AppleShortcutLibrary()
        library.tool = fake.tool
        return library
    }

    @Test func nothingIsReadUntilItIsAskedFor() {
        let fake = FakeShortcutsTool(list: ShortcutSample.listing)
        #expect(library(fake).shortcuts.isEmpty)
        #expect(fake.calls.isEmpty)
    }

    @Test func offMeansTheToolIsNeverStarted() {
        let fake = FakeShortcutsTool(list: ShortcutSample.listing)
        let library = library(fake)
        var changes = 0
        #expect(library.refresh(isOn: false) { changes += 1 } == nil)
        #expect(library.refresh(isOn: false) { changes += 1 } == nil)
        #expect(library.shortcuts.isEmpty)
        #expect(fake.calls.isEmpty)
        #expect(changes == 0)
    }

    @Test func aRefreshReadsTheListAndSaysWhenItChanged() async {
        let fake = FakeShortcutsTool(list: ShortcutSample.listing)
        let library = library(fake)
        var changes = 0
        await library.refresh(isOn: true) { changes += 1 }?.value
        #expect(library.shortcuts == ShortcutSample.all)
        #expect(changes == 1)
        await library.refresh(isOn: true) { changes += 1 }?.value
        #expect(changes == 1, "the same list again is no change")
        #expect(fake.calls == [FakeShortcutsTool.listing, FakeShortcutsTool.listing])
    }

    @Test func theLastListIsKeptWhileTheNextOneIsOnItsWayAndOnlyOneIsAskedFor() async {
        let fake = FakeShortcutsTool(list: ShortcutSample.listing, isGated: true)
        let library = library(fake)
        fake.open()
        await library.refresh(isOn: true) { /* the first list */ }?.value
        fake.list("Only One (\(ShortcutSample.mailID))\n")

        let first = library.refresh(isOn: true) { /* the second list */ }
        let second = library.refresh(isOn: true) { /* never asked */ }
        #expect(first == second, "a request that is on its way is not doubled")
        #expect(library.shortcuts == ShortcutSample.all, "the search reads the list it has")
        fake.open()
        await first?.value
        #expect(library.shortcuts.map(\.name) == ["Only One"])
        #expect(fake.calls.count == 2)
    }

    @Test func aListThatCouldNotBeReadLeavesTheLastOneInPlace() async {
        let fake = FakeShortcutsTool(list: ShortcutSample.listing)
        let library = library(fake)
        await library.refresh(isOn: true) { /* the first list */ }?.value
        fake.answer("list", with: ShortcutsToolResult(succeeded: false, errorOutput: "busy"))
        var changes = 0
        await library.refresh(isOn: true) { changes += 1 }?.value
        #expect(library.shortcuts == ShortcutSample.all)
        #expect(changes == 0)
    }

    @Test func switchingOffEmptiesTheListAndDropsOneThatIsOnItsWay() async {
        let fake = FakeShortcutsTool(list: ShortcutSample.listing, isGated: true)
        let library = library(fake)
        var changes = 0
        let loading = library.refresh(isOn: true) { changes += 1 }
        #expect(library.refresh(isOn: false) { changes += 1 } == nil)
        fake.open()
        await loading?.value
        #expect(library.shortcuts.isEmpty, "a list that arrives after the switch went off is not kept")
        #expect(changes == 0)

        fake.open()
        await library.refresh(isOn: true) { changes += 1 }?.value
        #expect(library.shortcuts == ShortcutSample.all, "switched on again, it is read again")
    }

    @Test func aRunThatWorksShowsNothing() async {
        let fake = FakeShortcutsTool()
        var lines: [String] = []
        await library(fake).run(ShortcutSample.mail) { lines.append($0) }.value
        #expect(lines.isEmpty)
        #expect(fake.calls == [["run", ShortcutSample.mailID]])
    }

    @Test func aRunThatFailsShowsTheLastErrorLine() async {
        let fake = FakeShortcutsTool()
        fake.answer("run", with: ShortcutsToolResult(succeeded: false, errorOutput: "Error: The shortcut was cancelled.\n"))
        var lines: [String] = []
        await library(fake).run(ShortcutSample.focus) { lines.append($0) }.value
        #expect(lines == ["Keyboard Focus failed: Error: The shortcut was cancelled."])
    }

    @Test func twoRunsOfOneShortcutGoOnAtTheSameTime() async {
        let fake = FakeShortcutsTool(isGated: true)
        let library = library(fake)
        let first = library.run(ShortcutSample.mail) { _ in /* nothing fails */ }
        let second = library.run(ShortcutSample.mail) { _ in /* nothing fails */ }
        var started = fake.started.makeAsyncIterator()
        #expect(await started.next() == ["run", ShortcutSample.mailID])
        #expect(await started.next() == ["run", ShortcutSample.mailID], "the second started while the first was still running")
        fake.open()
        fake.open()
        await first.value
        await second.value
        #expect(fake.calls.count == 2)
    }
}
