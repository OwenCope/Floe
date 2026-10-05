//
//  AppleScript.swift
//  Project: Floe
//
//  Copyright (Floe) © 2026 René Jiménez
//  Licensed under the GNU AGPLv3

import Foundation

/// How a script ended.
nonisolated enum AppleScriptOutcome: Equatable, Sendable {
    case text(String)
    /// macOS did not let Floe control the app (error -1743).
    case refused
    case failed
}

/// Runs a script and waits for it. Tests pass their own, so no test ever talks to a browser.
typealias AppleScriptRunner = @Sendable (String) -> AppleScriptOutcome

/// The one place a script is handed to macOS. Each caller reads the answer its own way and words its own messages.
nonisolated enum AppleScript {
    /// What macOS reports when the user has not allowed Floe to control the app.
    static let refusedErrorNumber = -1743

    /// Everything a run reported, as plain values that may cross threads.
    struct Execution: Equatable, Sendable {
        /// False when the source could not be made into a script at all.
        var didRun = true
        /// What the script returned, when that reads as text.
        var text: String?
        /// Whether macOS reported an error, with or without a number.
        var hasError = false
        var errorNumber: Int?
        var errorMessage: String?

        var isRefused: Bool {
            errorNumber == AppleScript.refusedErrorNumber
        }
    }

    /// Blocks until the script ends: call it off the main thread.
    static func execute(_ source: String) -> Execution {
        var error: NSDictionary?
        let result = NSAppleScript(source: source)?.executeAndReturnError(&error)
        return Execution(
            didRun: result != nil,
            text: result?.stringValue,
            hasError: error != nil,
            errorNumber: error?[NSAppleScript.errorNumber] as? Int,
            errorMessage: error?[NSAppleScript.errorMessage] as? String
        )
    }

    /// Runs the script on a background queue and reports back on the main thread.
    static func execute(_ source: String, qos: DispatchQoS.QoSClass, completion: @escaping @MainActor (Execution) -> Void) {
        DispatchQueue.global(qos: qos).async {
            let execution = execute(source)
            DispatchQueue.main.async { completion(execution) }
        }
    }

    /// Blocks until the script ends: call it off the main thread.
    static let run: AppleScriptRunner = { source in
        let execution = execute(source)
        if let number = execution.errorNumber {
            return number == refusedErrorNumber ? .refused : .failed
        }
        guard execution.didRun else { return .failed }
        return .text(execution.text ?? "")
    }

    static func literal(_ text: String) -> String {
        "\"" + text.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"") + "\""
    }
}
