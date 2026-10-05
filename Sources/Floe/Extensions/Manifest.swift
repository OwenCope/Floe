//
//  Manifest.swift
//  Project: Floe
//
//  Copyright (Floe) © 2026 René Jiménez
//  Licensed under the GNU AGPLv3

import Foundation

/// A preference or argument declared in an extension manifest, as an editable field.
struct FieldSpec: Identifiable, Decodable, Sendable {
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

    /// The manifest default, kept as one of the four scalars manifests can declare, so the field
    /// stays transferable across actors despite the untyped `defaultValue` interface below.
    private enum DefaultValue: Sendable {
        case bool(Bool)
        case string(String)
        case int(Int)
        case double(Double)
    }

    private let storedDefault: DefaultValue?

    var id: String {
        name
    }

    var isSecret: Bool {
        type == "password"
    }

    /// A default is a string or, for a checkbox, a boolean; it stays untyped because it is passed on as JSON.
    var defaultValue: Any? {
        switch storedDefault {
        case let .bool(value): value
        case let .double(value): value
        case let .int(value): value
        case let .string(value): value
        case nil: nil
        }
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
        // A default is a string or, for a checkbox, a boolean; the scalar order here is the
        // precedence, so a whole number stays an Int and only genuine fractions become Double.
        storedDefault = (try? container.decode(Bool.self, forKey: .defaultValue)).map(DefaultValue.bool)
            ?? (try? container.decode(String.self, forKey: .defaultValue)).map(DefaultValue.string)
            ?? (try? container.decode(Int.self, forKey: .defaultValue)).map(DefaultValue.int)
            ?? (try? container.decode(Double.self, forKey: .defaultValue)).map(DefaultValue.double)
    }
}

/// An array that keeps the elements that decode and drops the rest: one bad entry must not hide the manifest.
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

struct ExtensionCommand: Identifiable, Sendable {
    enum Source: Sendable { case local, raycast }

    let extensionDir: URL
    let extensionName: String
    let extensionTitle: String
    let source: Source
    let name: String
    let title: String
    let mode: String
    let interval: TimeInterval?
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
        let interval: String?
        let icon: String?
        let arguments: Lossy<FieldSpec>?
        let preferences: Lossy<FieldSpec>?
    }

    /// Parses Raycast `interval` strings (`90s`, `10m`, `1h`, `1d`); clamps to at least 10 seconds.
    static func parseInterval(_ raw: String?) -> TimeInterval? {
        guard let raw, !raw.isEmpty else { return nil }
        let multipliers: [Character: Double] = ["s": 1, "m": 60, "h": 3600, "d": 86400]
        guard let unit = raw.last, let factor = multipliers[unit],
              let value = Double(raw.dropLast()), value.isFinite else { return nil }
        return max(value * factor, 10)
    }

    /// The commands a package.json declares that Floe can run: view, no-view and menu-bar.
    static func commands(inManifest data: Data, folder: URL, source: Source) -> [ExtensionCommand] {
        guard let manifest = try? JSONDecoder().decode(Manifest.self, from: data) else { return [] }
        return manifest.commands.elements.compactMap { command in
            let mode = command.mode ?? "view"
            guard mode == "view" || mode == "no-view" || mode == "menu-bar" else { return nil }
            return ExtensionCommand(
                extensionDir: folder,
                extensionName: manifest.name,
                extensionTitle: manifest.title ?? manifest.name,
                source: source,
                name: command.name,
                title: command.title ?? command.name,
                mode: mode,
                interval: parseInterval(command.interval),
                icon: command.icon ?? manifest.icon,
                arguments: command.arguments?.elements ?? [],
                extensionPreferences: manifest.preferences?.elements ?? [],
                commandPreferences: command.preferences?.elements ?? []
            )
        }
    }
}

