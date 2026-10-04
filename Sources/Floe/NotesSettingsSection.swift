//
//  NotesSettingsSection.swift
//  Project: Floe
//
//  Copyright (Floe) © 2026 René Jiménez
//  Licensed under the GNU AGPLv3

import SwiftUI
import ThawUI

/// Which app a note typed into the search goes to, and the link for an app Floe has no name for.
struct NotesSettingsSection: View {
    @ObservedObject var settings: AppSettings

    var body: some View {
        ThawSection("Notes") {
            Picker(selection: $settings.notesApp) {
                ForEach(NotesApp.allCases) { app in
                    Text(app.title).tag(app)
                }
            } label: {
                Text("Notes app")
                Text("Type “note” and then your text in the search to send it there.")
            }
            if settings.notesApp == .custom {
                TextField(text: $settings.notesURLTemplate, prompt: Text(verbatim: "bear://x-callback-url/create?text={text}")) {
                    Text("URL")
                    Text("The link that makes a note, with {text} where the text goes.")
                }
            }
        }
    }
}
