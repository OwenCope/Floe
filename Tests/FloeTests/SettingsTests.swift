//
//  SettingsTests.swift
//  Project: Floe
//
//  Copyright (Floe) © 2026 René Jiménez
//  Licensed under the GNU AGPLv3

@testable import Floe
import Foundation
import SwiftUI
import Testing

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
    /// Color equality compares storage, not components; the round trip converts
    /// through sRGB, so compare the components themselves.
    private func sameColor(_ left: Color, _ right: Color) -> Bool {
        let a = NSColor(left).usingColorSpace(.sRGB)!
        let b = NSColor(right).usingColorSpace(.sRGB)!
        return abs(a.redComponent - b.redComponent) < 0.001
            && abs(a.greenComponent - b.greenComponent) < 0.001
            && abs(a.blueComponent - b.blueComponent) < 0.001
    }

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
        #expect(settings.showInDock == false)
        #expect(settings.hasSeenOnboarding == false)
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
        settings.showInDock = true
        settings.hasSeenOnboarding = true
        settings.launcherTintIsDynamic = true
        settings.launcherTintLight = LauncherTint(
            kind: .solid,
            solid: StoredColor(Color(red: 0.2, green: 0.35, blue: 0.9)),
            opacity: 0.4
        )
        settings.launcherTintDark = LauncherTint(
            kind: .gradient,
            gradient: LauncherGradient(
                start: StoredColor(Color(red: 0.1, green: 0.2, blue: 0.8)),
                end: StoredColor(Color(red: 0.6, green: 0.2, blue: 0.85)),
                angle: 120
            ),
            opacity: 0.5
        )
        settings.launcherBorder = LauncherBorder(color: StoredColor(Color.white.opacity(0.6)), width: 2)
        settings.launcherShowsBorder = true
        settings.launcherShowsShadow = true
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
        #expect(reloaded.showInDock)
        #expect(reloaded.hasSeenOnboarding)
        #expect(reloaded.menuBarItemNames == ["com.a|status": "Renamed"])
        #expect(reloaded.isRecordingHotkey == false, "recording state is not persisted")

        #expect(reloaded.launcherTintIsDynamic)
        #expect(reloaded.launcherTintLight.kind == .solid)
        #expect(reloaded.launcherTintLight.opacity == 0.4)
        #expect(reloaded.launcherTintDark.kind == .gradient)
        #expect(reloaded.launcherTintDark.opacity == 0.5)
        #expect(reloaded.launcherTintDark.gradient.angle == 120)
        #expect(sameColor(reloaded.launcherTintDark.gradient.start.color, Color(red: 0.1, green: 0.2, blue: 0.8)))
        // The resolution follows the system appearance; this suite runs in light.
        #expect(reloaded.launcherTint(for: .light).kind == .solid)
        #expect(reloaded.launcherTint(for: .dark).kind == .gradient)
        #expect(reloaded.launcherBorder.width == 2)
        #expect(reloaded.launcherShowsBorder)
        #expect(reloaded.launcherShowsShadow)
    }

    @Test func theAIChoiceStartsWithTheToolsAndComesBackAfterASave() {
        let settings = AppSettings(defaults: scratch.defaults)
        #expect(settings.aiSource == .tools)
        #expect(settings.aiBaseURL == AIEndpoint.defaultBaseURL)
        #expect(settings.aiModel.isEmpty)
        settings.aiSource = .api
        settings.aiBaseURL = "http://localhost:11434/v1"
        settings.aiModel = "small"
        settings.save()
        let reloaded = AppSettings(defaults: scratch.defaults)
        #expect(reloaded.aiSource == .api)
        #expect(reloaded.aiBaseURL == "http://localhost:11434/v1")
        #expect(reloaded.aiModel == "small")
    }

    @Test func appearanceDefaultsPreserveTheCurrentLauncherLook() {
        let settings = AppSettings(defaults: scratch.defaults)
        #expect(settings.launcherTint(for: .light).kind == .none, "no tint unless it is chosen")
        #expect(settings.launcherTint(for: .dark).kind == .none, "both modes start without a tint")
        #expect(settings.launcherShowsBorder == false)
        #expect(settings.launcherShowsShadow == false, "the launcher shipped without a shadow")
    }

    @Test func settingsSavedBeforeNewerFieldsExistedStillLoad() {
        let older = #"{"commandHotkeys":{},"aliases":{"a/b":"x"},"disabledExtensions":[],"includeRaycastExtensions":true}"#
        scratch.defaults.set(Data(older.utf8), forKey: "settings")
        let settings = AppSettings(defaults: scratch.defaults)
        #expect(settings.aliases == ["a/b": "x"])
        #expect(settings.toggleHotkey == nil, "the stored blob has no hotkey")
        #expect(settings.popToRootDelay == 90)
        #expect(settings.favorites.isEmpty)
        #expect(settings.rememberMenuBarQuery == false)
        #expect(settings.showInDock == false)
        #expect(settings.hasSeenOnboarding == false)
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
        clock.now += 3 * 86400
        #expect(store.frecency(of: "settings") == 1)
        clock.now += 60 * 86400
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
