//
//  SettingsTests.swift
//  Project: Floe
//
//  Copyright (Floe) © 2026 René Jiménez
//  Licensed under the GNU GPLv3

import Foundation
import Testing
@testable import Floe

/// A throwaway defaults suite per test, removed when the test's suite value goes away.
final class ScratchDefaults {
    let name = "floe-tests-\(UUID().uuidString)"
    let defaults: UserDefaults

    init() throws {
        defaults = try #require(UserDefaults(suiteName: name))
    }

    deinit {
        defaults.removePersistentDomain(forName: name)
    }
}

struct AppSettingsTests {
    private let scratch: ScratchDefaults

    init() throws {
        scratch = try ScratchDefaults()
    }

    @Test func startsWithTheDocumentedDefaults() {
        let settings = AppSettings(defaults: scratch.defaults)
        #expect(settings.toggleHotkey == KeyCombination(key: .space, modifiers: [.control, .option]))
        #expect(settings.commandHotkeys.isEmpty)
        #expect(settings.aliases.isEmpty)
        #expect(settings.favorites.isEmpty)
        #expect(settings.disabledExtensions.isEmpty)
        #expect(settings.includeRaycastExtensions)
        #expect(settings.popToRootDelay == 90)
        #expect(settings.rememberMenuBarQuery == false)
        #expect(settings.menuBarItemNames.isEmpty)
        #expect(settings.isRecordingHotkey == false)
    }

    @Test func savedSettingsComeBackInANewInstance() {
        let settings = AppSettings(defaults: scratch.defaults)
        settings.toggleHotkey = nil
        settings.commandHotkeys = ["hello/planets": KeyCombination(key: .a, modifiers: .command)]
        settings.aliases = ["hacker-news/frontpage": "hn"]
        settings.favorites = ["settings", "app:/Applications/Notes.app"]
        settings.disabledExtensions = ["coffee"]
        settings.includeRaycastExtensions = false
        settings.popToRootDelay = 30
        settings.rememberMenuBarQuery = true
        settings.menuBarItemNames = ["com.a|status": "Renamed"]
        settings.isRecordingHotkey = true
        settings.save()

        let reloaded = AppSettings(defaults: scratch.defaults)
        #expect(reloaded.toggleHotkey == nil, "a cleared hotkey stays cleared instead of returning to the default")
        #expect(reloaded.commandHotkeys == ["hello/planets": KeyCombination(key: .a, modifiers: .command)])
        #expect(reloaded.aliases == ["hacker-news/frontpage": "hn"])
        #expect(reloaded.favorites == ["settings", "app:/Applications/Notes.app"])
        #expect(reloaded.disabledExtensions == ["coffee"])
        #expect(reloaded.includeRaycastExtensions == false)
        #expect(reloaded.popToRootDelay == 30)
        #expect(reloaded.rememberMenuBarQuery)
        #expect(reloaded.menuBarItemNames == ["com.a|status": "Renamed"])
        #expect(reloaded.isRecordingHotkey == false, "recording state is not persisted")
    }

    @Test func settingsSavedBeforeNewerFieldsExistedStillLoad() throws {
        let older = #"{"commandHotkeys":{},"aliases":{"a/b":"x"},"disabledExtensions":[],"includeRaycastExtensions":true}"#
        scratch.defaults.set(Data(older.utf8), forKey: "settings")
        let settings = AppSettings(defaults: scratch.defaults)
        #expect(settings.aliases == ["a/b": "x"])
        #expect(settings.toggleHotkey == nil, "the stored blob has no hotkey")
        #expect(settings.popToRootDelay == 90)
        #expect(settings.favorites.isEmpty)
        #expect(settings.rememberMenuBarQuery == false)
        #expect(settings.menuBarItemNames.isEmpty)
    }

