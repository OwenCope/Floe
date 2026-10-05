//
//  Notes.swift
//  Project: Floe
//
//  Copyright (Floe) © 2026 René Jiménez
//  Licensed under the GNU AGPLv3

import AppKit

/// The app the notes role stands for. Floe keeps no notes of its own: it hands the text to the one already in use.
enum NotesApp: String, Codable, CaseIterable, Identifiable {
    case appleNotes
    case antinote
    /// Any app with a URL scheme, through a template the user writes.
    case custom

    var id: String {
        rawValue
    }

    var title: String {
        switch self {
        case .appleNotes: "Apple Notes"
        case .antinote: "Antinote"
        case .custom: String(localized: "Another App", bundle: .floe)
        }
    }

    /// What the app can be asked to do. Appending needs a notion of the current note, which only Antinote has.
    var actions: [NoteAction] {
        switch self {
        case .antinote: [.new, .append]
        case .appleNotes, .custom: [.new]
        }
    }
}

enum NoteAction: String, CaseIterable {
    case new
    case append

    /// The word that starts a note from the search: `note buy milk`.
    var keyword: String {
        switch self {
        case .new: "note"
        case .append: "append"
        }
    }

    var symbol: String {
        switch self {
        case .new: "square.and.pencil"
        case .append: "text.append"
        }
    }

    func title(text: String) -> String {
        switch (self, text.isEmpty) {
        case (.new, true): String(localized: "New Note", bundle: .floe)
        case (.new, false): String(localized: "New Note “\(text)”", bundle: .floe, comment: "The placeholder is the text of the note.")
        case (.append, true): String(localized: "Append to Current Note", bundle: .floe)
        case (.append, false): String(localized: "Append “\(text)” to Current Note", bundle: .floe, comment: "The placeholder is the text added to the note.")
        }
    }
}

enum Notes {
    /// The placeholder a custom template puts where the note's text goes.
    static let placeholder = "{text}"

    /// A query that starts with an action's keyword and a space is that action with the rest as its text.
    static func request(in query: String, app: NotesApp) -> (action: NoteAction, text: String)? {
        for action in app.actions {
            let prefix = action.keyword + " "
            guard query.lowercased().hasPrefix(prefix) else { continue }
            let text = query.dropFirst(prefix.count).trimmingCharacters(in: .whitespacesAndNewlines)
            return text.isEmpty ? nil : (action, text)
        }
        return nil
    }

    /// Text as one value of a URL's query: everything but unreserved characters is escaped, so an
    /// ampersand or an equals sign in a note does not end it.
    static func encoded(_ text: String) -> String {
        let unreserved = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-._~"))
        return text.addingPercentEncoding(withAllowedCharacters: unreserved) ?? text
    }

    /// The link that hands a note to an app with a URL scheme; nil for Apple Notes, which is scripted,
    /// and for a template that is not a URL.
    static func url(_ action: NoteAction, text: String, app: NotesApp, template: String) -> URL? {
        switch app {
        case .appleNotes:
            return nil
        case .antinote:
            // Without text there is nothing to make or add: the app is opened instead.
            guard !text.isEmpty else { return URL(string: "antinote://") }
            let path = action == .new ? "createNote" : "appendToCurrent"
            return URL(string: "antinote://x-callback-url/\(path)?content=\(encoded(text))")
        case .custom:
            return URL(string: template.replacingOccurrences(of: placeholder, with: encoded(text)))
        }
    }

    /// The script that makes a note in Apple Notes. A note's body is HTML and its first line is its
    /// title. Without text, Notes comes forward on a new empty note.
    static func appleNotesScript(text: String) -> String {
        guard !text.isEmpty else {
            return """
            tell application "Notes"
                activate
                show (make new note)
            end tell
            """
        }
        let html = text
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .split(separator: "\n", omittingEmptySubsequences: false)
            .map { "<div>\($0.isEmpty ? "<br>" : String($0))</div>" }
            .joined()
        return "tell application \"Notes\" to make new note with properties {body:\(AppleScript.literal(html))}"
    }

    /// Hands the note over and answers with the line for the HUD, or nil when the app came forward
    /// and shows the result itself.
    static func perform(_ action: NoteAction, text: String, app: NotesApp, template: String, completion: @escaping (String?) -> Void) {
        guard app == .appleNotes else {
            guard let url = url(action, text: text, app: app, template: template), url.scheme != nil else {
                completion(String(localized: "Set a URL for your notes app in Settings", bundle: .floe))
                return
            }
            guard NSWorkspace.shared.urlForApplication(toOpen: url) != nil else {
                completion(app == .antinote ? String(localized: "Antinote isn't installed", bundle: .floe, comment: "Antinote is the name of an app.") : String(localized: "No app opens that URL", bundle: .floe))
                return
            }
            NSWorkspace.shared.openWithoutWaiting(url)
            completion(nil)
            return
        }
        let source = appleNotesScript(text: text)
        AppleScript.execute(source, qos: .userInitiated) { execution in
            switch execution.errorNumber {
            case nil: completion(text.isEmpty ? nil : String(localized: "Saved to Notes", bundle: .floe, comment: "Notes is Apple's notes app."))
            case AppleScript.refusedErrorNumber: SystemCommand.askForAutomation(toControl: "Notes")
            default: completion(String(localized: "Couldn't save the note in Notes", bundle: .floe, comment: "Notes is Apple's notes app."))
            }
        }
    }
}
