//
//  SettingsProcess.swift
//  Project: Floe
//
//  Copyright (Floe) © 2026 René Jiménez
//  Licensed under the GNU AGPLv3

import AppKit

/// The launcher's handle on its settings process: this executable again, started with `--settings`.
/// One runs at a time, it ends by itself when its window closes, and it never outlives the launcher.
final class SettingsProcess {
    /// What opening Settings comes to.
    enum Step: Equatable {
        /// No settings process runs: start one with these arguments.
        case start(arguments: [String])
        /// One runs: ask it to come to the front, on this page if one is named.
        case bringForward(page: String)
    }

    /// `page` is a `SettingsPage.id`; without one a new process opens where the last one was left.
    static func step(isRunning: Bool, page: String?, lastPage: String?) -> Step {
        if isRunning {
            return .bringForward(page: page ?? "")
        }
        return .start(arguments: ["--settings"] + ((page ?? lastPage).map { ["--page", $0] } ?? []))
    }

    private var process: Process?
    /// The page the settings window last showed, reported by the settings process.
    var lastPage: String?
    /// Called on the main thread when the process has ended, however it ended.
    var onExit: () -> Void = { /* set by the link */ }
    /// Asks the running process to come forward. Set by the link, which owns the messages.
    var bringForward: (String) -> Void = { _ in }

    /// The running settings process, which is the only sender the launcher listens to.
    var pid: Int32? {
        guard let process, process.isRunning else { return nil }
        return process.processIdentifier
    }

    func show(page: String?) {
        switch Self.step(isRunning: pid != nil, page: page, lastPage: lastPage) {
        case let .start(arguments):
            start(arguments)
        case let .bringForward(page):
            bringForward(page)
            // The settings process activates itself too; this covers the case where the system holds it back.
            pid.flatMap(NSRunningApplication.init(processIdentifier:))?.activate()
        }
    }

    private func start(_ arguments: [String]) {
        guard let executable = Bundle.main.executableURL else { return }
        let process = Process()
        process.executableURL = executable
        process.arguments = arguments
        process.terminationHandler = { [weak self] ended in
            DispatchQueue.main.async {
                guard let self else { return }
                // A process that crashed is simply gone: the next opening starts a new one.
                if self.process === ended {
                    self.process = nil
                }
                self.onExit()
            }
        }
        do {
            try process.run()
            self.process = process
        } catch {
            NSLog("Floe could not start its settings process: \(error.localizedDescription)")
        }
    }

    /// Ends the settings process with the launcher. It also watches for the launcher's exit itself.
    func terminate() {
        guard let process, process.isRunning else { return }
        process.terminate()
    }
}

/// Whether the launcher's global hotkeys stand down for a recorder in the settings process.
struct RemoteRecording: Equatable {
    private(set) var isRecording = false

    mutating func received(_ isRecording: Bool) {
        self.isRecording = isRecording
    }

    /// A settings process that dies while recording never says it stopped.
    mutating func settingsProcessExited() {
        isRecording = false
    }
}
