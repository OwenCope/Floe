//
//  SystemStores.swift
//  Project: Floe
//
//  Copyright (Floe) © 2026 René Jiménez
//  Licensed under the GNU AGPLv3

import Foundation
import Security
import ServiceManagement

extension AppSettings {
    /// Login items only work for the installed app bundle, not `swift run`.
    var launchAtLogin: Bool {
        get { SMAppService.mainApp.status == .enabled }
        set {
            objectWillChange.send()
            if newValue {
                try? SMAppService.mainApp.register()
            } else {
                try? SMAppService.mainApp.unregister()
            }
        }
    }
}

/// Extension and command preference values. Plain values live in the extension's support folder
/// as preferences.json; password preferences live in the Keychain.
enum PreferenceStore {
    static func directory(for extensionName: String) -> URL {
        Paths.data.appendingPathComponent(extensionName)
    }

    private static func storageKey(_ field: FieldSpec, command: ExtensionCommand?) -> String {
        PreferenceResolver.storageKey(field, commandName: command?.name)
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
        if field.isSecret {
            return Keychain.read(account: "\(extensionName)/\(key)")
        }
        return storedValues(extensionName)[key]
    }

    static func save(_ values: [String: Any], fields: [FieldSpec], extensionName: String, command: ExtensionCommand?) {
        var stored = storedValues(extensionName)
        for field in fields {
            let key = storageKey(field, command: command)
            let value = values[field.name]
            if field.isSecret {
                let account = "\(extensionName)/\(key)"
                if let text = value as? String, !text.isEmpty {
                    Keychain.write(text, account: account)
                } else {
                    Keychain.delete(account: account)
                }
            } else {
                stored[key] = value
            }
        }
        try? FileManager.default.createDirectory(at: directory(for: extensionName), withIntermediateDirectories: true)
        if let data = try? JSONSerialization.data(withJSONObject: stored) {
            try? data.write(to: file(for: extensionName))
        }
    }

    /// Everything a command's `getPreferenceValues()` should return: stored values, then defaults.
    static func resolvedValues(for command: ExtensionCommand) -> [String: Any] {
        PreferenceResolver.resolve(
            extensionFields: command.extensionPreferences,
            commandFields: command.commandPreferences,
            commandName: command.name,
            stored: storedValues(command.extensionName),
            secret: { Keychain.read(account: "\(command.extensionName)/\($0)") }
        )
    }

    static func missingRequired(for command: ExtensionCommand) -> [FieldSpec] {
        PreferenceResolver.missingRequired(command.preferences, values: resolvedValues(for: command))
    }
}

enum Keychain {
    private static let service = "com.thaw.floe.preferences"

    private static func query(_ account: String) -> [String: Any] {
        [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service, kSecAttrAccount as String: account]
    }

    static func read(account: String) -> String? {
        var query = query(account)
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
