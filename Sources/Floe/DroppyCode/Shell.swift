//
//  Shell.swift
//  Project: Droppy Code
//
//  Copyright (Droppy Code) © 2026 Jordy Spruit
//  Droppy Code by Jordy Spruit (Droppy), https://getdroppycode.app
//  Licensed under the GNU AGPLv3
//
//  Floe changes © 2026 René Jiménez, under the same license.
//
//  Ported to Floe from Droppy Code's Core/Support/Shell.swift, and modified: the login shell
//  environment moved to LoginEnvironment.swift, the check for shell commands that write files
//  is left out, because Floe runs no agent's commands, and `run` can hand standard output on
//  as it is read, for a tool that streams its answer.

import Foundation
import Synchronization

nonisolated struct ShellResult: Sendable {
    var status: Int32
    var stdout: Data
    var stderr: Data

    var succeeded: Bool {
        status == 0
    }

    var output: String {
        // A tool's output is not always valid UTF-8; what can't be read is replaced, not dropped.
        // swiftlint:disable:next optional_data_string_conversion
        String(decoding: stdout, as: UTF8.self)
    }

    var errorOutput: String {
        // A tool's output is not always valid UTF-8; what can't be read is replaced, not dropped.
        // swiftlint:disable:next optional_data_string_conversion
        String(decoding: stderr, as: UTF8.self)
    }

    var trimmedOutput: String {
        output.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// The most useful text to show when a command fails.
    var failureMessage: String {
        let error = errorOutput.trimmingCharacters(in: .whitespacesAndNewlines)
        let message = error.isEmpty ? trimmedOutput : error
        return message.isEmpty ? "The command failed with exit code \(status)." : message
    }
}

nonisolated struct ShellError: LocalizedError, Sendable {
    var message: String
    var errorDescription: String? {
        message
    }

    init(_ message: String) {
        self.message = message
    }
}

nonisolated enum Shell {
    /// Runs a process to completion off the main actor and collects its output. With an
    /// `outputLimit`, only that many bytes of each stream's tail are kept. `onOutput` is given
    /// standard output as it is read, in order.
    @concurrent
    // swiftlint:disable:next function_body_length - kept in one piece, as in Droppy Code
    static func run(
        _ executable: URL,
        _ arguments: [String],
        in directory: URL? = nil,
        environment: [String: String]? = nil,
        input: Data? = nil,
        timeout: TimeInterval = 120,
        outputLimit: Int? = nil,
        onOutput: (@Sendable (Data) -> Void)? = nil
    ) async throws -> ShellResult {
        let process = Process()
        process.executableURL = executable
        process.arguments = arguments
        if let directory {
            process.currentDirectoryURL = directory
        }
        process.environment = environment ?? LoginEnvironment.current

        let stdout = Pipe()
        let stderr = Pipe()
        let stdin: Pipe? = input == nil ? nil : Pipe()
        process.standardOutput = stdout
        process.standardError = stderr
        process.standardInput = stdin ?? FileHandle.nullDevice

        let collector = OutputCollector(limit: outputLimit, onOutput: onOutput)
        stdout.fileHandleForReading.readabilityHandler = collector.reader(for: .stdout)
        stderr.fileHandleForReading.readabilityHandler = collector.reader(for: .stderr)

        let cancelled = Mutex(false)
        let deadline = Mutex<Task<Void, Never>?>(nil)
        defer {
            deadline.withLock { $0?.cancel() }
            stdout.fileHandleForReading.readabilityHandler = nil
            stderr.fileHandleForReading.readabilityHandler = nil
        }
        let status: Int32 = try await withTaskCancellationHandler {
            try Task.checkCancellation()
            return try await withCheckedThrowingContinuation { continuation in
                let once = OnceContinuation(continuation)
                process.terminationHandler = { process in
                    once.resume(returning: process.terminationStatus)
                }
                do {
                    try cancelled.withLock { isCancelled in
                        if isCancelled {
                            throw CancellationError()
                        }
                        try process.run()
                    }
                    let timer = Task {
                        do {
                            try await Task.sleep(for: .seconds(timeout))
                        } catch {
                            return
                        }
                        terminate(process)
                    }
                    deadline.withLock { $0 = timer }
                } catch {
                    once.resume(throwing: error)
                    return
                }
                if let input, let stdin {
                    DispatchQueue.global(qos: .userInitiated).async {
                        try? stdin.fileHandleForWriting.write(contentsOf: input)
                        try? stdin.fileHandleForWriting.close()
                    }
                }
            }
        } onCancel: {
            cancelled.withLock { isCancelled in
                isCancelled = true
                terminate(process)
            }
        }
        deadline.withLock { $0?.cancel() }
        try Task.checkCancellation()
        let output = await collector.finished(within: 3)
        try Task.checkCancellation()
        return ShellResult(status: status, stdout: output.stdout, stderr: output.stderr)
    }

    private static func terminate(_ process: Process) {
        guard process.isRunning else { return }
        process.terminate()
        DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + 1) {
            guard process.isRunning else { return }
            let pid = process.processIdentifier
            kill(getpgid(pid) == pid ? -pid : pid, SIGKILL)
        }
    }

    /// Runs a named tool found on the login PATH.
    @concurrent
    static func run(
        tool name: String,
        _ arguments: [String],
        in directory: URL? = nil,
        environment: [String: String]? = nil,
        input: Data? = nil,
        timeout: TimeInterval = 120
    ) async throws -> ShellResult {
        guard let executable = LoginEnvironment.which(name) else {
            throw ShellError("\(name) was not found on your PATH.")
        }
        return try await run(executable, arguments, in: directory, environment: environment, input: input, timeout: timeout)
    }
}

