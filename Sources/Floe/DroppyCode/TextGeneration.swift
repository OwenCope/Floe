//
//  TextGeneration.swift
//  Project: Droppy Code
//
//  Copyright (Droppy Code) © 2026 Jordy Spruit
//  Droppy Code by Jordy Spruit (Droppy), https://getdroppycode.app
//  Licensed under the GNU AGPLv3
//
//  Floe changes © 2026 René Jiménez, under the same license.
//
//  Ported to Floe from Droppy Code's Services/Providers/TextGeneration.swift, and modified: the
//  thread title and commit message prompts are left out, the prompt is the caller's, both engines
//  take an optional model, a failure is thrown with the tool's own words, and the arguments are
//  built by a function a test can call.

import Foundation

/// One-shot text generation through a provider's command line tool with no tools of its own,
/// on the account the user is already signed in to.
enum TextGeneration {
    enum Engine: Sendable, Equatable {
        case claude(executable: URL, model: String?)
        case codex(executable: URL, model: String?)

        var executable: URL {
            switch self {
            case let .claude(executable, _), let .codex(executable, _): executable
            }
        }

        var timeout: TimeInterval {
            switch self {
            case .claude: 120
            case .codex: 180
            }
        }
    }

    /// The arguments for one run. Codex writes its last message to `output`, since its standard
    /// output carries the whole session.
    static func arguments(for engine: Engine, output: URL) -> [String] {
        switch engine {
        case let .claude(_, model):
            [
                "-p", "--output-format", "text", "--model", model ?? "haiku", "--tools", "",
                "--disable-slash-commands", "--strict-mcp-config", "--permission-mode", "dontAsk",
                "--no-session-persistence",
            ]
        case let .codex(_, model):
            ["exec", "--ephemeral", "--skip-git-repo-check", "-s", "read-only"]
                + (model.map { ["--model", $0] } ?? [])
                + ["--config", "model_reasoning_effort=\"low\"", "--output-last-message", output.path, "-"]
        }
    }

    static func run(_ prompt: String, engine: Engine, environment: [String: String] = LoginEnvironment.current) async throws -> String {
        let directory = FileManager.default.temporaryDirectory
        let output = directory.appendingPathComponent("floe-\(UUID().uuidString).txt")
        defer { try? FileManager.default.removeItem(at: output) }
        let result = try await Shell.run(
            engine.executable,
            arguments(for: engine, output: output),
            in: directory,
            environment: environment,
            input: Data(prompt.utf8),
            timeout: engine.timeout
        )
        guard result.succeeded else {
            throw ShellError(result.failureMessage)
        }
        let text: String = switch engine {
        case .claude: result.trimmedOutput
        case .codex: ((try? String(contentsOf: output, encoding: .utf8)) ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        }
        guard !text.isEmpty else {
            throw ShellError("The model gave no answer.")
        }
        return text
    }
}
