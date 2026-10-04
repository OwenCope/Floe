//
//  SettingsSearchEntries.swift
//  Project: Floe
//
//  Copyright (Floe) © 2026 René Jiménez
//  Licensed under the GNU AGPLv3

import Foundation

extension SearchPaneLabel {
    static let general = SearchPaneLabel(title: "General", symbol: "gearshape")
    static let applications = SearchPaneLabel(title: "Applications", symbol: "square.grid.2x2")
    static let quicklinks = SearchPaneLabel(title: "Quicklinks", symbol: "link")
    static let snippets = SearchPaneLabel(title: "Snippets", symbol: "text.quote")
    static let extensionStore = SearchPaneLabel(title: "Extension Store", symbol: "bag")
    static let appearance = SearchPaneLabel(title: "Appearance", symbol: "paintbrush")
    static let privacy = SearchPaneLabel(title: "Privacy", symbol: "hand.raised")
    static let about = SearchPaneLabel(title: "About", symbol: "info.circle")
}

extension SearchEntry {
    /// An entry on the Appearance pane.
    static func appearance(
        _ id: String,
        _ title: String,
        description: String? = nil,
        section: String? = nil,
        keywords: [String]
    ) -> SearchEntry {
        SearchEntry(
            id: "appearance.\(id)",
            title: title,
            descriptionText: description,
            pane: .appearance,
            paneLabel: .appearance,
            section: section,
            keywords: keywords
        )
    }

    /// An entry on the Quicklinks pane.
    static func quicklinks(
        _ id: String,
        _ title: String,
        description: String? = nil,
        section: String? = nil,
        keywords: [String]
    ) -> SearchEntry {
        SearchEntry(
            id: "quicklinks.\(id)",
            title: title,
            descriptionText: description,
            pane: .quicklinks,
            paneLabel: .quicklinks,
            section: section,
            keywords: keywords
        )
    }

    /// An entry on the General pane.
    static func general(
        _ id: String,
        _ title: String,
        description: String? = nil,
        section: String? = nil,
        keywords: [String]
    ) -> SearchEntry {
        SearchEntry(
            id: "general.\(id)",
            title: title,
            descriptionText: description,
            pane: .general,
            paneLabel: .general,
            section: section,
            keywords: keywords
        )
    }
}

/// What the settings search can find: one entry per control in the settings window.
///
/// Titles, sections and descriptions repeat what the panes in SettingsView.swift show. A pane
/// that gains a control adds an entry to its list here; a new pane adds a list and appends it
/// to SearchIndex.staticEntries.
extension SearchIndex {
    /// The panes themselves, so typing a pane's name finds it. Applications and About have no
    /// entries beyond these: one is a list of apps with its own filter, the other has no settings.
    static let paneEntries: [SearchEntry] = [
        SearchEntry(
            id: "pane.appearance",
            title: "Appearance",
            descriptionText: "Tint, border and shadow for the launcher panel.",
            pane: .appearance,
            paneLabel: .appearance,
            keywords: ["appearance", "glass", "tint", "colour", "color", "gradient", "border", "shadow", "theme", "style"]
        ),
        SearchEntry(
            id: "pane.privacy",
            title: "Privacy",
            descriptionText: "Permissions and what Floe contacts.",
            pane: .privacy,
            paneLabel: .privacy,
            keywords: ["privacy", "permissions", "network", "analytics", "tracking", "data"]
        ),
        SearchEntry(
            id: "pane.general",
            title: "General",
            pane: .general,
            paneLabel: .general,
            keywords: ["settings", "preferences", "options"]
        ),
        SearchEntry(
            id: "pane.applications",
            title: "Applications",
            descriptionText: "Aliases and hotkeys for apps.",
            pane: .applications,
            paneLabel: .applications,
            keywords: ["apps", "alias", "hotkey", "shortcut", "keyboard", "filter"]
        ),
        SearchEntry(
            id: "pane.quicklinks",
            title: "Quicklinks",
            descriptionText: "Keywords and fallbacks for web search.",
            pane: .quicklinks,
            paneLabel: .quicklinks,
            keywords: ["quicklink", "quicklinks", "keyword", "search", "web", "fallback", "link", "url"]
        ),
        SearchEntry(
            id: "pane.snippets",
            title: "Snippets",
            descriptionText: "Text you paste or type by keyword.",
            pane: .snippets,
            paneLabel: .snippets,
            keywords: ["snippet", "snippets", "text", "expansion", "expand", "keyword", "abbreviation", "template"]
        ),
        SearchEntry(
            id: "pane.extensionStore",
            title: "Extension Store",
            descriptionText: "Install, update and remove extensions from the Raycast store.",
            pane: .extensionStore,
            paneLabel: .extensionStore,
            keywords: ["store", "install", "update", "remove", "download", "extensions", "browse", "raycast"]
        ),
        SearchEntry(
            id: "pane.about",
            title: "About",
            pane: .about,
            paneLabel: .about,
            keywords: [
                "version",
                "build",
                "commit",
                "license",
                "credits",
                "acknowledgements",
                "source code",
                "github",
                "discord",
                "report a bug",
                "data folder",
            ]
        ),
    ]

