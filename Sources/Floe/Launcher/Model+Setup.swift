//
//  Model+Setup.swift
//  Project: Floe
//
//  Copyright (Floe) © 2026 René Jiménez
//  Licensed under the GNU AGPLv3

import Foundation

/// The fields a command asks for before it runs: its required preferences, or its arguments.
extension LauncherModel {
    func beginSetup(_ request: SetupRequest) {
        var values: [String: String] = [:]
        for field in request.fields {
            let scope = request.command.commandPreferences.contains { $0.name == field.name } ? request.command : nil
            let stored = request.kind == .preferences
                ? PreferenceStore.value(field, extensionName: request.command.extensionName, command: scope)
                : nil
            values[field.name] = FieldValues.initialText(for: field, stored: stored)
        }
        setupValues = values
        setupError = nil
        setup = request
        showPanel()
        focusToken += 1
    }

    func submitSetup() {
        guard let request = setup else { return }
        let missing = FieldValues.missing(request.fields, texts: setupValues)
        guard missing.isEmpty else {
            setupError = "Fill in \(missing.map(\.title).joined(separator: ", "))."
            return
        }
        let values = FieldValues.typed(setupValues, fields: request.fields)
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
