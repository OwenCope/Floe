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
//  tools, permissions, thinking, subagents, resuming and usage limits. The reading of the lines
//  themselves is in ToolTextStream.swift.

import Foundation

/// One prompt, streamed back from the `claude` command line tool as it writes its answer.
nonisolated enum ClaudeTextStream {
    typealias Event = ToolTextStream.Event

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
            return .failure(text.isEmpty ? String(localized: "Claude stopped before finishing.", bundle: .floe) : text)
        default:
            return nil
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
        let launch = ToolTextStream.Launch(
            executable: executable,
            arguments: arguments(model: model),
            directory: FileManager.default.temporaryDirectory,
            environment: environment,
            timeout: 120
        )
        return try await ToolTextStream.run(prompt, launch: launch, read: event(in:), onText: onText)
    }
}
