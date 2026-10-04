//
//  ClaudeTextStream.swift
//  Project: Droppy Code
//
//  Copyright (Droppy Code) © 2026 Jordy Spruit
//  Droppy Code by Jordy Spruit (Droppy), https://getdroppycode.app
//  Licensed under the GNU AGPLv3
//
//  Floe changes © 2026 René Jiménez, under the same license.
//
//  Ported to Floe from Droppy Code's Services/Providers/ClaudeSession.swift, and modified: only the
//  reading of Claude Code's stream-json output is kept (a text delta, and the result line with its
//  error), for one prompt and one answer run through Shell. The session around it is left out:
//  tools, permissions, thinking, subagents, resuming and usage limits.

import Foundation

/// One prompt, streamed back from the `claude` command line tool as it writes its answer.
enum ClaudeTextStream {
    /// What one line of the tool's output says.
    enum Event: Equatable {
        case text(String)
        /// The whole answer, on the last line.
        case result(String)
        case failure(String)
    }

    /// TextGeneration's arguments for claude, with the answer as stream-json lines and partial messages.
    static func arguments(model: String?) -> [String] {
        [
            "-p", "--output-format", "stream-json", "--verbose", "--include-partial-messages",
            "--model", model ?? "haiku", "--tools", "",
            "--disable-slash-commands", "--strict-mcp-config", "--permission-mode", "dontAsk",
            "--no-session-persistence",
        ]
    }

    /// Nil for a line that carries nothing to show: the session's start, a block's start or stop, usage.
    static func event(in line: String) -> Event? {
        guard let message = (try? JSONSerialization.jsonObject(with: Data(line.utf8))) as? [String: Any] else { return nil }
        switch message["type"] as? String {
        case "stream_event":
            guard let event = message["event"] as? [String: Any], event["type"] as? String == "content_block_delta",
                  let delta = event["delta"] as? [String: Any], delta["type"] as? String == "text_delta",
                  let text = delta["text"] as? String, !text.isEmpty
            else { return nil }
            return .text(text)
        case "result":
            let isError = message["is_error"] as? Bool ?? (message["subtype"] as? String != "success")
            let errors = (message["errors"] as? [String] ?? []).joined(separator: "\n")
            let text = message["result"] as? String ?? errors
            guard isError else { return .result(text) }
            return .failure(text.isEmpty ? "Claude stopped before finishing." : text)
        default:
            return nil
        }
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

        /// Returns the text a line adds, for showing at once.
        mutating func take(_ line: String) -> String? {
            switch ClaudeTextStream.event(in: line) {
            case let .text(text):
                streamed += text
                return text
            case let .result(text):
                result = text
            case let .failure(message):
                failure = message
            case nil:
                break
            }
            return nil
        }

        /// The result line's text, or what was streamed when the tool ended without one.
        var text: String {
            (result.flatMap { $0.isEmpty ? nil : $0 } ?? streamed).trimmingCharacters(in: .whitespacesAndNewlines)
        }
    }

    /// Runs the tool and returns the whole answer, handing each piece of text to `onText` as it arrives.
    /// Cancelling the task stops the tool.
    static func run(
        _ prompt: String,
        executable: URL,
        model: String?,
        environment: [String: String] = LoginEnvironment.current,
        onText: @Sendable (String) async -> Void
    ) async throws -> String {
        let (output, continuation) = AsyncStream.makeStream(of: Data.self)
        async let finished: ShellResult = {
            defer { continuation.finish() }
            return try await Shell.run(
                executable,
                arguments(model: model),
                in: FileManager.default.temporaryDirectory,
                environment: environment,
                input: Data(prompt.utf8),
                timeout: 120,
                onOutput: { continuation.yield($0) }
            )
        }()
        var lines = Lines()
        var answer = Answer()
        for await data in output {
            for line in lines.append(data) {
                if let text = answer.take(line) {
                    await onText(text)
                }
            }
        }
        let result = try await finished
        for line in lines.rest() {
            _ = answer.take(line)
        }
        if let failure = answer.failure {
            throw ShellError(failure)
        }
        guard result.succeeded else {
            throw ShellError(result.failureMessage)
        }
        guard !answer.text.isEmpty else {
            throw ShellError("The model gave no answer.")
        }
        return answer.text
    }
}