struct AppEntry: Sendable {
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
    case script(ScriptCommand)
    case menuBarSearch
    case emojiSearch
    case clipboardHistory
    /// Clipboard History while another app keeps the history: the same command, opened there.
    case clipboardApp(ClipboardDestination)
    case fileSearch
    case searchFiles(String)
    case settings
    case calculator(CalculatorResult)
    case system(SystemCommand)
    case settingsPane(SystemSettingsPane)
    /// Something Thaw does when asked through its `thaw://` links.
    case thaw(ThawAction)
    /// The Finder selection, opened in the app a role stands for.
    case finderSelection(AppRole, app: ResolvedApp)
    /// A note for the user's notes app; `text` is what was typed after the action's keyword.
    case note(NoteAction, text: String)
    case event(CalendarEvent)
    case snippet(Snippet)
    case emoji(EmojiResult)
    /// A quicklink matched against the query: `queryText` is the text put into the URL,
    /// and `fallback`/`keywordSearch` rows read as Search … for "…" instead of the link's name.
    case quicklink(Quicklink, queryText: String, fallback: Bool, keywordSearch: Bool)
    /// A scope's rows: a file Spotlight found, a clipboard entry, a menu bar item under the name it is shown by.
    case file(FileResult)
    /// An open browser tab, or the row that stands in for a browser Floe may not ask (see BrowserTabs.swift).
    case browserTab(BrowserTabRow)
    case clipboardEntry(ClipboardEntry)
    case menuBarItem(MenuBarExtra, name: String)
    /// Stands in for the menu bar items until Floe may read them.
    case menuBarAccess
    /// A question for the chosen AI source. Its id leaves the question out, so nothing stores it.
    case askAI(String)
    case webAddress(WebAddress)
    /// A host of the SSH configuration, with the terminal it opens in.
    case sshHost(SSHHost, terminal: ResolvedApp?)

    static let menuBarSearchKey = "builtin:menubar-search"
    static let emojiSearchKey = "builtin:emoji-search"
    static let clipboardHistoryKey = "builtin:clipboard-history"
    static let fileSearchKey = "builtin:file-search"

    var id: String {
        switch self {
        case let .app(app): "app:\(app.url.path)"
        case let .command(command): "command:\(command.id)"
        case let .script(script): "script:\(script.file.lastPathComponent)"
        case .menuBarSearch: Self.menuBarSearchKey
        case .emojiSearch: Self.emojiSearchKey
        case .clipboardHistory, .clipboardApp: Self.clipboardHistoryKey
        case .fileSearch: Self.fileSearchKey
        case let .searchFiles(query): "files-for:\(query)"
        case .settings: "settings"
        case .calculator: "calculator"
        case let .system(command): "system:\(command.rawValue)"
        case let .settingsPane(pane): "settings-pane:\(pane.identifier)"
        case let .note(action, _): "note:\(action.rawValue)"
        case let .thaw(action): "thaw:\(action.rawValue)"
        case let .finderSelection(role, _): "finder-selection:\(role.rawValue)"
        case let .event(event): "event:\(event.identifier)"
        case let .snippet(snippet): "snippet:\(snippet.id.uuidString)"
        case let .emoji(entry): entry.id
        case let .quicklink(link, _, fallback, _):
            (fallback ? "quicklink-fallback:" : "quicklink:") + link.id.uuidString
        case let .file(file): "file:\(file.id)"
        case let .browserTab(row): row.id
        case let .clipboardEntry(entry): "clipboard-entry:\(entry.id.uuidString)"
        case let .menuBarItem(extra, _): "menubar-item:\(extra.id)"
        case .menuBarAccess: "menubar-access"
        case .askAI: "ask-ai"
        case .webAddress: "web-address"
        case let .sshHost(host, _): host.id
        }
    }

