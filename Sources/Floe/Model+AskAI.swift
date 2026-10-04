//
//  Model+AskAI.swift
//  Project: Floe
//
//  Copyright (Floe) © 2026 René Jiménez
//  Licensed under the GNU AGPLv3

import AppKit

/// Ask AI in the panel: opening the answer view, its keys and its actions.
extension LauncherModel {
    /// Replaces the list with the answer to one question. The query stays, for when the view is left.
    func openAskAI(_ question: String) {
        askAI?.leave()
        let asking = AskAIModel(question: question, source: AskAI.configuredSource(settings), request: askAIRequest)
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

    func copyAskAIAnswer() {
        guard let answer = askAI?.answer, !answer.isEmpty else { return }
        NSPasteboard.general.copy(answer)
        showHUD("Copied Answer")
    }

    /// Into the app the user came from, as a snippet is pasted.
    func pasteAskAIAnswer() {
        guard let answer = askAI?.answer, !answer.isEmpty else { return }
        paste(text: answer)
    }

    /// What Return does: the answer is copied once there is one, and a failed question is asked again.
    func askAIPrimaryAction() {
        guard let asking = askAI else { return }
        if case .failed = asking.state {
            asking.ask()
        } else if !asking.isWorking {
            copyAskAIAnswer()
        }
    }

    func askAIActions() -> [ItemAction?] {
        guard let asking = askAI else { return [] }
        var actions: [ItemAction?] = []
        if !asking.answer.isEmpty {
            actions += [
                ItemAction(title: "Copy Answer", symbol: "doc.on.doc") { [weak self] in self?.copyAskAIAnswer() },
                ItemAction(title: "Paste Answer", symbol: "doc.on.clipboard") { [weak self] in self?.pasteAskAIAnswer() },
                nil,
            ]
        }
        actions.append(ItemAction(title: "Ask Again", symbol: "arrow.clockwise") { [weak asking] in asking?.ask() })
        return actions
    }

    /// Returns true when the key was consumed. Escape goes back; the arrows scroll the answer.
    func handleAskAIKey(_ event: NSEvent, _ flags: NSEvent.ModifierFlags) -> Bool {
        guard let asking = askAI else { return false }
        if let lines = Shortcuts.navigationDelta(event.keyCode) {
            asking.scroll(by: lines)
            return true
        }
        switch event.keyCode {
        case 53: closeAskAI()
        case 36 where flags == .command, 76 where flags == .command: pasteAskAIAnswer()
        case 36, 76: askAIPrimaryAction()
        case 15 where flags == .command: asking.ask()
        case 40 where flags == .command: showActions()
        // There is no field to type in; a shortcut such as Command-C still reaches the selected text.
        default: return flags.subtracting(.shift).isEmpty
        }
        return true
    }
}