    static let appearanceEntries: [SearchEntry] = [
        .appearance("followThaw", "Follow Thaw's Appearance", section: "Thaw", keywords: ["thaw", "follow", "match", "mirror", "sync", "same look"]),
        .appearance("launcherLayout", "Launcher Layout", section: "Layout", keywords: ["layout", "compact", "extended", "size", "search bar", "list"]),
        .appearance("glassEffect", "Glass Effect", section: "Glass", keywords: ["glass", "liquid", "dynamic", "clear", "regular", "effect", "material"]),
        .appearance("tintStyle", "Tint", section: "Tint", keywords: ["tint", "colour", "color", "style", "solid", "gradient", "none"]),
        .appearance("tintColor", "Tint Colour", section: "Tint", keywords: ["tint", "colour", "color", "picker"]),
        .appearance("tintOpacity", "Tint Opacity", section: "Tint", keywords: ["tint", "opacity", "strength", "transparency"]),
        .appearance("border", "Border", section: "Border", keywords: ["border", "outline", "stroke", "edge", "width"]),
        .appearance("shadow", "Drop Shadow", section: "Shadow", keywords: ["shadow", "depth", "drop"]),
    ]

    static let privacyEntries: [SearchEntry] = [
        privacy("permissions", "Permissions", section: "Permissions", keywords: ["privacy", "security", "access", "grant", "allow", "accessibility"]),
        privacy("accessibility", "Accessibility", section: "Permissions", keywords: ["permission", "privacy", "access", "grant", "trusted", "menu bar"]),
        privacy("network", "Network Access", section: "Network Access", keywords: ["network", "internet", "updates", "github", "ai", "requests", "analytics"]),
        privacy("searchSources", "Search Sources", section: "Search Sources", keywords: ["sources", "root search", "results", "sections"]),
        privacy("searchSources.files", "Files", section: "Search Sources", keywords: ["file search", "spotlight", "documents", "source"]),
        privacy("searchSources.tabs", "Browser Tabs", section: "Search Sources", keywords: ["tabs", "browser", "safari", "open tabs", "automation", "applescript", "source"]),
    ]

    private static func privacy(_ id: String, _ title: String, section: String, keywords: [String]) -> SearchEntry {
        SearchEntry(id: "privacy.\(id)", title: title, pane: .privacy, paneLabel: .privacy, section: section, keywords: keywords)
    }

