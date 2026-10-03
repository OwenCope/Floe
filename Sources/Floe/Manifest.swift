//
//  Manifest.swift
//  Project: Floe
//
//  Copyright (Floe) © 2026 René Jiménez
//  Licensed under the GNU GPLv3

import Foundation

/// A preference or argument declared in an extension manifest, as an editable field.
struct FieldSpec: Identifiable, Decodable {
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

    var id: String {
        name
    }

    var isSecret: Bool {
        type == "password"
    }

    private enum CodingKeys: String, CodingKey {
        case name, title, type, required, placeholder, label
        case detail = "description"
        case options = "data"
        case defaultValue = "default"
    }

    private struct Option: Decodable {
        let title: String?
        let value: String
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.name = try container.decode(String.self, forKey: .name)
        self.placeholder = try container.decodeIfPresent(String.self, forKey: .placeholder)
        self.title = try container.decodeIfPresent(String.self, forKey: .title) ?? placeholder ?? name
        self.detail = try container.decodeIfPresent(String.self, forKey: .detail)
        self.type = try container.decodeIfPresent(String.self, forKey: .type) ?? "textfield"
        self.required = try container.decodeIfPresent(Bool.self, forKey: .required) ?? false
        self.label = try container.decodeIfPresent(String.self, forKey: .label)
        self.options = try (container.decodeIfPresent(Lossy<Option>.self, forKey: .options)?.elements ?? [])
            .map { ($0.title ?? $0.value, $0.value) }
        // A default is a string or, for a checkbox, a boolean; it stays untyped because it is passed on as JSON.
        self.defaultValue = (try? container.decode(Bool.self, forKey: .defaultValue))
            ?? (try? container.decode(String.self, forKey: .defaultValue))
            ?? (try? container.decode(Int.self, forKey: .defaultValue))
            ?? (try? container.decode(Double.self, forKey: .defaultValue))
    }
}

/// An array that keeps the elements that decode and drops the rest, so one malformed entry
/// doesn't hide the whole manifest.
struct Lossy<Element: Decodable>: Decodable {
    private struct Skipped: Decodable {}

    let elements: [Element]

    init(from decoder: Decoder) throws {
        var container = try decoder.unkeyedContainer()
        var elements: [Element] = []
        while !container.isAtEnd {
            if let element = try? container.decode(Element.self) {
                elements.append(element)
            } else {
                // A failed decode leaves the container where it was.
                _ = try container.decode(Skipped.self)
            }
        }
        self.elements = elements
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

    var id: String {
        "\(extensionName)/\(name)"
    }

    var assetsPath: String {
        extensionDir.appendingPathComponent("assets").path
    }

    var preferences: [FieldSpec] {
        extensionPreferences + commandPreferences
    }

    private struct Manifest: Decodable {
        let name: String
        let title: String?
        let icon: String?
        let preferences: Lossy<FieldSpec>?
        let commands: Lossy<ManifestCommand>
    }

    private struct ManifestCommand: Decodable {
        let name: String
        let title: String?
        let mode: String?
        let icon: String?
        let arguments: Lossy<FieldSpec>?
        let preferences: Lossy<FieldSpec>?
    }

    /// The commands a package.json declares that Floe can run: view and no-view, not menu-bar.
    static func commands(inManifest data: Data, folder: URL, source: Source) -> [ExtensionCommand] {
        guard let manifest = try? JSONDecoder().decode(Manifest.self, from: data) else { return [] }
        return manifest.commands.elements.compactMap { command in
            let mode = command.mode ?? "view"
            guard mode == "view" || mode == "no-view" else { return nil }
            return ExtensionCommand(
                extensionDir: folder,
                extensionName: manifest.name,
                extensionTitle: manifest.title ?? manifest.name,
                source: source,
                name: command.name,
                title: command.title ?? command.name,
                mode: mode,
                icon: command.icon ?? manifest.icon,
                arguments: command.arguments?.elements ?? [],
                extensionPreferences: manifest.preferences?.elements ?? [],
                commandPreferences: command.preferences?.elements ?? []
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
    var id: String {
        item.id
    }
}

enum RootItem: Identifiable {
    case app(AppEntry)
    case command(ExtensionCommand)
    case menuBarSearch
    case settings

    static let menuBarSearchKey = "builtin:menubar-search"

    var id: String {
        switch self {
        case let .app(app): "app:\(app.url.path)"
        case let .command(command): "command:\(command.id)"
        case .menuBarSearch: Self.menuBarSearchKey
        case .settings: "settings"
        }
    }

    var title: String {
        switch self {
        case let .app(app): app.name
        case let .command(command): command.title
        case .menuBarSearch: "Search Menu Bar Items"
        case .settings: "Floe Settings"
        }
    }

    var subtitle: String? {
        if case let .command(command) = self {
            return command.extensionTitle
        }
        return nil
    }

    /// Key for aliases and hotkeys; commands keep their historical "extension/command" key.
    var settingsKey: String? {
        switch self {
        case .app: id
        case let .command(command): command.id
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
        if case .app = self {
            return true
        }
        return false
    }
}
