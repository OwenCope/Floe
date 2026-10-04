//
//  Settings.swift
//  Project: Floe
//
//  Copyright (Floe) © 2026 René Jiménez
//  Licensed under the GNU AGPLv3

import Combine
import Foundation
import SwiftUI

/// Launcher-wide settings, persisted as one JSON blob in UserDefaults.
final class AppSettings: ObservableObject {
    static let shared = AppSettings()

    static let defaultToggleHotkey = KeyCombination(key: .space, modifiers: [.control, .option])

    @Published var toggleHotkey: KeyCombination? = defaultToggleHotkey
    /// Keyed by `RootItem.settingsKey`: a command's id, or "app:" and the app's path.
    @Published var commandHotkeys: [String: KeyCombination] = [:]
    /// Keyed by `RootItem.settingsKey`.
    @Published var aliases: [String: String] = [:]
    /// `RootItem.id`s, in the order they're shown.
    @Published var favorites: [String] = []
    /// Extension names.
    @Published var disabledExtensions: Set<String> = []
    @Published var includeRaycastExtensions = true
    /// Seconds a closed panel keeps the open command before going back to the root search; 0 resets at once.
    @Published var popToRootDelay = 90
    /// Show Floe's icon in the Dock; off, it lives only in the menu bar.
    @Published var showInDock = false
    /// The welcome window was finished or skipped once, so it does not open on later launches.
    @Published var hasSeenOnboarding = false
    /// Keep the menu bar search's query between showings, like Thaw's "Remember last search".
    @Published var rememberMenuBarQuery = false
    /// Whether copies are saved to the clipboard history.
    @Published var clipboardHistoryEnabled = true
    /// The menu-bar commands that have a status item, by command id. A command is added by running it.
    @Published var menuBarCommands: Set<String> = []
    /// Names given to menu bar items with Edit Name, keyed by `MenuBarExtra.id`.
    @Published var menuBarItemNames: [String: String] = [:]
    /// True while a hotkey recorder is listening, so the registry can stand down.
    @Published var isRecordingHotkey = false
    /// Thaw-style appearance for the launcher panel: a tint over the glass, an
    /// optional border, and a shaped drop shadow. Like Thaw's isDynamic switch,
    /// the tint can follow the system appearance with separate light and dark
    /// values, or stay the same in both.
    @Published var launcherGlass = LauncherGlass()
    @Published var launcherTintIsDynamic = false
    @Published var launcherTintLight = LauncherTint()
    @Published var launcherTintDark = LauncherTint()
    @Published var launcherBorder = LauncherBorder()
    @Published var launcherShowsBorder = false
    @Published var launcherShowsShadow = false
    /// What answers an extension's `AI.ask`, and where the API is when that is the choice.
    /// The API's key is in the Keychain (`AIEndpoint.keychainAccount`).
    @Published var aiSource = AISource.tools
    @Published var aiBaseURL = AIEndpoint.defaultBaseURL
    @Published var aiModel = ""

    /// The tint a view should draw for the given system appearance.
    func launcherTint(for colorScheme: ColorScheme) -> LauncherTint {
        guard launcherTintIsDynamic else { return launcherTintLight }
        return colorScheme == .dark ? launcherTintDark : launcherTintLight
    }

    private struct Stored: Codable {
        var toggleHotkey: KeyCombination?
        var commandHotkeys: [String: KeyCombination]
        var aliases: [String: String]
        var disabledExtensions: Set<String>
        var includeRaycastExtensions: Bool
        var popToRootDelay: Int?
        var favorites: [String]?
        var rememberMenuBarQuery: Bool?
        var clipboardHistoryEnabled: Bool?
        var menuBarCommands: Set<String>?
        var menuBarItemNames: [String: String]?
        var showInDock: Bool?
        var hasSeenOnboarding: Bool?
        var launcherTint: LauncherTint?
        var launcherTintIsDynamic: Bool?
        var launcherTintLight: LauncherTint?
        var launcherTintDark: LauncherTint?
        var launcherBorder: LauncherBorder?
        var launcherShowsBorder: Bool?
        var launcherShowsShadow: Bool?
        var launcherGlass: LauncherGlass?
        var aiSource: AISource?
        var aiBaseURL: String?
        var aiModel: String?
    }

