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
enum AppleIntelligence {
    /// Why the model cannot answer, as one sentence for Settings and for a failed request; nil when it can.
    static var problem: String? {
        let model = SystemLanguageModel.default
        switch model.availability {
        case .available:
            return model.supportsLocale(Locale.current) ? nil : "Apple Intelligence doesn't work in this Mac's language yet."
        case .unavailable(.appleIntelligenceNotEnabled):
            return "Turn on Apple Intelligence in System Settings to use it here."
        case .unavailable(.modelNotReady):
            return "Apple Intelligence is still getting its model ready. Try again in a while."
        case .unavailable(.deviceNotEligible):
            return "This Mac can't run Apple Intelligence."
        case .unavailable:
            return "Apple Intelligence isn't available right now."
        }
    }

    /// The system hands back the whole answer so far each time; `emit` is given only what is new.
    static func answer(_ prompt: String, emit: @Sendable (String) async -> Void) async throws -> String {
        if let problem {
            throw ProviderError.failed(problem)
        }
        var answer = ""
        do {
            for try await snapshot in LanguageModelSession().streamResponse(to: prompt) {
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
        case .exceededContextWindowSize: "That is more text than Apple Intelligence can take at once."
        case .guardrailViolation, .refusal: "Apple Intelligence declined to answer that."
        case .unsupportedLanguageOrLocale: "Apple Intelligence doesn't work in that language yet."
        case .rateLimited: "Apple Intelligence is busy. Try again in a moment."
        default: error.localizedDescription
        }
    }
}
