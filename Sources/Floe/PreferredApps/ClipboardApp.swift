//
//  ClipboardApp.swift
//  Project: Floe
//
//  Copyright (Floe) © 2026 René Jiménez
//  Licensed under the GNU AGPLv3

import AppKit

/// What keeps the clipboard history: Floe, an app, or an app that shows its history from a link.
enum ClipboardHandler: String, Codable, CaseIterable {
    case floe
    case app
    case link
}

/// Where the Clipboard History command goes right now.
enum ClipboardDestination: Hashable {
    /// Floe's own history, in the panel.
    case floe
    case app(ResolvedApp)
    /// A link, and the app that answers it when there is one to name.
    case link(URL, app: ResolvedApp?)
    /// Nothing can be opened: the chosen app when it has a name, and what the HUD says.
    case unavailable(app: String?, message: String)

    /// The app whose icon the command's row shows.
    var app: ResolvedApp? {
        switch self {
        case let .app(app): app
        case let .link(_, app): app
        case .floe, .unavailable: nil
        }
    }

    /// The text at the right edge of the command's row: where it goes.
    var label: String {
        switch self {
        case .floe: "Floe"
        case let .app(app): app.name
        case let .link(_, app): app?.name ?? ClipboardApps.linkTitle
        case let .unavailable(app, _): app ?? String(localized: "Not Set Up", bundle: .floe, comment: "Shown where the name of the clipboard app would be when none can be opened.")
        }
    }
}

/// Opens another app's clipboard history. Tests pass their own, so nothing is opened.
struct ClipboardOpener {
    var app: (URL) -> Void
    /// The link, in the app when it is known which one answers it.
    var link: (URL, URL?) -> Void

    static let system = ClipboardOpener(
        app: { url in
            // A clipboard manager that is already running takes being opened again as "show your window".
            let configuration = NSWorkspace.OpenConfiguration()
            configuration.activates = true
            NSWorkspace.shared.openApplication(at: url, configuration: configuration)
        },
        link: { url, application in
            if let application {
                NSWorkspace.shared.open([url], withApplicationAt: application, configuration: NSWorkspace.OpenConfiguration())
            } else {
                NSWorkspace.shared.open(url)
            }
        }
    )
}

/// The clipboard role: Floe keeps the history itself, or hands the command to the manager already in use.
enum ClipboardApps {
    /// The picker's row for a link, and the row label of a link no app is named for.
    static let linkTitle = String(localized: "Link", bundle: .floe, comment: "A web style link that opens an app, as a choice in a picker and as the label of its field.")

    /// Apps whose history opens from a link, by bundle identifier. Both were read from the installed
    /// copy: the identifier from its Info.plist, the link from how the app builds its own deeplinks.
    static let links = ["com.raycast.macos": "raycast://extensions/raycast/clipboard-history/clipboard-history"]

    /// Floe saves copies only while it is the clipboard manager and its switch is on.
    static func records(handler: ClipboardHandler, historyEnabled: Bool) -> Bool {
        handler == .floe && historyEnabled
    }

    /// A link as typed: a URL with a scheme, or nil.
    static func url(from link: String) -> URL? {
        let trimmed = link.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let url = URL(string: trimmed), url.scheme?.isEmpty == false else { return nil }
        return url
    }

