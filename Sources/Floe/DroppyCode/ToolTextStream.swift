//
//  ToolTextStream.swift
//  Project: Droppy Code
//
//  Copyright (Droppy Code) © 2026 Jordy Spruit
//  Droppy Code by Jordy Spruit (Droppy), https://getdroppycode.app
//  Licensed under the GNU AGPLv3
//
//  Floe changes © 2026 René Jiménez, under the same license.
//
//  Ported to Floe from Droppy Code's Services/Providers/ClaudeSession.swift, and modified: this is
//  the line by line reading that ClaudeTextStream.swift kept from it, moved to a file of its own so
//  the opencode and pi tools are read the same way. What a line means is the caller's to say.

import Foundation

/// One prompt, streamed back from a command line tool that prints its answer as lines of JSON.
enum ToolTextStream {
    /// What one line of a tool's output says.
    enum Event: Equatable {
        case text(String)
        /// The whole answer, once the tool has it.
        case result(String)
        case failure(String)
        /// The tool did something Floe does not let it do, so the run is stopped at once.
        case stop(String)
    }

    /// One run of a tool: what to start, where, and how long it may take.
    struct Launch {
        var executable: URL
        var arguments: [String]
        var directory: URL
        var environment: [String: String]
        var timeout: TimeInterval
    }

    /// The whole lines in what has been read so far; a line still being written waits for its end.
    struct Lines {
        private var buffer = Data()

        mutating func append(_ data: Data) -> [String] {
            buffer.append(data)
            var lines: [String] = []
            while let newline = buffer.firstIndex(of: 0x0A) {
                // swiftlint:disable:next optional_data_string_conversion
                lines.append(String(decoding: buffer[buffer.startIndex ..< newline], as: UTF8.self))
                buffer = Data(buffer[buffer.index(after: newline)...])
            }
            return lines
        }

        /// What is left when the output ends without a final newline.
        mutating func rest() -> [String] {
            defer { buffer = Data() }
            // swiftlint:disable:next optional_data_string_conversion
            return buffer.isEmpty ? [] : [String(decoding: buffer, as: UTF8.self)]
        }
    }

    /// Collects what the lines say: the text so far, and how the run ended.
    struct Answer {
        private(set) var streamed = ""
        private(set) var result: String?
        private(set) var failure: String?

        /// Returns the text an event adds, for showing at once.
        mutating func take(_ event: Event?) -> String? {
            switch event {
            case let .text(text):
                streamed += text
                return text
            case let .result(text):
                // A tool that tries again after an error ends with the answer, not the error.
                result = text
                failure = nil
            case let .failure(message), let .stop(message):
                failure = message
            case nil:
                break
            }
            return nil
        }

        /// The result's text, or what was streamed when the tool ended without one.
        var text: String {
            (result.flatMap { $0.isEmpty ? nil : $0 } ?? streamed).trimmingCharacters(in: .whitespacesAndNewlines)
        }
    }

    /// What a tool said went wrong, from its standard error: the last line that is not part of a
    /// stack trace, since pi prints one under its message. Nil when it printed nothing.
    static func complaint(in errorOutput: String) -> String? {
        let lines = errorOutput.split(whereSeparator: \.isNewline).map { $0.trimmingCharacters(in: .whitespaces) }
        let line = lines.last { !$0.isEmpty && !$0.hasPrefix("at ") }
        return line.map { String($0.prefix(500)) }
    }

    /// Runs the tool and returns the whole answer, handing each piece of text to `onText` as it arrives.
    /// `read` says what a line means. Cancelling the task stops the tool, and so does a `stop` line.
    static func run(
        _ prompt: String,
        launch: Launch,
        read: (String) -> Event?,
        onText: @Sendable (String) async -> Void
    ) async throws -> String {
        let (output, continuation) = AsyncStream.makeStream(of: Data.self)
        async let finished: ShellResult = {
            defer { continuation.finish() }
            return try await Shell.run(
                launch.executable,
                launch.arguments,
                in: launch.directory,
                environment: launch.environment,
                input: Data(prompt.utf8),
                timeout: launch.timeout,
                onOutput: { continuation.yield($0) }
            )
        }()
        var lines = Lines()
        var answer = Answer()
        for await data in output {
            for line in lines.append(data) {
                let event = read(line)
                if case let .stop(message) = event {
                    // Leaving here cancels the run above, which ends the tool.
                    throw ShellError(message)
                }
                if let text = answer.take(event) {
                    await onText(text)
                }
            }
        }
        let result = try await finished
        for line in lines.rest() {
            _ = answer.take(read(line))
        }
        if let failure = answer.failure {
            throw ShellError(failure)
        }
        guard result.succeeded else {
            throw ShellError(complaint(in: result.errorOutput) ?? result.failureMessage)
        }
        guard !answer.text.isEmpty else {
            throw ShellError(complaint(in: result.errorOutput) ?? "The model gave no answer.")
        }
        return answer.text
    }
}
