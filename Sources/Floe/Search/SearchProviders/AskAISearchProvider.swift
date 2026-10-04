//
//  AskAISearchProvider.swift
//  Project: Floe
//
//  Copyright (Floe) © 2026 René Jiménez
//  Licensed under the GNU AGPLv3

import Foundation

/// Ask AI two ways: `ask why is the sky blue` on top, and for any other text a row at the bottom.
/// Neither is offered while no source can answer.
struct AskAISearchProvider: SearchProvider {
    func contribution(for context: SearchContext) -> SearchContribution {
        guard context.canAskAI, !context.trimmed.isEmpty else { return SearchContribution() }
        if let question = AskAI.question(in: context) {
            return SearchContribution(pinned: [RootResult(item: .askAI(question), section: nil)])
        }
        return SearchContribution(appended: [RootResult(item: .askAI(context.trimmed), section: nil)])
    }
}
