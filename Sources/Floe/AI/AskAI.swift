//
//  AskAI.swift
//  Project: Floe
//
//  Copyright (Floe) © 2026 René Jiménez
//  Licensed under the GNU AGPLv3

import Foundation

/// Ask AI, the launcher's own way to the source chosen in Settings: one question, one answer.
/// What is here is the part that needs no panel: the keyword, where a source runs, and who answered.
enum AskAI {
    /// `ask why is the sky blue` leads the search with the question.
    static let keyword = "ask"
    /// A question in a speech bubble; the row, the view and the menu all use it.
    static let symbol = "questionmark.bubble"
    /// Stands in for an answer where the view is drawn without asking anything (`--panel-snapshot`).
    static nonisolated let sampleAnswer = """
    Tides are the sea rising and falling, **twice a day** in most places.

    1. The Moon pulls the water nearest to it into a bulge.
    2. A second bulge forms on the far side of the Earth.
    3. As the Earth turns, a coast passes through both.

    > The Sun does the same with about half the strength.

    - Spring tides: Sun and Moon in line.
    - Neap tides: Sun and Moon at right angles.

    ```
    high tide to high tide: about 12 h 25 min
    ```
    """

    /// Who answers, and whether the question stays on this Mac.
    struct Source: Equatable {
        /// One line for under the answer, such as "Ollama, on this Mac" or "openrouter.ai".
        let line: String
        let isOnThisMac: Bool
    }

    /// The question in a query that starts with the keyword, as a scope reads its own (see `SearchContext.text(after:)`).
    static func question(in context: SearchContext) -> String? {
        context.text(after: keyword)
    }

    /// Whether a question stays on this Mac: Apple Intelligence, and an API whose address is on this Mac.
    /// A command line tool never counts, even pointed at a local model: Floe cannot see where it sends a question.
    static nonisolated func isOnThisMac(_ choice: AIAnswer.Choice) -> Bool {
        switch choice {
        case .appleIntelligence: true
        case let .api(endpoint): AIEndpoint.isOnThisMac(endpoint?.chatURL)
        case .tools: false
        }
    }

    /// Who would answer and where. `tool` is the command line tool that will answer, such as "claude".
    /// Nil when nothing can answer: no tool installed, or an API that is not filled in.
    static func source(for choice: AIAnswer.Choice, tool: String?) -> Source? {
        switch choice {
        case .appleIntelligence:
            return Source(line: String(localized: "Apple Intelligence, on this Mac", bundle: .floe), isOnThisMac: true)
        case .tools:
            return tool.map { Source(line: String(localized: "The \($0) tool, on your account", bundle: .floe, comment: "The placeholder is the name of a command line tool such as claude."), isOnThisMac: false) }
        case let .api(endpoint):
            guard let endpoint, let host = endpoint.chatURL.host else { return nil }
            guard isOnThisMac(choice) else { return Source(line: host, isOnThisMac: false) }
            // Ollama and LM Studio are known by their address; any other local server by its port.
            let service = AIService.allCases.first { $0.baseURL.flatMap(AIEndpoint.chatURL(baseURL:)) == endpoint.chatURL }
            let address = endpoint.chatURL.port.map { "\(host):\($0)" } ?? host
            return Source(line: service?.title ?? String(localized: "\(address), on this Mac", bundle: .floe, comment: "The placeholder is the address of a server such as localhost:8080."), isOnThisMac: true)
        }
    }

    /// The command line tool the settings choose, looked up on the PATH known so far; nil when it is not installed.
    static func configuredTool(_ settings: AppSettings) -> String? {
        AIEngine.resolve(model: nil, setup: AIEngine.Setup(settings), which: { LoginEnvironment.which($0) })?.toolName
    }

    /// The source the settings choose.
    static func configuredSource(_ settings: AppSettings) -> Source? {
        source(for: AIAnswer.configured(settings), tool: configuredTool(settings))
    }

    /// Whether a source can answer, asked at most once per `lifetime`: the search asks on every
    /// keystroke, and the answer may cost a Keychain read or a walk of the PATH.
    static func availabilityCheck(
        lifetime: TimeInterval = 2,
        now: @escaping () -> Date = Date.init,
        check: @escaping () -> Bool
    ) -> () -> Bool {
        var last: (at: Date, value: Bool)?
        return {
            if let last, now().timeIntervalSince(last.at) < lifetime {
                return last.value
            }
            let value = check()
            last = (now(), value)
            return value
        }
    }
}