    var title: String {
        switch self {
        case let .app(app): app.name
        case let .command(command): command.title
        case let .script(script): script.title
        case .menuBarSearch: "Search Menu Bar Items"
        case .emojiSearch: "Search Emoji & Symbols"
        case .clipboardHistory, .clipboardApp: "Clipboard History"
        case .fileSearch: "Search Files"
        case let .searchFiles(query): "Search Files for \"\(query)\""
        case .settings: "Floe Settings"
        case let .calculator(result): result.value
        case let .system(command): command.title
        case let .settingsPane(pane): pane.title
        case let .note(action, text): action.title(text: text)
        case let .thaw(action): action.title
        case let .finderSelection(_, app): "Open Finder Selection in \(app.name)"
        case let .event(event): event.title
        case let .snippet(snippet): snippet.name
        case let .emoji(entry): entry.name
        case let .quicklink(link, queryText, fallback, keywordSearch):
            if fallback || keywordSearch {
                "Search \(link.name) for \u{201C}\(queryText)\u{201D}"
            } else {
                link.name
            }
        case let .file(file): file.name
        case let .browserTab(row): row.title
        case let .clipboardEntry(entry): entry.title.isEmpty ? entry.kind.rawValue.capitalized : entry.title
        case let .menuBarItem(_, name): name
        case .menuBarAccess: "Floe needs Accessibility to list your menu bar items"
        case let .askAI(question): "Ask AI \u{201C}\(question)\u{201D}"
        case let .webAddress(address): "Open \(address.text)"
        case let .sshHost(host, _): host.alias
        }
    }

    var subtitle: String? {
        switch self {
        case let .command(command):
            return command.extensionTitle
        case let .script(script):
            return script.displayPackage
        case let .calculator(result):
            return result.detail.map { "\(result.expression) · \($0)" } ?? result.expression
        case let .emoji(entry):
            return entry.character
        case let .quicklink(link, _, _, _):
            return link.keyword
        case .system:
            return "System"
        case let .event(event):
            return event.subtitle
        case let .snippet(snippet):
            return snippet.firstLine
        case let .sshHost(host, _):
            return host.subtitle
        default:
            return nil
        }
    }

    /// Key for aliases and hotkeys; commands keep their historical "extension/command" key.
    var settingsKey: String? {
        switch self {
        case .app, .sshHost: id
        case let .command(command): command.id
        case let .script(script): script.id
        case .menuBarSearch: Self.menuBarSearchKey
        case .emojiSearch: Self.emojiSearchKey
        case .clipboardHistory, .clipboardApp: Self.clipboardHistoryKey
        case .fileSearch: Self.fileSearchKey
        case let .system(command): "system:\(command.rawValue)"
        case .snippet: id
        case .settings, .settingsPane, .note, .thaw, .finderSelection, .calculator, .emoji, .quicklink, .searchFiles, .event: nil
        case .file, .clipboardEntry, .menuBarItem, .menuBarAccess, .browserTab, .askAI, .webAddress: nil
        }
    }

    var kind: String {
        switch self {
        case .app: "Application"
        case let .command(command): command.mode == "menu-bar" ? "Menu Bar" : "Command"
        case .script: "Script"
        case .menuBarSearch, .emojiSearch, .clipboardHistory, .settings: "Floe"
        case let .clipboardApp(destination): destination.label
        case .fileSearch, .searchFiles: "Files"
        case .calculator: "Calculator"
        case .system: "System"
        case .settingsPane: "System Settings"
        case .note: "Notes"
        case .thaw: "Thaw"
        case .finderSelection: "Finder"
        case .event: "Event"
        case .snippet: "Snippet"
        case .emoji: "Emoji"
        case .quicklink: "Quicklink"
        case .file: "File"
        case .browserTab: "Browser Tab"
        case .clipboardEntry: "Clipboard"
        case .menuBarItem, .menuBarAccess: "Menu Bar"
        case .askAI: "AI"
        case .webAddress: "Web Address"
        case .sshHost: "SSH"
        }
    }

    /// Other words a result answers to, matched like its title.
    var keywords: [String] {
        switch self {
        case let .system(command): command.keywords
        case let .settingsPane(pane): pane.keywords
        case let .note(action, _): action == .new ? AppRole.notes.keywords : ["add to note"]
        case let .thaw(action): action.keywords
        case let .finderSelection(role, _): role.keywords
        case .clipboardApp: AppRole.clipboard.keywords
        case let .snippet(snippet): [snippet.keyword]
        case let .sshHost(host, _): host.keywords
        default: []
        }
    }
}
