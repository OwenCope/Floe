//
//  Settings.swift
//  Project: Floe
//
//  Copyright (Floe) © 2026 René Jiménez
//  Licensed under the GNU GPLv3

import Combine
import Foundation
import Security
import ServiceManagement

/// Settings and usage saved before the rename lived under the old bundle identifier's defaults.
enum LegacyDefaults {
    private static let oldDomain = "com.diazdesandi.launcher-proto"

    static func migrate() {
        let defaults = UserDefaults.standard
        guard defaults.data(forKey: "settings") == nil, let old = UserDefaults(suiteName: oldDomain) else { return }
        for key in ["settings", "usage"] {
            if let data = old.data(forKey: key) { defaults.set(data, forKey: key) }
        }
    }
}

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
    }

    private static let defaultsKey = "settings"
    private var cancellable: AnyCancellable?

    private init() {
        if let data = UserDefaults.standard.data(forKey: Self.defaultsKey),
           let stored = try? JSONDecoder().decode(Stored.self, from: data) {
            toggleHotkey = stored.toggleHotkey
            commandHotkeys = stored.commandHotkeys
            aliases = stored.aliases
            disabledExtensions = stored.disabledExtensions
            includeRaycastExtensions = stored.includeRaycastExtensions
            popToRootDelay = stored.popToRootDelay ?? popToRootDelay
            favorites = stored.favorites ?? []
            rememberMenuBarQuery = stored.rememberMenuBarQuery ?? false
            menuBarItemNames = stored.menuBarItemNames ?? [:]
        }
        cancellable = objectWillChange
            .debounce(for: .milliseconds(200), scheduler: RunLoop.main)
            .sink { [weak self] in self?.save() }
    }

    private func save() {
        let stored = Stored(toggleHotkey: toggleHotkey, commandHotkeys: commandHotkeys, aliases: aliases,
                            disabledExtensions: disabledExtensions, includeRaycastExtensions: includeRaycastExtensions,
                            popToRootDelay: popToRootDelay, favorites: favorites,
                            rememberMenuBarQuery: rememberMenuBarQuery, menuBarItemNames: menuBarItemNames)
        if let data = try? JSONEncoder().encode(stored) {
            UserDefaults.standard.set(data, forKey: Self.defaultsKey)
        }
    }

    /// Login items only work for the installed app bundle, not `swift run`.
    var launchAtLogin: Bool {
        get { SMAppService.mainApp.status == .enabled }
        set {
            objectWillChange.send()
            try? newValue ? SMAppService.mainApp.register() : SMAppService.mainApp.unregister()
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

    private init() {
        records = UserDefaults.standard.data(forKey: Self.defaultsKey)
            .flatMap { try? JSONDecoder().decode([String: Record].self, from: $0) } ?? [:]
    }

    func recordUse(of id: String) {
        var record = records[id] ?? Record(count: 0, lastUsed: .distantPast)
        record.count += 1
        record.lastUsed = Date()
        records[id] = record
        if let data = try? JSONEncoder().encode(records) {
            UserDefaults.standard.set(data, forKey: Self.defaultsKey)
        }
    }

    /// Use count weighted by recency: an item opened often but not lately fades behind one used today.
    func frecency(of id: String) -> Double {
        guard let record = records[id] else { return 0 }
        let age = Date().timeIntervalSince(record.lastUsed)
        let weight: Double = switch age {
        case ..<3600: 4
        case ..<86_400: 2
        case ..<604_800: 1
        case ..<2_592_000: 0.5
        default: 0.25
        }
        return Double(record.count) * weight
    }
}

/// Extension and command preference values. Plain values live in the extension's support folder
/// as preferences.json; password preferences live in the Keychain.
enum PreferenceStore {
    static func directory(for extensionName: String) -> URL {
        Paths.data.appendingPathComponent(extensionName)
    }

    /// Command preferences are stored under "command/name" so two commands can reuse a name.
    private static func storageKey(_ field: FieldSpec, command: ExtensionCommand?) -> String {
        command.map { "\($0.name)/\(field.name)" } ?? field.name
    }

    private static func file(for extensionName: String) -> URL {
        directory(for: extensionName).appendingPathComponent("preferences.json")
    }

    private static func storedValues(_ extensionName: String) -> [String: Any] {
        guard let data = try? Data(contentsOf: file(for: extensionName)) else { return [:] }
        return (try? JSONSerialization.jsonObject(with: data) as? [String: Any]) ?? [:]
    }

    /// The stored value for one field, without falling back to its default.
    static func value(_ field: FieldSpec, extensionName: String, command: ExtensionCommand?) -> Any? {
        let key = storageKey(field, command: command)
        if field.isSecret { return Keychain.read(account: "\(extensionName)/\(key)") }
        return storedValues(extensionName)[key]
    }

    static func save(_ values: [String: Any], fields: [FieldSpec], extensionName: String, command: ExtensionCommand?) {
        var stored = storedValues(extensionName)
        for field in fields {
            let key = storageKey(field, command: command)
            let value = values[field.name]
            if field.isSecret {
                let account = "\(extensionName)/\(key)"
                if let text = value as? String, !text.isEmpty { Keychain.write(text, account: account) } else { Keychain.delete(account: account) }
            } else {
                stored[key] = value
            }
        }
        try? FileManager.default.createDirectory(at: directory(for: extensionName), withIntermediateDirectories: true)
        if let data = try? JSONSerialization.data(withJSONObject: stored) {
            try? data.write(to: file(for: extensionName))
        }
    }

    /// Everything a command's `getPreferenceValues()` should return: defaults, then stored values.
    static func resolvedValues(for command: ExtensionCommand) -> [String: Any] {
        var result: [String: Any] = [:]
        let scoped = command.extensionPreferences.map { ($0, Optional<ExtensionCommand>.none) }
            + command.commandPreferences.map { ($0, Optional(command)) }
        for (field, scope) in scoped {
            if let value = value(field, extensionName: command.extensionName, command: scope) {
                result[field.name] = value
            } else if let fallback = field.defaultValue {
                result[field.name] = fallback
            } else if field.type == "checkbox" {
                result[field.name] = false
            }
        }
        return result
    }

    static func missingRequired(for command: ExtensionCommand) -> [FieldSpec] {
        let values = resolvedValues(for: command)
        return command.preferences.filter { field in
            guard field.required else { return false }
            if let text = values[field.name] as? String { return text.isEmpty }
            return values[field.name] == nil
        }
    }
}

enum Keychain {
    private static let service = "com.diazdesandi.Floe.preferences"
    /// Items saved before the rename to Floe; read as a fallback and moved over on first use.
    private static let legacyService = "com.diazdesandi.launcher-proto.preferences"

    private static func query(_ account: String, service: String = service) -> [String: Any] {
        [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service, kSecAttrAccount as String: account]
    }

    static func read(account: String) -> String? {
        if let value = read(account: account, service: service) { return value }
        guard let legacy = read(account: account, service: legacyService) else { return nil }
        write(legacy, account: account)
        SecItemDelete(query(account, service: legacyService) as CFDictionary)
        return legacy
    }

    private static func read(account: String, service: String) -> String? {
        var query = query(account, service: service)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: AnyObject?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess, let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    static func write(_ value: String, account: String) {
        let data = Data(value.utf8)
        if SecItemUpdate(query(account) as CFDictionary, [kSecValueData as String: data] as CFDictionary) == errSecItemNotFound {
            var item = query(account)
            item[kSecValueData as String] = data
            SecItemAdd(item as CFDictionary, nil)
        }
    }

    static func delete(account: String) {
        SecItemDelete(query(account) as CFDictionary)
    }
}