    static let generalEntries: [SearchEntry] = [
        .general(
            "toggleHotkey",
            "Open Floe",
            section: "Floe",
            keywords: ["hotkey", "shortcut", "keyboard", "global", "toggle", "show", "launcher", "summon"]
        ),
        .general(
            "launchAtLogin",
            "Launch at Login",
            section: "Floe",
            keywords: ["startup", "start", "boot", "login item", "autostart", "open at login"]
        ),
        .general(
            "showInDock",
            "Show in Dock",
            section: "Floe",
            keywords: ["dock", "icon", "menu bar", "hide", "app switcher"]
        ),
        .general(
            "popToRootDelay",
            "Return to root search",
            description: "How long a closed launcher keeps the command you had open.",
            section: "Floe",
            keywords: ["pop to root", "delay", "timeout", "reset", "close", "immediately", "seconds", "minutes"]
        ),
        .general(
            "checkForUpdates",
            "Automatically check for updates",
            keywords: ["check for updates", "update", "updates", "automatic", "upgrade", "new version"]
        ),
        .general(
            "menuBarSearchHotkey",
            "Search Menu Bar Items",
            description: "Find an item in the menu bar and open its menu.",
            section: "Menu Bar Items",
            keywords: ["hotkey", "shortcut", "keyboard", "menu bar", "status items", "icons"]
        ),
        .general(
            "menuBarSearchAlias",
            "Alias",
            section: "Menu Bar Items",
            keywords: ["menu bar", "keyword", "abbreviation", "short name"]
        ),
        .general(
            "thawSupport",
            "Thaw",
            description: "Thaw's actions are in the search: type “thaw” to see them.",
            section: "Menu Bar Items",
            keywords: ["thaw", "hidden items", "thaw bar", "menu bar manager"]
        ),
        .general(
            "menuBarCommands",
            "Extension Commands in the Menu Bar",
            description: "Which extension commands have an item in the menu bar.",
            section: "Menu Bar Commands",
            keywords: ["status item", "extension", "show", "remove"]
        ),
        .general(
            "terminalApp",
            "Terminal",
            description: AppRole.terminal.detail,
            section: "Preferred Apps",
            keywords: ["terminal", "shell", "command line", "open in terminal", "preferred app", "default app"]
        ),
        .general(
            "editorApp",
            "Editor",
            description: AppRole.editor.detail,
            section: "Preferred Apps",
            keywords: ["editor", "text editor", "code", "open in editor", "preferred app", "default app"]
        ),
        .general(
            "notesApp",
            "Notes",
            description: AppRole.notes.detail,
            section: "Preferred Apps",
            keywords: ["notes", "notes app", "apple notes", "antinote", "new note", "quick note", "capture", "preferred app"]
        ),
        .general(
            "clipboardHistory",
            "Save clipboard history",
            description: "Keeps text, links, images and files you copy.",
            section: "Clipboard",
            keywords: ["clipboard", "history", "copy", "paste", "copies", "pin", "clear"]
        ),
        .general(
            "clearClipboardHistory",
            "Clear clipboard history",
            description: "Removes every copy except pinned ones.",
            section: "Clipboard",
            keywords: ["clipboard", "history", "clear", "delete", "remove", "copies"]
        ),
        .general(
            "transferSettings",
            "Export or import settings",
            description: "Moves aliases, hotkeys, favorites, appearance and extension preferences to another Mac.",
            section: "Your Settings",
            keywords: ["export", "import", "backup", "transfer", "move", "file", "restore"]
        ),
        .general(
            "includeRaycastExtensions",
            "Include extensions installed in Raycast",
            description: "Reads ~/.config/raycast/extensions. Their Raycast settings don't carry over.",
            section: "Extensions",
            keywords: ["raycast", "import", "store", "installed"]
        ),
        .general(
            "extensionsFolder",
            "Extensions folder",
            section: "Extensions",
            keywords: ["finder", "directory", "location", "path", "install", "show in finder"]
        ),
        .general(
            "runtime",
            "Runtime",
            section: "Extensions",
            keywords: ["bun", "javascript", "node", "engine"]
        ),
        .general(
            "scriptsFolder",
            "Scripts folder",
            section: "Script Commands",
            keywords: ["script", "scripts", "script commands", "raycast", "finder", "directory", "new script"]
        ),
        .general(
            "aiSource",
            "Answer AI requests with",
            description: "Extensions that ask AI a question get their answer from here.",
            section: "AI",
            keywords: ["ai", "ask", "claude", "codex", "openai", "apple intelligence", "ollama", "lm studio", "local", "model", "llm", "assistant", "provider"]
        ),
        .general(
            "aiAddress",
            "Address",
            section: "AI",
            keywords: ["ai", "api", "base url", "endpoint", "openai", "server", "host"]
        ),
        .general(
            "aiModel",
            "Model",
            section: "AI",
            keywords: ["ai", "api", "model", "gpt", "openai"]
        ),
        .general(
            "aiKey",
            "API key",
            section: "AI",
            keywords: ["ai", "api", "key", "token", "secret", "keychain", "openai"]
        ),
    ]