    /// Where the command goes. A choice that cannot be opened says so and never becomes Floe's history.
    static func destination(handler: ClipboardHandler, choice: AppChoice?, link: String, installed: AppLookup) -> ClipboardDestination {
        switch handler {
        case .floe:
            return .floe
        case .app:
            guard let choice else {
                return .unavailable(app: nil, message: String(localized: "Choose a clipboard app in Settings", bundle: .floe))
            }
            guard let app = PreferredApps.chosenApp(choice, installed: installed) else {
                let name = ResolvedApp(url: URL(fileURLWithPath: choice.path)).name
                return .unavailable(app: name, message: String(localized: "\(name) isn't installed", bundle: .floe, comment: "The placeholder is the name of an app."))
            }
            let known = (choice.bundleIdentifier ?? installed.bundleIdentifier(app.url)).flatMap { links[$0] }
            return known.flatMap(URL.init(string:)).map { .link($0, app: app) } ?? .app(app)
        case .link:
            guard !link.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                return .unavailable(app: nil, message: String(localized: "Set a link for your clipboard app in Settings", bundle: .floe))
            }
            guard let url = url(from: link) else {
                return .unavailable(app: nil, message: String(localized: "The clipboard link isn't a URL. Change it in Settings", bundle: .floe))
            }
            guard let answering = installed.appForURL(url) else {
                return .unavailable(app: nil, message: String(localized: "No app opens the clipboard link. Change it in Settings", bundle: .floe))
            }
            return .link(url, app: ResolvedApp(url: answering))
        }
    }

    /// The scopes the root search offers: the “clipboard” scope searches Floe's history, so it goes with it.
    static func scopes(_ scopes: [any SearchScope], handler: ClipboardHandler) -> [any SearchScope] {
        handler == .floe ? scopes : scopes.filter { !($0 is ClipboardSearchScope) }
    }

    /// The command's row: Floe's own, or one that shows where it goes.
    static func row(for destination: ClipboardDestination) -> RootItem {
        destination == .floe ? .clipboardHistory : .clipboardApp(destination)
    }

    /// Why the history switch in Settings is off, or nil while Floe keeps the history.
    static func settingsNotice(for destination: ClipboardDestination) -> String? {
        switch destination {
        case .floe: nil
        case let .app(app): handled(by: app.name)
        case let .link(_, app): handled(by: app?.name)
        case let .unavailable(app, _): handled(by: app)
        }
    }
}

extension ClipboardApps {
    private static func handled(by app: String?) -> String {
        guard let app else {
            return String(localized: "Clipboard history is handled by another app. Floe saves no copies.", bundle: .floe)
        }
        return String(localized: "Clipboard history is handled by \(app). Floe saves no copies.", bundle: .floe, comment: "The placeholder is the name of an app.")
    }
}

extension AppSettings {
    /// Whether copies are saved now: the user's switch, and Floe being the clipboard manager.
    var recordsClipboardHistory: Bool {
        ClipboardApps.records(handler: clipboardHandler, historyEnabled: clipboardHistoryEnabled)
    }

    func clipboardDestination(installed: AppLookup) -> ClipboardDestination {
        ClipboardApps.destination(handler: clipboardHandler, choice: clipboardApp, link: clipboardURL, installed: installed)
    }
}

extension SearchIndex {
    /// The clipboard's controls on the General page: the role's picker, then the Clipboard section,
    /// which stays in view whatever app is chosen.
    static let clipboardEntries: [SearchEntry] = [
        .general(
            "clipboardApp",
            AppRole.clipboard.title,
            description: AppRole.clipboard.detail,
            section: String(localized: "Preferred Apps", bundle: .floe),
            keywords: String(
                localized: "clipboard, clipboard manager, clipboard history, raycast, link, url, preferred app, default app",
                bundle: .floe,
                comment: "Words that find the Clipboard app setting in the settings search, separated by commas."
            ).searchTerms
        ),
        .general(
            "clipboardHistory",
            String(localized: "Save clipboard history", bundle: .floe),
            description: String(localized: "Keeps text, links, images and files you copy.", bundle: .floe),
            section: String(localized: "Clipboard", bundle: .floe),
            keywords: String(
                localized: "clipboard, history, copy, paste, copies, pin, clear",
                bundle: .floe,
                comment: "Words that find the Save clipboard history setting in the settings search, separated by commas."
            ).searchTerms
        ),
        .general(
            "clearClipboardHistory",
            String(localized: "Clear clipboard history", bundle: .floe),
            description: String(localized: "Removes every copy except pinned ones.", bundle: .floe),
            section: String(localized: "Clipboard", bundle: .floe),
            keywords: String(
                localized: "clipboard, history, clear, delete, remove, copies",
                bundle: .floe,
                comment: "Words that find the Clear clipboard history setting in the settings search, separated by commas."
            ).searchTerms
        ),
    ]
}