/// Resumes a continuation exactly once, however many callbacks race to finish it.
///
/// It is taken out under the lock and resumed outside it, since a resume runs whatever
/// the awaiting task does next and `withLock` is non-reentrant.
final nonisolated class OnceContinuation<Value: Sendable>: Sendable {
    private let continuation: Mutex<CheckedContinuation<Value, Error>?>

    init(_ continuation: CheckedContinuation<Value, Error>) {
        self.continuation = Mutex(continuation)
    }

    func resume(returning value: Value) {
        take()?.resume(returning: value)
    }

    func resume(throwing error: Error) {
        take()?.resume(throwing: error)
    }

    private func take() -> CheckedContinuation<Value, Error>? {
        continuation.withLock { continuation in
            defer { continuation = nil }
            return continuation
        }
    }
}

private final nonisolated class OutputCollector: Sendable {
    enum Stream: Hashable {
        case stdout
        case stderr
    }

    private struct State {
        var stdout = Data()
        var stderr = Data()
        var closed: Set<Stream> = []
        var waiters: [OnceContinuation<Void>] = []
    }

    private let state = Mutex(State())
    private let limit: Int?
    private let onOutput: (@Sendable (Data) -> Void)?

    init(limit: Int?, onOutput: (@Sendable (Data) -> Void)? = nil) {
        self.limit = limit
        self.onOutput = onOutput
    }

    func reader(for stream: Stream) -> @Sendable (FileHandle) -> Void {
        { [self] handle in
            let data = handle.availableData
            if data.isEmpty {
                handle.readabilityHandler = nil
                close(stream)
            } else {
                state.withLock { state in
                    switch stream {
                    case .stdout: append(data, to: &state.stdout)
                    case .stderr: append(data, to: &state.stderr)
                    }
                }
                if stream == .stdout {
                    onOutput?(data)
                }
            }
        }
    }

    /// Keeps the tail within the limit, trimming by whole chunks once the buffer holds twice
    /// the limit, so a stream that never ends costs O(limit) memory and amortized O(1) per byte.
    private func append(_ data: Data, to buffer: inout Data) {
        buffer.append(data)
        guard let limit, buffer.count > limit * 2 else { return }
        buffer = Data(buffer.suffix(limit))
    }

    func finished(within timeout: TimeInterval) async -> (stdout: Data, stderr: Data) {
        if let output = state.withLock({ $0.closed.count == 2 ? ($0.stdout, $0.stderr) : nil }) {
            return output
        }
        let deadline = Task {
            do {
                try await Task.sleep(for: .seconds(timeout))
            } catch {
                return
            }
            close(.stdout)
            close(.stderr)
        }
        defer { deadline.cancel() }
        await withTaskCancellationHandler {
            try? await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                let once = OnceContinuation(continuation)
                let isDone = state.withLock { state in
                    if state.closed.count == 2 {
                        return true
                    }
                    state.waiters.append(once)
                    return false
                }
                if isDone {
                    once.resume(returning: ())
                }
            }
        } onCancel: {
            close(.stdout)
            close(.stderr)
        }
        return state.withLock { ($0.stdout, $0.stderr) }
    }

    private func close(_ stream: Stream) {
        let ready: [OnceContinuation<Void>] = state.withLock { state in
            guard state.closed.insert(stream).inserted, state.closed.count == 2 else { return [] }
            let ready = state.waiters
            state.waiters.removeAll()
            return ready
        }
        for waiter in ready {
            waiter.resume(returning: ())
        }
    }
}
