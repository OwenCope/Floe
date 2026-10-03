//
//  SettingsSearchEntries.swift
//  Project: Floe
//
//  Copyright (Floe) © 2026 René Jiménez
//  Licensed under the GNU GPLv3

import Foundation

extension SearchPaneLabel {
    static let general = SearchPaneLabel(title: "General", symbol: "gearshape")
    static let applications = SearchPaneLabel(title: "Applications", symbol: "square.grid.2x2")
    static let about = SearchPaneLabel(title: "About", symbol: "info.circle")
}

extension SearchEntry {
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
            "permissions",
            "Permissions",
            section: "Permissions",
            keywords: ["privacy", "security", "access", "grant", "allow", "accessibility"]
        ),
        .general(
            "accessibility",
            "Accessibility",
            section: "Permissions",
            keywords: ["permission", "privacy", "access", "grant", "trusted", "menu bar"]
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
