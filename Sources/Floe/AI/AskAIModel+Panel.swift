//
//  AskAIModel+Panel.swift
//  Project: Floe
//
//  Copyright (Floe) © 2026 René Jiménez
//  Licensed under the GNU AGPLv3

import AppKit

/// What the answer view's buttons, menu and keys do with the answer.
extension AskAIModel {
    func copyAnswer() {
        guard !answer.isEmpty else { return }
        NSPasteboard.general.copy(answer)
        host.showHUD(String(localized: "Copied Answer", bundle: .floe))
    }

    /// Into the app the user came from, as a snippet is pasted.
    func pasteAnswer() {
        guard !answer.isEmpty else { return }
        host.paste(answer)
    }

    /// What Return does, which is also what the bar says it does.
    enum ReturnAction: Equatable {
        case askFollowUp
        case askAgain
        case copyAnswer
        case nothing
    }

    /// A follow-up typed in the field is asked. With the field empty, a failed question is asked again
    /// and a finished answer is copied.
    var returnAction: ReturnAction {
        if hasDraft {
            return .askFollowUp
        }
        if case .failed = state {
            return .askAgain
        }
        return isWorking || answer.isEmpty ? .nothing : .copyAnswer
    }

    func primaryAction() {
        switch returnAction {
        case .askFollowUp: askFollowUp()
        case .askAgain: ask()
        case .copyAnswer: copyAnswer()
        case .nothing: break
        }
    }

    func actions() -> [ItemAction?] {
        var actions: [ItemAction?] = []
        if !answer.isEmpty {
            actions += [
                ItemAction(title: String(localized: "Copy Answer", bundle: .floe), symbol: "doc.on.doc") { [weak self] in self?.copyAnswer() },
                ItemAction(title: String(localized: "Paste Answer", bundle: .floe), symbol: "doc.on.clipboard") { [weak self] in self?.pasteAnswer() },
                nil,
            ]
        }
        actions.append(ItemAction(title: String(localized: "Ask Again", bundle: .floe), symbol: "arrow.clockwise") { [weak self] in self?.ask() })
        return actions
    }

    /// Returns true when the key was consumed. Escape goes back; the arrows scroll the conversation.
    func handleKey(_ event: NSEvent, _ flags: NSEvent.ModifierFlags) -> Bool {
        if let lines = Shortcuts.navigationDelta(event.keyCode) {
            scroll(by: lines)
            return true
        }
        switch event.keyCode {
        case 53: host.close()
        case 36 where flags == .command, 76 where flags == .command: pasteAnswer()
        case 36, 76: primaryAction()
        case 15 where flags == .command: ask()
        case 40 where flags == .command: host.showActions()
        // Typing is the field's, and so is a shortcut such as Command-C.
        default: return false
        }
        return true
    }
}
