//
//  Manifest.swift
//  Project: Floe
//
//  Copyright (Floe) © 2026 René Jiménez
//  Licensed under the GNU GPLv3

import Foundation

/// A preference or argument declared in an extension manifest, as an editable field.
struct FieldSpec: Identifiable {
    let name: String
    let title: String
    let detail: String?
    /// Raycast's type names: textfield, password, checkbox, dropdown, appPicker, file, directory (preferences);
    /// text, password, dropdown (arguments).
    let type: String
    let required: Bool
    let placeholder: String?
    /// Checkbox label.
    let label: String?
    let options: [(title: String, value: String)]
    let defaultValue: Any?

    var id: String { name }
    var isSecret: Bool { type == "password" }

    init?(json: [String: Any]) {
        guard let name = json["name"] as? String else { return nil }
        self.name = name
        self.title = json["title"] as? String ?? json["placeholder"] as? String ?? name
        self.detail = json["description"] as? String
        self.type = json["type"] as? String ?? "textfield"
        self.required = json["required"] as? Bool ?? false
        self.placeholder = json["placeholder"] as? String
        self.label = json["label"] as? String
        self.options = (json["data"] as? [[String: Any]] ?? []).compactMap { option in
            guard let value = option["value"] as? String else { return nil }
            return (option["title"] as? String ?? value, value)
        }
        self.defaultValue = json["default"]
    }
}

struct ExtensionCommand: Identifiable {
    enum Source { case local, raycast }

    let extensionDir: URL
    let extensionName: String
    let extensionTitle: String
    let source: Source
    let name: String
    let title: String
    let mode: String
    let icon: String?
    let arguments: [FieldSpec]
    let extensionPreferences: [FieldSpec]
    let commandPreferences: [FieldSpec]

    var id: String { "\(extensionName)/\(name)" }
    var assetsPath: String { extensionDir.appendingPathComponent("assets").path }
    var preferences: [FieldSpec] { extensionPreferences + commandPreferences }

    /// The commands a package.json declares that Floe can run: view and no-view, not menu-bar.
    static func commands(inManifest manifest: [String: Any], folder: URL, source: Source) -> [ExtensionCommand] {
        guard let extensionName = manifest["name"] as? String,
              let commands = manifest["commands"] as? [[String: Any]] else { return [] }
        let extensionPreferences = (manifest["preferences"] as? [[String: Any]] ?? []).compactMap(FieldSpec.init(json:))
        return commands.compactMap { command in
            guard let name = command["name"] as? String else { return nil }
            let mode = command["mode"] as? String ?? "view"
            guard mode == "view" || mode == "no-view" else { return nil }
            return ExtensionCommand(
                extensionDir: folder,
                extensionName: extensionName,
                extensionTitle: manifest["title"] as? String ?? extensionName,
                source: source,
                name: name,
                title: command["title"] as? String ?? name,
                mode: mode,
                icon: command["icon"] as? String ?? manifest["icon"] as? String,
                arguments: (command["arguments"] as? [[String: Any]] ?? []).compactMap(FieldSpec.init(json:)),
                extensionPreferences: extensionPreferences,
                commandPreferences: (command["preferences"] as? [[String: Any]] ?? []).compactMap(FieldSpec.init(json:))
            )
        }
    }
}

struct AppEntry {
    let name: String
    let url: URL
}

struct RootResult: Identifiable {
    let item: RootItem
    /// Shown above the first result of a run with the same title; only set when the query is empty.
    let section: String?
    var id: String { item.id }
}

enum RootItem: Identifiable {
    case app(AppEntry)
    case command(ExtensionCommand)
    case menuBarSearch
    case settings

    static let menuBarSearchKey = "builtin:menubar-search"

    var id: String {
        switch self {
        case .app(let app): "app:\(app.url.path)"
        case .command(let command): "command:\(command.id)"
        case .menuBarSearch: Self.menuBarSearchKey
        case .settings: "settings"
        }
    }

    var title: String {
        switch self {
        case .app(let app): app.name
        case .command(let command): command.title
        case .menuBarSearch: "Search Menu Bar Items"
        case .settings: "Floe Settings"
        }
    }

    var subtitle: String? {
        if case .command(let command) = self { return command.extensionTitle }
        return nil
    }

    /// Key for aliases and hotkeys; commands keep their historical "extension/command" key.
    var settingsKey: String? {
        switch self {
        case .app: id
        case .command(let command): command.id
        case .menuBarSearch: Self.menuBarSearchKey
        case .settings: nil
        }
    }

    var kind: String {
        switch self {
        case .app: "Application"
        case .command: "Command"
        case .menuBarSearch, .settings: "Floe"
        }
    }

    var isApp: Bool {
        if case .app = self { return true }
        return false
    }
}
