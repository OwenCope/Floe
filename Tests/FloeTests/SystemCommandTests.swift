//
//  SystemCommandTests.swift
//  Project: Floe
//
//  Copyright (Floe) © 2026 René Jiménez
//  Licensed under the GNU AGPLv3

import AppKit
@testable import Floe
import Testing

struct SystemCommandTests {
    @Test(arguments: SystemCommand.allCases)
    func everyCommandHasATitleAndASymbolThatExists(command: SystemCommand) {
        #expect(!command.title.isEmpty)
        #expect(NSImage(systemSymbolName: command.symbol, accessibilityDescription: nil) != nil)
    }

    @Test func onlyTheCommandsThatLoseWorkAskFirst() {
        let asking = Set(SystemCommand.allCases.filter { $0.confirmation != nil })
        #expect(asking == [.restart, .shutDown, .logOut, .emptyTrash, .quitAllApps])
    }

    @Test func onlyTheTogglesAnswerWithALineForTheHUD() {
        let toggles = Set(SystemCommand.allCases.filter { $0.flip != nil })
        #expect(toggles == [.toggleWiFi, .toggleMute, .toggleKeepAwake])
        #expect(toggles.allSatisfy { $0.confirmation == nil }, "a toggle is undone by running it again")
    }

    @Test(arguments: [("wifi", "system:toggleWiFi"), ("unmute", "system:toggleMute"), ("prevent sleep", "system:toggleKeepAwake")])
    func aToggleIsFoundByWhatPeopleCallIt(query: String, id: String) {
        let results = Ranking.search(
            SystemCommand.allCases.map(RootItem.system), query: query, favorites: [], alias: { _ in nil }, frecency: { _ in 0 }
        )
        #expect(results.first?.item.id == id)
    }

    @Test func keepAwakeHoldsUntilItIsFlippedBack() {
        #expect(!SystemToggle.isKeepingAwake)
        #expect(SystemToggle.flipKeepAwake() == "Keeping your Mac awake")
        #expect(SystemToggle.isKeepingAwake)
        #expect(SystemToggle.flipKeepAwake() == "Your Mac can sleep again")
        #expect(!SystemToggle.isKeepingAwake)
    }

    @Test func aKeywordFindsItsCommand() {
        let results = Ranking.search(
            SystemCommand.allCases.map(RootItem.system), query: "reboot", favorites: [], alias: { _ in nil }, frecency: { _ in 0 }
        )
        #expect(results.first?.item.id == "system:restart")
    }
}
