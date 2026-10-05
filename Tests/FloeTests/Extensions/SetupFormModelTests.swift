//
//  SetupFormModelTests.swift
//  Project: Floe
//
//  Copyright (Floe) © 2026 René Jiménez
//  Licensed under the GNU AGPLv3

import AppKit
@testable import Floe
import Testing

/// Argument forms only: a preferences form reads what is stored for the extension.
@MainActor
struct SetupFormModelTests {
    private func command(_ arguments: [FieldSpec]) -> ExtensionCommand {
        ExtensionCommand(
            extensionDir: URL(fileURLWithPath: "/tmp/floe-setup-form-tests"), extensionName: "floe-setup-form-tests",
            extensionTitle: "Tests", source: .local, name: "greet", title: "Greet",
            mode: "view", interval: nil, icon: nil, arguments: arguments, extensionPreferences: [], commandPreferences: []
        )
    }

    private func request(_ fields: [FieldSpec]) -> SetupRequest {
        SetupRequest(command: command(fields), kind: .arguments, fields: fields)
    }

    private func key(_ code: UInt16) throws -> NSEvent {
        try #require(NSEvent.keyEvent(
            with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0, windowNumber: 0, context: nil,
            characters: "", charactersIgnoringModifiers: "", isARepeat: false, keyCode: code
        ))
    }

    @Test func aFormStartsOnItsFieldsDefaultsWithNoError() {
        let form = SetupFormModel()
        let fields = [Fixture.field("name", required: true), Fixture.field("greeting", defaultValue: "Hello"), Fixture.field("loud", type: "checkbox")]
        form.values = ["left": "over"]
        form.begin(request(fields))
        #expect(form.values == ["name": "", "greeting": "Hello", "loud": ""], "a checkbox with no default starts unset")
        #expect(form.error == nil)
    }

    @Test func aMissingRequiredFieldIsNamedAndFillingItInGivesTheTypedValues() throws {
        let form = SetupFormModel()
        let request = request([Fixture.field("name", required: true), Fixture.field("loud", type: "checkbox")])
        form.begin(request)
        #expect(form.validated(for: request) == nil)
        #expect(form.error == "Fill in name.")

        form.values["name"] = "Ada"
        form.values["loud"] = "true"
        let values = try #require(form.validated(for: request))
        #expect(values["name"] as? String == "Ada")
        #expect(values["loud"] as? Bool == true)

        form.begin(request)
        #expect(form.error == nil, "a form that is opened again starts clean")
    }

    @Test func theLauncherShowsTheFormAndTypingInItDoesNotRepublishTheLauncher() throws {
        let settings = try AppSettings(defaults: #require(UserDefaults(suiteName: "floe-setup-form-tests-\(UUID().uuidString)")))
        let greet = command([Fixture.field("name", required: true)])
        let launcher = LauncherModel(settings: settings, snapshot: CatalogSnapshot(apps: [], commands: [greet]), scopes: [], sources: [])
        launcher.run(greet)
        #expect(launcher.setup?.kind == .arguments)
        #expect(launcher.setupForm.values == ["name": ""])
        #expect(launcher.panelState.isRootSearch == false)

        var changes = 0
        let subscription = launcher.objectWillChange.sink { changes += 1 }
        defer { subscription.cancel() }
        launcher.setupForm.values["name"] = ""
        #expect(try launcher.handleKey(key(36)), "Return with the field still empty")
        #expect(launcher.setupForm.error == "Fill in name.")
        #expect(launcher.setup != nil, "the form stays")
        #expect(changes == 0)

        #expect(try launcher.handleKey(key(53)))
        #expect(launcher.setup == nil)
        #expect(launcher.session == nil, "the command did not run")
    }
}
