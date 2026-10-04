//
//  ThawIntegration.swift
//  Project: Floe
//
//  Copyright (Floe) © 2026 René Jiménez
//  Licensed under the GNU AGPLv3

import AppKit

/// What Floe can ask Thaw to do, through the `thaw://` links Thaw 3 answers. The names are the
/// ones Thaw's own hotkey settings use, so an action reads the same in both apps.
enum ThawAction: String, CaseIterable, Identifiable {
    case toggleHidden
    case toggleAlwaysHidden
    case toggleSwap
    case search
    case itemHints
    case toggleThawBar
    case toggleApplicationMenus
    case toggleZenMode
    case toggleLayoutEditor
    case openSettings
    case toggleAutoRehide
    case toggleShowOnHover
    case toggleHideApplicationMenus
    case authorize

    var id: String {
        rawValue
    }

    var title: String {
        switch self {
        case .toggleHidden: "Toggle the Hidden Section"
        case .toggleAlwaysHidden: "Toggle the Always Hidden Section"
        case .toggleSwap: "Swap Shown and Hidden Items"
        case .search: "Search Menu Bar Items in Thaw"
        case .itemHints: "Open an Item by Letter"
        case .toggleThawBar: "Turn Thaw Bar On or Off"
        case .toggleApplicationMenus: "Toggle Application Menus"
        case .toggleZenMode: "Toggle Zen Mode"
        case .toggleLayoutEditor: "Show Layout"
        case .openSettings: "Thaw Settings"
        case .toggleAutoRehide: "Toggle Automatic Rehiding"
        case .toggleShowOnHover: "Toggle Show on Hover"
        case .toggleHideApplicationMenus: "Toggle Hiding Application Menus"
        case .authorize: "Allow Floe to Change Thaw Settings"
        }
    }

    /// The path and query after `thaw://`, as Thaw 3's URL handler reads them.
    var link: String {
        switch self {
        case .toggleHidden: "toggle-hidden"
        case .toggleAlwaysHidden: "toggle-always-hidden"
        case .toggleSwap: "toggle-swap"
        case .search: "search"
        case .itemHints: "item-hints"
        case .toggleThawBar: "toggle-thawbar"
        case .toggleApplicationMenus: "toggle-application-menus"
        case .toggleZenMode: "toggle-zen-mode"
        case .toggleLayoutEditor: "toggle-layout-editor"
        case .openSettings: "open-settings"
        case .toggleAutoRehide: "toggle?key=autoRehide"
        case .toggleShowOnHover: "toggle?key=showOnHover"
        case .toggleHideApplicationMenus: "toggle?key=hideApplicationMenus"
        case .authorize: "authorize"
        }
    }

    var url: URL? {
        URL(string: "thaw://\(link)")
    }

    /// The three that change a setting only work once Thaw has Floe on its list of allowed apps.
    var changesASetting: Bool {
        switch self {
        case .toggleAutoRehide, .toggleShowOnHover, .toggleHideApplicationMenus: true
        default: false
        }
    }

    var keywords: [String] {
        switch self {
        case .toggleHidden: ["thaw", "menu bar", "hidden", "show hidden"]
        case .toggleAlwaysHidden: ["thaw", "menu bar", "always hidden"]
        case .toggleSwap: ["thaw", "menu bar", "swap"]
        case .search: ["thaw", "menu bar", "find item"]
        case .itemHints: ["thaw", "item hints", "letters"]
        case .toggleThawBar: ["thaw", "thawbar", "bar"]
        case .toggleApplicationMenus: ["thaw", "app menus", "menus"]
        case .toggleZenMode: ["thaw", "zen", "focus"]
        case .toggleLayoutEditor: ["thaw", "edit layout", "arrange"]
        case .openSettings: ["thaw", "preferences", "open settings"]
        case .toggleAutoRehide: ["thaw", "rehide", "auto hide"]
        case .toggleShowOnHover: ["thaw", "hover", "reveal"]
        case .toggleHideApplicationMenus: ["thaw", "hide menus"]
        case .authorize: ["thaw", "authorize", "permission", "automation"]
        }
    }
}

enum Thaw {
    /// Where the app that answers `thaw://` links is, release or debug build; nil when none is installed.
    static var applicationURL: URL? {
        URL(string: "thaw://").flatMap { NSWorkspace.shared.urlForApplication(toOpen: $0) }
    }

    /// The actions to list: all of them with Thaw installed, none without.
    static func actions(isInstalled: Bool = applicationURL != nil) -> [ThawAction] {
        isInstalled ? ThawAction.allCases : []
    }

    /// Hands the link to Thaw and answers whether there was an app to take it.
    @discardableResult
    static func perform(_ action: ThawAction) -> Bool {
        guard let url = action.url, applicationURL != nil else { return false }
        return NSWorkspace.shared.open(url)
    }
}
