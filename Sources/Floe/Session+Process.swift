//
//  Session+Process.swift
//  Project: Floe
//
//  Copyright (Floe) © 2026 René Jiménez
//  Licensed under the GNU AGPLv3

import Foundation
import Subprocess
import System

/// The half of a session that needs a real Bun process: spawning it, wiring its pipes, and stopping it.
/// What the session does with the messages lives in Session.swift.
extension ExtensionSession {
    func start() {
        guard let bun = Paths.bun else {
            toast = ToastState(id: 0, style: "failure", title: "Bun isn't installed", message: "brew install bun")
            return
        }
        let argumentsJSON = (try? JSONSerialization.data(withJSONObject: arguments)).flatMap { String(data: $0, encoding: .utf8) } ?? "{}"
        // The login shell's environment, not the app's own: launched from Finder, the app has a PATH
        // without brew, git or node, and extensions run those.
        let variables = Self.hostVariables(
            LoginEnvironment.current,
            preferences: try? JSONSerialization.data(withJSONObject: PreferenceStore.resolvedValues(for: command)),
            hasAI: AIAnswer.isAvailable
        )
        let environment = Environment.custom(Dictionary(uniqueKeysWithValues: variables.map { (Environment.Key(stringLiteral: $0.key), $0.value) }))
        // Cancelling the task sends SIGTERM, then SIGKILL: a host stuck in synchronous code ignores SIGTERM.
        var options = PlatformOptions()
        options.teardownSequence = [.gracefulShutDown(allowedDurationToNextStep: .seconds(1))]
        // Messages sent before the host is up wait here until its stdin opens.
        let (outgoing, messages) = AsyncStream<[UInt8]>.makeStream()
        transport = { message in
            guard let data = try? JSONSerialization.data(withJSONObject: message) else { return }
            messages.yield(Array(data) + [0x0A])
        }
        // --smol trades some GC headroom for a smaller footprint: extension trees stay mounted for
        // Back and resume, so the allocator's retention is the host's biggest memory cost.
        let hostArguments = Arguments(["--smol", Paths.host.path, command.extensionDir.path, command.name, argumentsJSON])
        // One decoder per host: it owns the partial bytes between chunks and keeps decoding off the main actor.
        let decoder = HostMessageDecoder()
        hostTask = Task { [weak self] in
            do {
                let result = try await Subprocess.run(
                    .path(FilePath(bun)),
                    arguments: hostArguments,
                    environment: environment,
                    platformOptions: options,
                    input: .inputWriter,
                    output: .sequence,
                    error: .sequence
                ) { execution in
                    await MainActor.run { [weak self] in self?.hostStarted(execution.processIdentifier.value) }
                    try await Self.relay(
                        execution,
                        outgoing: outgoing,
                        output: { [weak self] data in
                            await decoder.deliver(data) { message in
                                await MainActor.run { [weak self] in self?.apply(message) }
                            }
                        },
                        errors: { [weak self] data in await MainActor.run { [weak self] in self?.appendLog(data) } }
                    )
                    // The host closed its output, so nothing more will be read from its input.
                    messages.finish()
                }
                await MainActor.run { [weak self] in self?.hostEnded(result.terminationStatus) }
            } catch {
                messages.finish()
                await MainActor.run { [weak self] in self?.hostFailed(error) }
            }
        }
    }

    /// Feeds the host's stdin and hands on what it prints, until it closes its output.
    /// It holds no session, so a session nobody keeps can go away while its host still runs.
    private static func relay(
        _ execution: Execution<CustomWriteInput, SequenceOutput, SequenceOutput>,
        outgoing: AsyncStream<[UInt8]>,
        output: @escaping @Sendable (Data) async -> Void,
        errors: @escaping @Sendable (Data) async -> Void
    ) async throws {
        let writing = Task {
            for await bytes in outgoing {
                _ = try? await execution.standardInputWriter.write(bytes)
            }
        }
        defer { writing.cancel() }
        try await withThrowingTaskGroup(of: Void.self) { group in
            group.addTask {
                for try await buffer in execution.standardError {
                    let data = buffer.withUnsafeBytes { Data($0) }
                    FileHandle.standardError.write(data)
                    await errors(data)
                }
            }
            for try await buffer in execution.standardOutput {
                await output(buffer.withUnsafeBytes { Data($0) })
            }
            try await group.waitForAll()
        }
    }

    private func hostStarted(_ identifier: pid_t) {
        processID = identifier
        watchdog = Timer.scheduledTimer(withTimeInterval: 3, repeats: true) { [weak self] _ in
            guard let self, processID != nil else { return }
            heartbeat()
        }
    }

    private func hostEnded(_ status: TerminationStatus) {
        processID = nil
        switch status {
        case let .exited(code): processEnded(status: code, wasSignalled: false)
        case let .signaled(signal): processEnded(status: signal, wasSignalled: true)
        }
    }

    /// The host couldn't be launched, or reading from it broke off; stopping it on purpose also ends up here.
    private func hostFailed(_ error: Error) {
        let hadStarted = processID != nil
        processID = nil
        watchdog?.invalidate()
        cancelRequests()
        guard !isStopping, failure == nil else { return }
        let message = hadStarted ? "The extension stopped unexpectedly." : "The extension couldn't start."
        failure = SessionFailure(kind: hadStarted ? .crashed : .error, message: message, details: error.localizedDescription)
    }

    /// Stops the process, optionally after a grace period so trailing messages still arrive.
    func stop(after delay: TimeInterval = 0) {
        isStopping = true
        watchdog?.invalidate()
        cancelRequests()
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [self] in
            hostTask?.cancel()
        }
    }

    /// Kills the process now, for app quit and the self-test, where nothing waits for a grace period.
    func forceStop() {
        isStopping = true
        watchdog?.invalidate()
        cancelRequests()
        if let processID {
            kill(processID, SIGKILL)
        }
    }
}