    private static let defaultsKey = "settings"
    private let defaults: UserDefaults
    private var cancellable: AnyCancellable?

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        if let data = defaults.data(forKey: Self.defaultsKey),
           let stored = try? JSONDecoder().decode(Stored.self, from: data)
        {
            apply(stored)
        }
        cancellable = objectWillChange
            .debounce(for: .milliseconds(200), scheduler: RunLoop.main)
            .sink { [weak self] in self?.save() }
    }

    private func apply(_ stored: Stored) {
        toggleHotkey = stored.toggleHotkey
        commandHotkeys = stored.commandHotkeys
        aliases = stored.aliases
        disabledExtensions = stored.disabledExtensions
        includeRaycastExtensions = stored.includeRaycastExtensions
        popToRootDelay = stored.popToRootDelay ?? popToRootDelay
        favorites = stored.favorites ?? []
        rememberMenuBarQuery = stored.rememberMenuBarQuery ?? false
        clipboardHistoryEnabled = stored.clipboardHistoryEnabled ?? true
        menuBarCommands = stored.menuBarCommands ?? []
        menuBarItemNames = stored.menuBarItemNames ?? [:]
        showInDock = stored.showInDock ?? false
        hasSeenOnboarding = stored.hasSeenOnboarding ?? false
        // A tint saved before light and dark variants existed becomes the light one.
        launcherTintLight = stored.launcherTintLight ?? stored.launcherTint ?? launcherTintLight
        launcherTintDark = stored.launcherTintDark ?? launcherTintDark
        launcherTintIsDynamic = stored.launcherTintIsDynamic ?? launcherTintIsDynamic
        launcherBorder = stored.launcherBorder ?? launcherBorder
        launcherShowsBorder = stored.launcherShowsBorder ?? launcherShowsBorder
        launcherShowsShadow = stored.launcherShowsShadow ?? launcherShowsShadow
        launcherGlass = stored.launcherGlass ?? launcherGlass
        aiSource = stored.aiSource ?? aiSource
        aiBaseURL = stored.aiBaseURL ?? aiBaseURL
        aiModel = stored.aiModel ?? aiModel
    }

    /// The settings as they are saved, for an export file.
    func exportedJSON() throws -> Data {
        save()
        return defaults.data(forKey: Self.defaultsKey) ?? Data("{}".utf8)
    }

    /// Replaces every setting with an exported copy and saves it.
    func importJSON(_ data: Data) throws {
        try apply(JSONDecoder().decode(Stored.self, from: data))
        save()
    }

    /// Runs on its own shortly after any change; callable directly when the change must be on disk now.
    func save() {
        let stored = Stored(
            toggleHotkey: toggleHotkey,
            commandHotkeys: commandHotkeys,
            aliases: aliases,
            disabledExtensions: disabledExtensions,
            includeRaycastExtensions: includeRaycastExtensions,
            popToRootDelay: popToRootDelay,
            favorites: favorites,
            rememberMenuBarQuery: rememberMenuBarQuery,
            clipboardHistoryEnabled: clipboardHistoryEnabled,
            menuBarCommands: menuBarCommands,
            menuBarItemNames: menuBarItemNames,
            showInDock: showInDock,
            hasSeenOnboarding: hasSeenOnboarding,
            launcherTintIsDynamic: launcherTintIsDynamic,
            launcherTintLight: launcherTintLight,
            launcherTintDark: launcherTintDark,
            launcherBorder: launcherBorder,
            launcherShowsBorder: launcherShowsBorder,
            launcherShowsShadow: launcherShowsShadow,
            launcherGlass: launcherGlass,
            aiSource: aiSource,
            aiBaseURL: aiBaseURL,
            aiModel: aiModel
        )
        if let data = try? JSONEncoder().encode(stored) {
            defaults.set(data, forKey: Self.defaultsKey)
        }
    }
}

/// How often and how recently each root item was opened, for ranking. Kept apart from settings
/// because it changes on every launch.
final class UsageStore {
    static let shared = UsageStore()

    struct Record: Codable {
        var count: Int
        var lastUsed: Date
    }

    private(set) var records: [String: Record]
    private static let defaultsKey = "usage"
    private let defaults: UserDefaults
    private let now: () -> Date

    /// `now` is injectable so ranking by recency can be tested against a fixed clock.
    init(defaults: UserDefaults = .standard, now: @escaping () -> Date = Date.init) {
        self.defaults = defaults
        self.now = now
        records = defaults.data(forKey: Self.defaultsKey)
            .flatMap { try? JSONDecoder().decode([String: Record].self, from: $0) } ?? [:]
    }

    func recordUse(of id: String) {
        var record = records[id] ?? Record(count: 0, lastUsed: .distantPast)
        record.count += 1
        record.lastUsed = now()
        records[id] = record
        if let data = try? JSONEncoder().encode(records) {
            defaults.set(data, forKey: Self.defaultsKey)
        }
    }

    func frecency(of id: String) -> Double {
        guard let record = records[id] else { return 0 }
        return Ranking.frecency(count: record.count, age: now().timeIntervalSince(record.lastUsed))
    }
}
