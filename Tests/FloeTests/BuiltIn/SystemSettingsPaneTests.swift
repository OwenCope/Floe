//
//  SystemSettingsPaneTests.swift
//  Project: Floe
//
//  Copyright (Floe) © 2026 René Jiménez
//  Licensed under the GNU AGPLv3

import AppKit
@testable import Floe
import Foundation
import Testing

struct SystemSettingsPaneTests {
    private static let displays = "com.apple.Displays-Settings.extension"
    private static let controlCenter = "com.apple.ControlCenter-Settings.extension"

    @Test func aPaneTakesTheNameTheSystemGivesIt() throws {
        let pane = try #require(SystemSettingsPane.pane(identifier: Self.controlCenter, localizedName: "Menu Bar"))
        #expect(pane.title == "Menu Bar")
        #expect(pane.keywords.contains("control center"), "the name Floe knows it by still finds it")
        #expect(pane.url?.absoluteString == "x-apple.systempreferences:\(Self.controlCenter)")
    }

    @Test func aPaneWithoutANameOfItsOwnUsesTheKnownOne() throws {
        let pane = try #require(SystemSettingsPane.pane(identifier: "com.apple.Battery-Settings.extension", localizedName: nil))
        #expect(pane.title == "Battery")
        #expect(!pane.keywords.contains("battery"), "a title is not repeated as a keyword")
    }

    @Test func anUnknownPaneIsListedOnlyWhenItNamesItself() throws {
        #expect(SystemSettingsPane.pane(identifier: "com.example.unknown", localizedName: nil) == nil)
        let named = try #require(SystemSettingsPane.pane(identifier: "com.example.unknown", localizedName: "Example"))
        #expect(named.symbol == SystemSettingsPane.fallbackSymbol)
        #expect(named.keywords.isEmpty)
    }

    @Test func panesTheSystemOpensItselfAreLeftOut() {
        for identifier in SystemSettingsPane.hidden {
            #expect(SystemSettingsPane.pane(identifier: identifier, localizedName: "Anything") == nil)
        }
    }

    @Test(arguments: Array(SystemSettingsPane.known.keys))
    func everyKnownPaneHasASymbolThatExists(identifier: String) throws {
        let known = try #require(SystemSettingsPane.known[identifier])
        #expect(!known.title.isEmpty)
        #expect(NSImage(systemSymbolName: known.symbol, accessibilityDescription: nil) != nil, "\(known.symbol) for \(known.title)")
    }

    @Test func aScanKeepsOnlySettingsExtensions() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("floe-panes-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: folder) }
        try writeExtension(in: folder, name: "DisplaysExt", identifier: Self.displays, point: "com.apple.Settings.extension.ui")
        try writeExtension(in: folder, name: "DisplaysIntents", identifier: "com.apple.DisplaysIntents", point: "com.apple.appintents-extension")
        try Data().write(to: folder.appendingPathComponent("notes.txt"))

        let panes = SystemSettingsPane.scan(folder: folder)
        #expect(panes.map(\.identifier) == [Self.displays])
        #expect(panes.first?.title == "Displays")
    }

    @Test func aPaneDrawsItsOwnBundleUnlessMacOSHasNoIconForIt() throws {
        let displays = try #require(SystemSettingsPane.pane(identifier: Self.displays, localizedName: "Displays"))
        let battery = try #require(SystemSettingsPane.pane(identifier: "com.apple.Battery-Settings.extension", localizedName: "Battery"))
        #expect(displays.iconPath == nil, "a pane made without a bundle draws its symbol")
        #expect(displays.withIcon(at: "/x/Displays.appex").iconPath == "/x/Displays.appex")
        #expect(battery.withIcon(at: "/x/PowerPreferences.appex").iconPath == nil)
    }

    @Test func aPaneIsFoundByAKeywordAndOpensNothingElse() throws {
        let pane = try #require(SystemSettingsPane.pane(identifier: Self.displays, localizedName: "Displays"))
        let results = Ranking.search([.settingsPane(pane)], query: "monitor", favorites: [], alias: { _ in nil }, frecency: { _ in 0 })
        #expect(results.map(\.item.id) == ["settings-pane:\(Self.displays)"])
        #expect(RootItem.settingsPane(pane).kind == "System Settings")
    }

    @Test func aTitleOutranksAnotherItemsKeywordAndScatteredLettersInAKeywordDoNotMatch() throws {
        let sharing = try RootItem.settingsPane(#require(SystemSettingsPane.pane(identifier: "com.apple.Sharing-Settings.extension", localizedName: "Sharing")))
        let console = Fixture.app("Console")
        let prefix = Ranking.search([sharing, console], query: "co", favorites: [], alias: { _ in nil }, frecency: { _ in 0 })
        #expect(prefix.map(\.item.id) == [console.id, sharing.id], "\"computer name\" matches, behind the app whose name starts with it")
        let scattered = Ranking.search([sharing], query: "mute", favorites: [], alias: { _ in nil }, frecency: { _ in 0 })
        #expect(scattered.isEmpty, "m, u, t, e in \"computer name\" is not a match")
    }

    @Test func panesAreNotListedWithoutAQueryUnlessFavoriteOrUsed() throws {
        let displays = try RootItem.settingsPane(#require(SystemSettingsPane.pane(identifier: Self.displays, localizedName: "Displays")))
        let menuBar = try RootItem.settingsPane(#require(SystemSettingsPane.pane(identifier: Self.controlCenter, localizedName: "Menu Bar")))
        let notes = Fixture.app("Notes")

        let plain = Ranking.browse([notes], searchOnly: [displays, menuBar], favorites: [], frecency: { _ in 0 })
        #expect(plain.map(\.item.id) == [notes.id])

        let kept = Ranking.browse([notes], searchOnly: [displays, menuBar], favorites: [displays.id], frecency: { $0 == menuBar.id ? 3 : 0 })
        #expect(kept.map(\.item.id) == [displays.id, menuBar.id, notes.id])
        #expect(kept.map(\.section) == ["Favorites", "Suggestions", "Applications"])
    }

    private func writeExtension(in folder: URL, name: String, identifier: String, point: String) throws {
        let contents = folder.appendingPathComponent("\(name).appex/Contents")
        try FileManager.default.createDirectory(at: contents, withIntermediateDirectories: true)
        let info: [String: Any] = [
            "CFBundleIdentifier": identifier,
            "CFBundleDisplayName": "InternalName",
            "EXAppExtensionAttributes": ["EXExtensionPointIdentifier": point],
        ]
        try PropertyListSerialization.data(fromPropertyList: info, format: .xml, options: 0)
            .write(to: contents.appendingPathComponent("Info.plist"))
    }
}
