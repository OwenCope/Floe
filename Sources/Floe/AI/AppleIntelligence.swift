//
//  AppleIntelligence.swift
//  Project: Floe
//
//  Copyright (Floe) © 2026 René Jiménez
//  Licensed under the GNU AGPLv3

import Foundation
import FoundationModels

/// The model macOS runs on this Mac, as one more thing that can answer `AI.ask`. Nothing leaves
/// the machine and there is no key; whether it is there at all is the system's to say.
nonisolated enum AppleIntelligence {
    /// Why the model cannot answer, as one sentence for Settings and for a failed request; nil when it can.
    static var problem: String? {
        let model = SystemLanguageModel.default
        switch model.availability {
        case .available:
            return model.supportsLocale(Locale.current) ? nil : String(localized: "Apple Intelligence doesn't work in this Mac's language yet.", bundle: .floe)
        case .unavailable(.appleIntelligenceNotEnabled):
            return String(localized: "Turn on Apple Intelligence in System Settings to use it here.", bundle: .floe)
        case .unavailable(.modelNotReady):
            return String(localized: "Apple Intelligence is still getting its model ready. Try again in a while.", bundle: .floe)
        case .unavailable(.deviceNotEligible):
            return String(localized: "This Mac can't run Apple Intelligence.", bundle: .floe)
        case .unavailable:
            return String(localized: "Apple Intelligence isn't available right now.", bundle: .floe)
        }
    }

    /// The earlier turns as a session's transcript: each question a prompt, each answer a response, oldest first.
    static func transcript(of conversation: AIConversation) -> Transcript {
        Transcript(entries: conversation.earlier.flatMap { turn -> [Transcript.Entry] in
            [
                .prompt(Transcript.Prompt(segments: [.text(Transcript.TextSegment(content: turn.question))])),
                .response(Transcript.Response(assetIDs: [], segments: [.text(Transcript.TextSegment(content: turn.answer))])),
            ]
        })
    }

    /// The system hands back the whole answer so far each time; `emit` is given only what is new.
    /// The session is made for this one request from the turns before it, so asking again or stopping
    /// part way leaves nothing behind in a session.
    @concurrent
    static func answer(_ conversation: AIConversation, emit: @Sendable (String) async -> Void) async throws -> String {
        if let problem {
            throw ProviderError.failed(problem)
        }
        let session = conversation.earlier.isEmpty ? LanguageModelSession() : LanguageModelSession(transcript: transcript(of: conversation))
        var answer = ""
        do {
            for try await snapshot in session.streamResponse(to: conversation.question) {
                let added = addition(from: answer, to: snapshot.content)
                answer = snapshot.content
                if !added.isEmpty {
                    await emit(added)
                }
            }
        } catch let error as LanguageModelSession.GenerationError {
            throw ProviderError.failed(message(for: error))
        }
        return answer
    }

    /// What `current` adds to `previous`; all of it when the model rewrote what came before.
    static func addition(from previous: String, to current: String) -> String {
        current.hasPrefix(previous) ? String(current.dropFirst(previous.count)) : current
    }

    private static func message(for error: LanguageModelSession.GenerationError) -> String {
        switch error {
        case .exceededContextWindowSize: String(localized: "That is more text than Apple Intelligence can take at once.", bundle: .floe)
        case .guardrailViolation, .refusal: String(localized: "Apple Intelligence declined to answer that.", bundle: .floe)
        case .unsupportedLanguageOrLocale: String(localized: "Apple Intelligence doesn't work in that language yet.", bundle: .floe)
        case .rateLimited: String(localized: "Apple Intelligence is busy. Try again in a moment.", bundle: .floe)
        default: error.localizedDescription
        }
    }
}
