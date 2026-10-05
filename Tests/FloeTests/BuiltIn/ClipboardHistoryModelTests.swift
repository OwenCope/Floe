//
//  ClipboardHistoryModelTests.swift
//  Project: Floe
//
//  Copyright (Floe) © 2026 René Jiménez
//  Licensed under the GNU AGPLv3

import AppKit
@testable import Floe
import Testing

@MainActor
@Suite("Clipboard history view state")
final class ClipboardHistoryModelTests {
    private let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent("floe-clipboard-model-tests-\(UUID().uuidString)", isDirectory: true)
    private let scratch = UserDefaults(suiteName: "floe-clipboard-model-tests-\(UUID().uuidString)")!
    private lazy var store = ClipboardHistoryStore(files: .onDisk(directory), monitorsPasteboard: false)

    deinit {
        try? FileManager.default.removeItem(at: directory)
    }

    /// A model over a scratch store that holds the given copies, oldest first.
    private func makeModel(_ copies: [String] = ["alpha", "beta", "gamma"]) async -> ClipboardHistoryModel {
        for (index, copy) in copies.enumerated() {
            store.record(ClipboardCapture(content: .text(copy), date: Date(timeIntervalSince1970: TimeInterval(index + 1)), sourceApp: "Tests"))
        }
        for _ in 0 ..< 5000 where store.entries.count < copies.count {
            try? await Task.sleep(for: .milliseconds(1))
        }
        return ClipboardHistoryModel(usage: UsageStore(defaults: scratch)) { [store] in store }
    }

    private func key(_ code: UInt16) throws -> NSEvent {
        try #require(NSEvent.keyEvent(
            with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0, windowNumber: 0, context: nil,
            characters: "", charactersIgnoringModifiers: "", isARepeat: false, keyCode: code
        ))
    }

    @Test func theEntriesAreNewestFirstAndAQueryNarrowsThemAndResetsTheSelection() async {
        let model = await makeModel()
        #expect(model.filteredEntries().map(\.text) == ["gamma", "beta", "alpha"])
        model.selection = 2
        #expect(model.selectedEntry?.text == "alpha")
        model.query = "bet"
        #expect(model.filteredEntries().map(\.text) == ["beta"])
        #expect(model.selection == 0)
        #expect(model.selectedEntry?.text == "beta")
    }

    @Test func theArrowsMoveTheSelectionAndStopAtTheEnds() async throws {
        let model = await makeModel()
        #expect(try model.handleKey(key(126)))
        #expect(model.selection == 0)
        for _ in 0 ..< 5 {
            #expect(try model.handleKey(key(125)))
        }
        #expect(model.selection == 2)
        #expect(try !model.handleKey(key(0)), "a letter goes on to the search field")
    }

    @Test func deleteRemovesTheSelectedCopyAndKeepsTheSelectionInsideTheList() async throws {
        let model = await makeModel()
        model.selection = 2
        #expect(try model.handleKey(key(51)))
        #expect(model.filteredEntries().map(\.text) == ["gamma", "beta"])
        #expect(model.selection == 1)
    }

    @Test func pinningACopyPutsItFirst() async throws {
        let model = await makeModel()
        model.selection = 2
        try model.togglePin(#require(model.selectedEntry))
        #expect(model.filteredEntries().map(\.text) == ["alpha", "gamma", "beta"])
    }

    @Test func escapeClearsAQueryFirstAndOnlyThenLeavesTheHistory() async throws {
        let model = await makeModel([])
        var closed = 0
        model.host.close = { closed += 1 }
        model.query = "bet"
        #expect(try model.handleKey(key(53)))
        #expect(model.query.isEmpty)
        #expect(closed == 0)
        #expect(try model.handleKey(key(53)))
        #expect(closed == 1)
    }

    @Test func returnWithNothingSelectedIsConsumedAndLeavesThePanelAlone() async throws {
        let model = await makeModel([])
        var dismissed = 0
        model.host.dismiss = { dismissed += 1 }
        #expect(try model.handleKey(key(36)))
        #expect(try model.handleKey(key(51)))
        #expect(dismissed == 0)
    }

    @Test func theLauncherShowsTheHistoryAndTypingInItDoesNotRepublishTheLauncher() throws {
        let launcher = LauncherModel(
            settings: AppSettings(defaults: scratch), usage: UsageStore(defaults: scratch),
            snapshot: CatalogSnapshot(apps: [], commands: []), scopes: [], sources: []
        )
        launcher.clipboardHistory.query = "left over"
        launcher.clipboardHistory.selection = 4
        launcher.openClipboardHistory()
        #expect(launcher.isShowingClipboardHistory)
        #expect(launcher.clipboardHistory.query.isEmpty, "the history opens on everything")
        #expect(launcher.clipboardHistory.selection == 0)

        var changes = 0
        let subscription = launcher.objectWillChange.sink { changes += 1 }
        defer { subscription.cancel() }
        launcher.clipboardHistory.query = "bet"
        launcher.clipboardHistory.selection = 0
        #expect(changes == 0)

        #expect(try launcher.handleKey(key(53)))
        #expect(launcher.clipboardHistory.query.isEmpty)
        #expect(launcher.isShowingClipboardHistory)
        #expect(try launcher.handleKey(key(53)))
        #expect(!launcher.isShowingClipboardHistory)
    }
}
