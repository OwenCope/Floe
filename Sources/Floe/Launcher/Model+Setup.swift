//
//  Model+Setup.swift
//  Project: Floe
//
//  Copyright (Floe) © 2026 René Jiménez
//  Licensed under the GNU AGPLv3

import Foundation

/// Showing a command's setup form and running the command once it is filled in; the typed values are `SetupFormModel`'s.
extension LauncherModel {
    func beginSetup(_ request: SetupRequest) {
        setupForm.begin(request)
        setup = request
        showPanel()
        focusToken += 1
    }

    func submitSetup() {
        guard let request = setup, let values = setupForm.validated(for: request) else { return }
        setup = nil
        switch request.kind {
        case .preferences:
            let command = request.command
            PreferenceStore.save(values, fields: command.extensionPreferences, extensionName: command.extensionName, command: nil)
            PreferenceStore.save(values, fields: command.commandPreferences, extensionName: command.extensionName, command: command)
            run(command)
        case .arguments:
            run(request.command, arguments: values)
        }
    }

    func cancelSetup() {
        setup = nil
        focusToken += 1
    }
}
