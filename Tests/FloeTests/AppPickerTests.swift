//
//  AppPickerTests.swift
//  Project: Floe
//
//  Copyright (Floe) © 2026 René Jiménez
//  Licensed under the GNU AGPLv3

@testable import Floe
import Testing

struct AppPickerTests {
    private let apps = [
        AppPickerValue.App(name: "TextEdit", path: "/System/Applications/TextEdit.app", bundleId: "com.apple.TextEdit"),
        AppPickerValue.App(name: "Visual Studio Code", path: "/Applications/Visual Studio Code.app", bundleId: "com.microsoft.VSCode"),
    ]
    private let field = Fixture.field(["name": "editor", "type": "appPicker", "title": "Editor", "required": true])!

    @Test(arguments: ["com.apple.TextEdit", "textedit", "/System/Applications/TextEdit.app", "TextEdit.app"])
    func aDefaultNamesTheAppByBundleIdNameOrPath(value: String) {
        #expect(AppPickerValue.match(value, in: apps)?.bundleId == "com.apple.TextEdit")
    }

    @Test func theCommandReceivesTheAppObject() {
        let resolved = AppPickerValue.resolve(["editor": "/Applications/Visual Studio Code.app"], fields: [field]) { apps }
        #expect(resolved["editor"] as? [String: String] == [
            "name": "Visual Studio Code", "path": "/Applications/Visual Studio Code.app", "bundleId": "com.microsoft.VSCode",
        ])
    }

    @Test func anAppThatIsNotInstalledLeavesARequiredPickerMissing() {
        let resolved = AppPickerValue.resolve(["editor": "com.example.Gone"], fields: [field]) { apps }
        #expect(resolved["editor"] == nil)
        #expect(PreferenceResolver.missingRequired([field], values: resolved).map(\.name) == ["editor"])
    }
}
