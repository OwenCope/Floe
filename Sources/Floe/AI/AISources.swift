//
//  AISources.swift
//  Project: Floe
//
//  Copyright (Floe) © 2026 René Jiménez
//  Licensed under the GNU AGPLv3

import Foundation

/// The three things that can answer a prompt, each behind a function so a test can stand in for it.
struct AISources: Sendable {
    typealias Emit = @Sendable (String) async -> Void

    var api: @Sendable (AIEndpoint, String, Emit) async throws -> String
    var appleIntelligence: @Sendable (String, Emit) async throws -> String
    /// The prompt, and the model an extension asked for, which decides between claude and codex.
    var tools: @Sendable (String, String?, Emit) async throws -> String

    /// The real ones: the network, the system's model and the installed tools.
    static let live = AISources(
        api: { endpoint, prompt, emit in
            let request = ChatCompletionStream.request(chatURL: endpoint.chatURL, apiKey: endpoint.apiKey, model: endpoint.model, prompt: prompt)
            return try await ChatCompletionStream.run(request, onText: emit)
        },
        appleIntelligence: { prompt, emit in
            try await AppleIntelligence.answer(prompt, emit: emit)
        },
        tools: { prompt, model, emit in
            // A request right after launch waits for the shell, so a tool under nvm or mise is found.
            await LoginEnvironment.load()
            guard let engine = AIEngine.resolve(model: model, which: { LoginEnvironment.which($0) }) else {
                throw ShellError(AIEngine.missingMessage)
            }
            return try await TextGeneration.run(prompt, engine: engine, onText: emit)
        }
    )
}

extension AIAnswer {
    static let localOnlyMessage = "“Only use AI that runs on this Mac” is on, and the AI source you chose sends questions elsewhere, so nothing was asked. "
        + "Turn the switch off under Settings › Privacy, or choose Apple Intelligence or a server on this Mac under Settings › General › AI."

    /// Why the chosen source will not be asked, as one message for the person who asked; nil when it may be.
    static func refusal(for choice: Choice, localOnly: Bool) -> String? {
        localOnly && !AskAI.isOnThisMac(choice) ? localOnlyMessage : nil
    }

    /// Answers a prompt with the chosen source, for Ask AI and for an extension's `AI.ask` alike.
    /// It answers or the request fails: nothing else is tried, so a question never leaves by a fallback.
    static func answer(
        _ prompt: String,
        model: String?,
        choice: Choice,
        localOnly: Bool,
        sources: AISources = .live,
        emit: AISources.Emit
    ) async throws -> String {
        let started = Date()
        do {
            let text = try await route(prompt, model: model, choice: choice, localOnly: localOnly, sources: sources, emit: emit)
            Log.ai.info("\(choice.logName) answered \(prompt.count) characters in \(Log.milliseconds(since: started)) ms")
            return text
        } catch {
            Log.ai.error("\(choice.logName) failed after \(Log.milliseconds(since: started)) ms: \(error.localizedDescription)")
            throw error
        }
    }

    private static func route(
        _ prompt: String,
        model: String?,
        choice: Choice,
        localOnly: Bool,
        sources: AISources,
        emit: AISources.Emit
    ) async throws -> String {
        if case .api(nil) = choice {
            throw ProviderError.failed(incompleteMessage)
        }
        if let refusal = refusal(for: choice, localOnly: localOnly) {
            throw ProviderError.failed(refusal)
        }
        switch choice {
        case let .api(endpoint?):
            return try await sources.api(endpoint, prompt, emit)
        case .api:
            throw ProviderError.failed(incompleteMessage)
        case .appleIntelligence:
            return try await sources.appleIntelligence(prompt, emit)
        case .tools:
            return try await sources.tools(prompt, model, emit)
        }
    }

    /// Whether the choice can answer at all. `toolInstalled` and `appleIntelligenceReady` are only
    /// asked about the source that was chosen.
    static func isAvailable(choice: Choice, localOnly: Bool, toolInstalled: () -> Bool, appleIntelligenceReady: () -> Bool) -> Bool {
        guard refusal(for: choice, localOnly: localOnly) == nil else { return false }
        switch choice {
        case .tools: return toolInstalled()
        case let .api(endpoint): return endpoint != nil
        case .appleIntelligence: return appleIntelligenceReady()
        }
    }
}
