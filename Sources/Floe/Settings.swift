//
//  Settings.swift
//  Project: Floe
//
//  Copyright (Floe) © 2026 René Jiménez
//  Licensed under the GNU GPLv3

import Combine
import Foundation

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
    /// Names given to menu bar items with Edit Name, keyed by `MenuBarExtra.id`.
    @Published var menuBarItemNames: [String: String] = [:]
    /// True while a hotkey recorder is listening, so the registry can stand down.
    @Published var isRecordingHotkey = false

    private struct Stored: Codable {
        var toggleHotkey: KeyCombination?
        var commandHotkeys: [String: KeyCombination]
        var aliases: [String: String]
        var disabledExtensions: Set<String>
        var includeRaycastExtensions: Bool
        var popToRootDelay: Int?
        var favorites: [String]?
        var rememberMenuBarQuery: Bool?
        var menuBarItemNames: [String: String]?
        var showInDock: Bool?
        var hasSeenOnboarding: Bool?
    }

    private static let defaultsKey = "settings"
    private let defaults: UserDefaults
    private var cancellable: AnyCancellable?

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        if let data = defaults.data(forKey: Self.defaultsKey),
           let stored = try? JSONDecoder().decode(Stored.self, from: data)
        {
            toggleHotkey = stored.toggleHotkey
            commandHotkeys = stored.commandHotkeys
            aliases = stored.aliases
            disabledExtensions = stored.disabledExtensions
            includeRaycastExtensions = stored.includeRaycastExtensions
            popToRootDelay = stored.popToRootDelay ?? popToRootDelay
            favorites = stored.favorites ?? []
            rememberMenuBarQuery = stored.rememberMenuBarQuery ?? false
            menuBarItemNames = stored.menuBarItemNames ?? [:]
            showInDock = stored.showInDock ?? false
            hasSeenOnboarding = stored.hasSeenOnboarding ?? false
        }
        cancellable = objectWillChange
            .debounce(for: .milliseconds(200), scheduler: RunLoop.main)
            .sink { [weak self] in self?.save() }
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
            menuBarItemNames: menuBarItemNames,
            showInDock: showInDock,
            hasSeenOnboarding: hasSeenOnboarding
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
