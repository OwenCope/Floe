//
//  NotesTests.swift
//  Project: Floe
//
//  Copyright (Floe) © 2026 René Jiménez
//  Licensed under the GNU AGPLv3

import AppKit
@testable import Floe
import Foundation
import Testing

@MainActor
struct NotesTests {
    private func makeModel(app: NotesApp) -> LauncherModel {
        let settings = AppSettings(defaults: UserDefaults(suiteName: "floe-notes-tests-\(UUID().uuidString)")!)
        settings.notesApp = app
        return LauncherModel(settings: settings, snapshot: CatalogSnapshot(apps: [], commands: []))
    }

    @Test func aQueryThatStartsWithNoteIsANewNoteWithTheRestAsItsText() throws {
        let request = try #require(Notes.request(in: "Note buy milk & eggs ", app: .appleNotes))
        #expect(request.action == .new)
        #expect(request.text == "buy milk & eggs")
        #expect(Notes.request(in: "note", app: .appleNotes) == nil, "the keyword alone is a search for it")
        #expect(Notes.request(in: "note   ", app: .appleNotes) == nil)
        #expect(Notes.request(in: "notes app", app: .appleNotes) == nil, "a longer word is not the keyword")
    }

    @Test func onlyAntinoteCanAppend() throws {
        #expect(Notes.request(in: "append call back", app: .appleNotes) == nil)
        #expect(Notes.request(in: "append call back", app: .custom) == nil)
        let request = try #require(Notes.request(in: "append call back", app: .antinote))
        #expect(request.action == .append)
        #expect(NotesApp.allCases.filter { $0.actions.contains(.append) } == [.antinote])
    }

    @Test func antinoteGetsItsDocumentedLinksWithTheTextEscaped() {
        let new = Notes.url(.new, text: "a&b=c d?", app: .antinote, template: "")
        #expect(new?.absoluteString == "antinote://x-callback-url/createNote?content=a%26b%3Dc%20d%3F")
        let append = Notes.url(.append, text: "línea\n2", app: .antinote, template: "")
        #expect(append?.absoluteString == "antinote://x-callback-url/appendToCurrent?content=l%C3%ADnea%0A2")
        #expect(Notes.url(.new, text: "", app: .antinote, template: "")?.absoluteString == "antinote://", "no text opens the app")
    }

    @Test func aTemplatePutsTheEscapedTextWhereThePlaceholderIs() {
        let url = Notes.url(.new, text: "buy milk", app: .custom, template: "bear://x-callback-url/create?text={text}")
        #expect(url?.absoluteString == "bear://x-callback-url/create?text=buy%20milk")
        #expect(Notes.url(.new, text: "x", app: .appleNotes, template: "ignored://{text}") == nil, "Apple Notes is scripted, not linked")
    }

    @Test func theAppleNotesScriptEscapesHTMLAndQuotesAndKeepsLines() {
        let script = Notes.appleNotesScript(text: "Say \"hi\" <now>\n\nA & B \\ C")
        #expect(script == #"tell application "Notes" to make new note with properties {body:"<div>Say \"hi\" &lt;now&gt;</div><div><br></div><div>A &amp; B \\ C</div>"}"#)
        #expect(NSAppleScript(source: script) != nil)
        #expect(Notes.appleNotesScript(text: "").contains("show (make new note)"), "without text Notes opens on a new note")
    }

    @Test(arguments: NoteAction.allCases)
    func everyActionHasASymbolThatExistsAndATitleForBothStates(action: NoteAction) {
        #expect(NSImage(systemSymbolName: action.symbol, accessibilityDescription: nil) != nil)
        #expect(action.title(text: "") != action.title(text: "x"))
        #expect(action.title(text: "buy milk").contains("“buy milk”"))
    }

    @Test func theSearchLeadsWithTheNoteItWouldMakeAndListsItOnce() throws {
        let model = makeModel(app: .antinote)
        model.query = "note buy milk"
        let first = try #require(model.results.first?.item)
        #expect(first.title == "New Note “buy milk”")
        #expect(first.kind == "Notes")
        #expect(model.results.filter { $0.id == "note:new" }.count == 1)

        model.query = "append call back"
        #expect(model.results.first?.item.title == "Append “call back” to Current Note")
    }

    @Test func theBareActionsAreFoundByNameAndFollowTheChosenApp() {
        let antinote = makeModel(app: .antinote)
        antinote.query = "new note"
        #expect(antinote.results.first?.item.id == "note:new")
        antinote.query = "append to"
        #expect(antinote.results.contains { $0.id == "note:append" })

        let apple = makeModel(app: .appleNotes)
        apple.query = "append to"
        #expect(!apple.results.contains { $0.id == "note:append" }, "Apple Notes has no current note to add to")
    }

    @Test func theNotesAppAndItsLinkComeBackAfterASave() throws {
        let defaults = try #require(UserDefaults(suiteName: "floe-notes-tests-\(UUID().uuidString)"))
        let settings = AppSettings(defaults: defaults)
        #expect(settings.notesApp == .appleNotes, "the app every Mac has is the default")
        settings.notesApp = .custom
        settings.notesURLTemplate = "bear://x-callback-url/create?text={text}"
        settings.save()
        let reloaded = AppSettings(defaults: defaults)
        #expect(reloaded.notesApp == .custom)
        #expect(reloaded.notesURLTemplate == "bear://x-callback-url/create?text={text}")
    }
}
