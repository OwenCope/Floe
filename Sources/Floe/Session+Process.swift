//
//  Session+Process.swift
//  Project: Floe
//
//  Copyright (Floe) © 2026 René Jiménez
//  Licensed under the GNU GPLv3

import Foundation

/// The half of a session that needs a real Bun process: spawning it, wiring its pipes, and stopping it.
/// What the session does with the messages lives in Session.swift.
extension ExtensionSession {
    func start() {
        guard let bun = Paths.bun else {
            toast = ToastState(id: 0, style: "failure", title: "Bun isn't installed", message: "brew install bun")
            return
        }
        process.executableURL = URL(fileURLWithPath: bun)
        let argumentsJSON = (try? JSONSerialization.data(withJSONObject: arguments)).flatMap { String(data: $0, encoding: .utf8) } ?? "{}"
        process.arguments = [Paths.host.path, command.extensionDir.path, command.name, argumentsJSON]
        // Preferences go through the environment so the host has them before the command's first line runs.
        var environment = ProcessInfo.processInfo.environment
        if let data = try? JSONSerialization.data(withJSONObject: PreferenceStore.resolvedValues(for: command)) {
            environment["FLOE_PREFERENCES"] = String(data: data, encoding: .utf8)
        }
        process.environment = environment
        process.standardInput = input
        process.standardOutput = output
        process.standardError = errors
        output.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            guard !data.isEmpty else { return }
            DispatchQueue.main.async { self?.receive(data) }
        }
        errors.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            guard !data.isEmpty else { return }
            FileHandle.standardError.write(data)
            DispatchQueue.main.async { self?.appendLog(data) }
        }
        process.terminationHandler = { [weak self] process in
            let status = process.terminationStatus
            let reason = process.terminationReason
            DispatchQueue.main.async { self?.processEnded(status: status, wasSignalled: reason == .uncaughtSignal) }
        }
        transport = { [weak self] in self?.write($0) }
        do {
            try process.run()
            startWatchdog()
        } catch {
            failure = SessionFailure(kind: .error, message: "The extension couldn't start.", details: error.localizedDescription)
        }
    }

    private func startWatchdog() {
        watchdog = Timer.scheduledTimer(withTimeInterval: 3, repeats: true) { [weak self] _ in
            guard let self, process.isRunning else { return }
            heartbeat()
        }
    }

    /// Stops the process, optionally after a grace period so trailing messages still arrive.
    func stop(after delay: TimeInterval = 0) {
        isStopping = true
        watchdog?.invalidate()
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [self] in
            output.fileHandleForReading.readabilityHandler = nil
            errors.fileHandleForReading.readabilityHandler = nil
            if process.isRunning { process.terminate() }
            // A host stuck in synchronous code ignores SIGTERM.
            DispatchQueue.main.asyncAfter(deadline: .now() + 1) { [self] in
                if process.isRunning { kill(process.processIdentifier, SIGKILL) }
            }
        }
    }

    /// Kills the process now, for app quit and the self-test, where nothing waits for a grace period.
    func forceStop() {
        isStopping = true
        watchdog?.invalidate()
        if process.isRunning { kill(process.processIdentifier, SIGKILL) }
    }

    private func write(_ message: [String: Any]) {
        guard process.isRunning, var data = try? JSONSerialization.data(withJSONObject: message) else { return }
        data.append(0x0A)
        try? input.fileHandleForWriting.write(contentsOf: data)
    }
}