    static let quicklinksEntries: [SearchEntry] = [
        .quicklinks(
            "list",
            "Quicklinks",
            section: "Quicklinks",
            keywords: ["quicklink", "keyword", "link", "name", "url", "list", "edit", "delete"]
        ),
        .quicklinks(
            "new",
            "New Quicklink",
            section: "Quicklinks",
            keywords: ["new", "add", "create", "quicklink"]
        ),
        .quicklinks(
            "name",
            "Name",
            section: "Quicklink",
            keywords: ["name", "title", "label"]
        ),
        .quicklinks(
            "keyword",
            "Keyword",
            section: "Quicklink",
            keywords: ["keyword", "abbreviation", "prefix", "trigger"]
        ),
        .quicklinks(
            "url",
            "URL",
            section: "Quicklink",
            keywords: ["url", "link", "address", "query", "template"]
        ),
        .quicklinks(
            "symbol",
            "Symbol",
            section: "Quicklink",
            keywords: ["symbol", "icon", "glyph"]
        ),
        .quicklinks(
            "fallback",
            "Use as fallback",
            section: "Quicklink",
            keywords: ["fallback", "default", "search", "results"]
        ),
        .quicklinks(
            "fallbacks",
            "Fallbacks",
            description: "Shown under your results when you search.",
            section: "Fallbacks",
            keywords: ["fallback", "fallbacks", "order", "reorder", "default", "results", "bottom"]
        ),
    ]

    /// One group per extension: the extension, its preferences, then each command and the
    /// command's preferences. Extensions follow the sidebar's order, by title.
    static func extensionEntries(for commands: [ExtensionCommand]) -> [SearchEntry] {
        var order: [String] = []
        var byExtension: [String: [ExtensionCommand]] = [:]
        for command in commands {
            if byExtension[command.extensionName] == nil {
                order.append(command.extensionName)
            }
            byExtension[command.extensionName, default: []].append(command)
        }
        return order.compactMap { byExtension[$0] }
            .sorted { lhs, rhs in
                guard let left = lhs.first, let right = rhs.first else { return false }
                return left.extensionTitle.localizedCaseInsensitiveCompare(right.extensionTitle) == .orderedAscending
            }
            .flatMap(entries(forExtension:))
    }

    private static func entries(forExtension commands: [ExtensionCommand]) -> [SearchEntry] {
        guard let first = commands.first else { return [] }
        let name = first.extensionName
        let pane = SettingsPage.extensionPage(name)
        let label = SearchPaneLabel(title: first.extensionTitle, icon: first.icon ?? "icon:Terminal", assetsPath: first.assetsPath)

        var entries = [
            SearchEntry(
                id: "extension.\(name)",
                title: first.extensionTitle,
                pane: pane,
                paneLabel: label,
                keywords: [name, "extension", "enabled", "enable", "disable"] + (first.source == .raycast ? ["raycast"] : [])
            ),
        ]
        entries += first.extensionPreferences.map { field in
            SearchEntry(
                id: "extension.\(name).preference.\(field.name)",
                title: field.title,
                descriptionText: field.detail,
                pane: pane,
                paneLabel: label,
                section: "Preferences",
                keywords: [field.name]
            )
        }
        for command in commands {
            entries.append(SearchEntry(
                id: "command.\(command.id)",
                title: command.title,
                pane: pane,
                paneLabel: label,
                section: "Command",
                keywords: [command.name],
                anchor: command.id
            ))
            entries += command.commandPreferences.map { field in
                SearchEntry(
                    id: "command.\(command.id).preference.\(field.name)",
                    title: field.title,
                    descriptionText: field.detail,
                    pane: pane,
                    paneLabel: label,
                    section: command.title,
                    keywords: [field.name],
                    anchor: command.id
                )
            }
        }
        return entries
    }
}
