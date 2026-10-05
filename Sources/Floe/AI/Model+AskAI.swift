//
//  Model+AskAI.swift
//  Project: Floe
//
//  Copyright (Floe) © 2026 René Jiménez
//  Licensed under the GNU AGPLv3

import AppKit

/// Showing and leaving Ask AI's answer view; the question and its answer are `AskAIModel`'s.
extension LauncherModel {
    /// Replaces the list with the answer to one question. The query stays, for when the view is left.
    func openAskAI(_ question: String) {
        askAI?.leave()
        let asking = AskAIModel(question: question, source: AskAI.configuredSource(settings), request: askAIRequest)
        asking.host = modeHost { [weak self] in self?.closeAskAI() }
        askAI = asking
        asking.ask()
    }

    /// Back to the root search. The request stops and the answer is gone: there is no history.
    func closeAskAI() {
        guard let asking = askAI else { return }
        asking.leave()
        askAI = nil
        focusToken += 1
    }

    /// The answer view went off screen, because something else took the panel.
    func leaveAskAI(_ asking: AskAIModel) {
        if askAI === asking {
            closeAskAI()
        } else {
            asking.leave()
        }
    }
}
