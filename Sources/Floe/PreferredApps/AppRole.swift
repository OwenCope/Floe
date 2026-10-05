//
//  AppRole.swift
//  Project: Floe
//
//  Copyright (Floe) © 2026 René Jiménez
//  Licensed under the GNU AGPLv3

import Foundation

/// A kind of app the user has a preferred one of. Floe hands things to that app and does none of its work.
enum AppRole: String, CaseIterable, Identifiable {
    case terminal
    case editor
    case browser
    case notes
    case clipboard

    /// What a role's app is handed.
    enum Input {
        /// A folder; a file stands for the folder it is in.
        case folder
        case fileOrFolder
        /// Text typed into the search, sent through a link or a script the app answers (see `Notes`).
        case text
        /// A web link, one at a time (see `Browsers`).
        case link
        /// Nothing: the app is opened to show what it already has (see `ClipboardApps`).
        case nothing
    }

    var id: String {
        rawValue
    }

    /// The role's name in Settings.
    var title: String {
        switch self {
        case .terminal: "Terminal"
        case .editor: "Editor"
        case .browser: "Browser"
        case .notes: "Notes"
        case .clipboard: "Clipboard"
        }
    }

    var input: Input {
        switch self {
        case .terminal: .folder
        case .editor: .fileOrFolder
        case .browser: .link
        case .notes: .text
        case .clipboard: .nothing
        }
    }

    /// The line under the role's picker in Settings.
    var detail: String {
        switch self {
        case .terminal: "Opens a folder from the Actions menu or from Finder, and the SSH hosts you pick in the search."
        case .editor: "Opens a file or a folder from the Actions menu or from Finder."
        case .browser: "Opens web addresses, quicklinks and the other web links you open from Floe."
        case .notes: "Type “note” and then your text in the search to send it there."
        case .clipboard: "Opens from Clipboard History in the search. With another app chosen, Floe saves no copies and keeps the history it has."
        }
    }

    /// The terminal every Mac has, which the terminal role uses until another is chosen.
    static let systemTerminal = "com.apple.Terminal"

    /// Bundle identifiers of the apps offered by name when they are installed. Each one was read from
    /// the Info.plist of an installed copy; an app that is not here is picked with Choose.
    var knownApps: [String] {
        switch self {
        case .terminal: ["com.mitchellh.ghostty"]
        case .editor: ["com.apple.TextEdit", "com.microsoft.VSCode", "dev.zed.Zed", "com.apple.dt.Xcode"]
        // The browsers are read from the system when the picker is shown (see `Browsers`).
        case .browser: []
        // Notes go to an app Floe knows how to hand text to, which `NotesApp` lists.
        case .notes: []
        // Raycast's history opens from a link, which `ClipboardApps.links` holds.
        case .clipboard: ["com.raycast.macos"]
        }
    }

    /// Other words the role's search rows answer to.
    var keywords: [String] {
        switch self {
        case .terminal: ["terminal", "shell", "command line", "finder selection"]
        case .editor: ["editor", "edit", "code", "finder selection"]
        case .browser: ["browser", "web", "links"]
        case .notes: ["notes", "jot", "memo"]
        case .clipboard: ["clipboard", "copies", "paste"]
        }
    }

    /// How the picker names the choice of nothing, given the app that stands in for it.
    func defaultTitle(appName: String?) -> String {
        switch self {
        case .terminal: appName ?? "Terminal"
        case .editor: appName.map { "Default for Text Files (\($0))" } ?? "Default for Text Files"
        case .browser: appName.map { "Default Browser (\($0))" } ?? "Default Browser"
        case .notes: NotesApp.appleNotes.title
        case .clipboard: "Floe"
        }
    }

    /// The roles whose app is handed files and folders.
    static var opening: [AppRole] {
        allCases.filter { $0.input == .folder || $0.input == .fileOrFolder }
    }
}

/// The app chosen for a role: its bundle identifier, so a moved or updated copy still resolves,
/// and the path it was picked at for an app without one.
struct AppChoice: Codable, Hashable {
    var bundleIdentifier: String?
    var path: String

    /// What tells one choice from another whatever folder the app is in now.
    var key: String {
        bundleIdentifier ?? path
    }
}

/// An application on this Mac, named as its bundle is.
struct ResolvedApp: Hashable {
    let url: URL

    var name: String {
        url.deletingPathExtension().lastPathComponent
    }
}

/// A role with the app it resolves to right now.
struct RoleApp: Hashable {
    let role: AppRole
    let app: ResolvedApp
}
