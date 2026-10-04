//
//  DiagnosticsSettingsSection.swift
//  Project: Floe
//
//  Copyright (Floe) © 2026 René Jiménez
//  Licensed under the GNU AGPLv3

import SwiftUI
import ThawUI

/// Settings → General: the switch for the log file, and the way to it.
struct DiagnosticsSettingsSection: View {
    @ObservedObject var settings: AppSettings
    @State private var logFileName: String?

    var body: some View {
        ThawSection("Diagnostics") {
            Toggle(isOn: $settings.diagnosticLogging) {
                Text("Detailed logging")
                Text("Writes a log to ~/Library/Logs/Floe for troubleshooting: launch and scan times, slow searches, and commands and AI requests that fail. Never what you type or ask. Turn it off when you are done.")
            }
            LabeledContent {
                Button("Show Log Files in Finder") { NSWorkspace.shared.open(DiagnosticLogger.shared.logDirectory) }
            } label: {
                Text("Log files")
                Text(logFileName ?? "None yet")
            }
        }
        .task(id: settings.diagnosticLogging) {
            // The launcher opens the file once it hears of the switch, a moment after it flips here.
            try? await Task.sleep(for: .milliseconds(600))
            logFileName = (DiagnosticLogger.shared.currentLogFile ?? DiagnosticLogger.shared.latestLogFile)?.lastPathComponent
        }
    }
}