    @Test func unreadableSettingsFallBackToDefaults() {
        scratch.defaults.set(Data("not json".utf8), forKey: "settings")
        let settings = AppSettings(defaults: scratch.defaults)
        #expect(settings.toggleHotkey == AppSettings.defaultToggleHotkey)
        #expect(settings.popToRootDelay == 90)
    }

    @Test func changesAreSavedOnTheirOwnShortlyAfter() async throws {
        let settings = AppSettings(defaults: scratch.defaults)
        settings.popToRootDelay = 300
        try await Task.sleep(for: .milliseconds(600))
        #expect(AppSettings(defaults: scratch.defaults).popToRootDelay == 300)
    }
}

struct LegacyDefaultsTests {
    private let old: ScratchDefaults
    private let new: ScratchDefaults

    init() throws {
        old = try ScratchDefaults()
        new = try ScratchDefaults()
    }

    @Test func copiesSettingsAndUsageIntoEmptyDefaults() {
        old.defaults.set(Data("settings".utf8), forKey: "settings")
        old.defaults.set(Data("usage".utf8), forKey: "usage")
        LegacyDefaults.migrate(from: old.defaults, to: new.defaults)
        #expect(new.defaults.data(forKey: "settings") == Data("settings".utf8))
        #expect(new.defaults.data(forKey: "usage") == Data("usage".utf8))
    }

    @Test func leavesExistingSettingsAlone() {
        old.defaults.set(Data("old".utf8), forKey: "settings")
        old.defaults.set(Data("old usage".utf8), forKey: "usage")
        new.defaults.set(Data("current".utf8), forKey: "settings")
        LegacyDefaults.migrate(from: old.defaults, to: new.defaults)
        #expect(new.defaults.data(forKey: "settings") == Data("current".utf8))
        #expect(new.defaults.data(forKey: "usage") == nil)
    }

    @Test func doesNothingWithoutOldDefaults() {
        LegacyDefaults.migrate(from: nil, to: new.defaults)
        LegacyDefaults.migrate(from: old.defaults, to: new.defaults)
        #expect(new.defaults.data(forKey: "settings") == nil)
    }
}

struct UsageStoreTests {
    private let scratch: ScratchDefaults
    private let clock = Clock()

    /// A clock the test moves by hand.
    private final class Clock {
        var now = Date(timeIntervalSince1970: 1_800_000_000)
    }

    init() throws {
        scratch = try ScratchDefaults()
    }

    private func makeStore() -> UsageStore {
        UsageStore(defaults: scratch.defaults, now: { [clock] in clock.now })
    }

    @Test func anItemNeverUsedHasNoFrecency() {
        #expect(makeStore().frecency(of: "settings") == 0)
    }

    @Test func eachUseCountsAndRecentUseWeighsMost() {
        let store = makeStore()
        store.recordUse(of: "app:/Applications/Notes.app")
        store.recordUse(of: "app:/Applications/Notes.app")
        #expect(store.records["app:/Applications/Notes.app"]?.count == 2)
        #expect(store.frecency(of: "app:/Applications/Notes.app") == 8, "two uses in the last hour")
    }

    @Test func frecencyFadesAsTimePasses() {
        let store = makeStore()
        store.recordUse(of: "settings")
        clock.now += 2 * 3600
        #expect(store.frecency(of: "settings") == 2)
        clock.now += 3 * 86_400
        #expect(store.frecency(of: "settings") == 1)
        clock.now += 60 * 86_400
        #expect(store.frecency(of: "settings") == 0.25)
    }

    @Test func usageSurvivesARestart() {
        let store = makeStore()
        store.recordUse(of: "settings")
        store.recordUse(of: "settings")
        store.recordUse(of: "command:hello/planets")

        let reloaded = makeStore()
        #expect(reloaded.records["settings"]?.count == 2)
        #expect(reloaded.records["command:hello/planets"]?.count == 1)
        #expect(reloaded.records["settings"]?.lastUsed == clock.now)
    }
}
