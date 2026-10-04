//
//  Model+Keys.swift
//  Project: Floe
//
//  Copyright (Floe) © 2026 René Jiménez
//  Licensed under the GNU AGPLv3

import AppKit

/// The panel's keys, for whichever view is on screen.
extension LauncherModel {
    /// Returns true when the key was consumed.
    func handleKey(_ event: NSEvent) -> Bool {
        let flags = event.modifierFlags.intersection([.command, .shift, .option, .control])
        if setup != nil {
            switch event.keyCode {
            case 53: cancelSetup()
            case 36, 76: submitSetup()
            default: return false
            }
            return true
        }
        if event.keyCode == 43, flags == .command {
            hidePanel()
            openSettings(nil)
            return true
        }
        if isSearchingMenuBar, renamingMenuBarItem != nil {
            switch event.keyCode {
            case 36, 76: commitRename()
            case 53: cancelRename()
            default: return false
            }
            return true
        }
        if isSearchingMenuBar, flags == .command, event.keyCode == 14 {
            beginRenamingSelection()
            return true
        }
        if isSearchingMenuBar, flags == .command, event.keyCode == 40 {
            showActions()
            return true
        }
        if isSearchingMenuBar {
            if let delta = Shortcuts.navigationDelta(event.keyCode) {
                menuBarSelection = max(0, min(menuBarSelection + delta, menuBarResults.count - 1))
                return true
            }
            switch event.keyCode {
            case 36, 76:
                if menuBarResults.indices.contains(menuBarSelection) {
                    openMenuBarExtra(menuBarResults[menuBarSelection].extra)
                }
            case 53:
                if menuBarQuery.isEmpty {
                    closeMenuBarSearch()
                } else {
                    menuBarQuery = ""
                }
            default: return false
            }
            return true
        }
        if let session, session.command.mode == "view", session.alert != nil {
            switch event.keyCode {
            case 36, 76: session.resolveAlert(true)
            case 53: session.resolveAlert(false)
            default: return false
            }
            return true
        }
        if isShowingClipboardHistory {
            if let delta = Shortcuts.navigationDelta(event.keyCode) {
                let count = filteredClipboardEntries().count
                clipboardSelection = max(0, min(clipboardSelection + delta, count - 1))
                return true
            }
            switch event.keyCode {
            case 36, 76:
                if let entry = selectedClipboardEntry {
                    pasteClipboardEntry(entry)
                }
            case 51:
                if let entry = selectedClipboardEntry {
                    deleteClipboardEntry(entry)
                }
            case 53:
                if clipboardQuery.isEmpty {
                    closeClipboardHistory()
                } else {
                    clipboardQuery = ""
                }
            default: return false
            }
            return true
        }
        if isSearchingFiles {
            if let delta = Shortcuts.navigationDelta(event.keyCode) {
                fileSearchSelection = max(0, min(fileSearchSelection + delta, fileSearch.results.count - 1))
                return true
            }
            switch event.keyCode {
            case 36 where flags == .command, 76 where flags == .command:
                revealSelectedFile()
            case 36, 76:
                openSelectedFile()
            case 53:
                if fileSearchQuery.isEmpty {
                    closeFileSearch()
                } else {
                    fileSearchQuery = ""
                }
            case 8 where flags == [.command, .shift]:
                copySelectedFilePath()
            case 40 where flags == .command:
                showActions()
            default: return false
            }
            return true
        }
        if let session, session.command.mode == "view", session.failure != nil {
            switch event.keyCode {
            case 36: retry()
            case 53: end(session)
            case 8 where flags == [.command, .shift]: copyFailure()
            default: return false
            }
            return true
        }
        if let session, session.command.mode == "view" {
            return handleSessionKey(event, flags, session)
        }
        if askAI != nil {
            return handleAskAIKey(event, flags)
        }
        if let delta = Shortcuts.navigationDelta(event.keyCode) {
            selection = max(0, min(selection + delta, results.count - 1))
            return true
        }
        switch event.keyCode {
        case 36: if results.indices.contains(selection) {
                let item = results[selection].item
                if case let .emoji(entry) = item, flags == .command {
                    copyEmojiResult(entry)
                } else {
                    activate(item)
                }
            }
        case 53: if query.isEmpty {
                hidePanel()
            } else {
                query = ""
            }
        case 3 where flags == [.command, .shift]:
            if results.indices.contains(selection) {
                toggleFavorite(results[selection].item)
            }
        case 40 where flags == .command:
            showActions()
        default: return false
        }
        return true
    }

    private func handleSessionKey(_ event: NSEvent, _ flags: NSEvent.ModifierFlags, _ session: ExtensionSession) -> Bool {
        let actions = session.actions
        // In a form, arrows and Return belong to the fields; ⌘↵ submits.
        if session.view?.type == "Form", !session.actionMenuOpen {
            switch event.keyCode {
            case 125, 126: return false
            case 36 where flags != .command: return false
            case 36:
                if let action = actions.first {
                    session.run(action)
                }
                return true
            default: break
            }
        }
        if session.actionMenuOpen, handleActionMenuKey(event, flags, session) {
            return true
        }
        if let delta = Shortcuts.navigationDelta(event.keyCode) {
            session.moveSelection(by: delta)
            return true
        }
        switch event.keyCode {
        case 53:
            session.send(["type": "pop"])
        case 33 where flags == .command:
            session.send(["type": "pop"])
        case 36:
            let index = flags == .command ? 1 : 0
            if actions.indices.contains(index) {
                session.run(actions[index])
            }
        case 40 where flags == .command:
            session.actionMenuOpen = true
        default:
            guard !flags.isEmpty, let action = actions.first(where: { Shortcuts.matches($0.props["shortcut"], key: event.charactersIgnoringModifiers, flags: flags) }) else { return false }
            session.run(action)
        }
        return true
    }

    /// While the action menu is open, typing searches it, ↵ runs or opens a submenu, ← and Esc step back.
    private func handleActionMenuKey(_ event: NSEvent, _ flags: NSEvent.ModifierFlags, _ session: ExtensionSession) -> Bool {
        if let delta = Shortcuts.navigationDelta(event.keyCode) {
            session.moveSelection(by: delta)
            return true
        }
        switch event.keyCode {
        case 36, 76: session.activateMenuEntry(at: session.actionSelection)
        case 53, 123: session.closeSubmenuOrMenu()
        case 124:
            let entries = session.menuEntries
            if entries.indices.contains(session.actionSelection), entries[session.actionSelection].isSubmenu {
                session.openSubmenu(entries[session.actionSelection].node)
            }
        case 40 where flags == .command: session.actionMenuOpen = false
        case 51: if !session.actionQuery.isEmpty {
                session.actionQuery.removeLast()
            }
        default:
            // Plain typing (Shift allowed) filters; anything with ⌘, ⌃ or ⌥ falls through to shortcuts.
            guard flags.subtracting(.shift).isEmpty, let characters = event.characters,
                  !characters.isEmpty, characters.unicodeScalars.allSatisfy({ !CharacterSet.controlCharacters.contains($0) })
            else {
                return false
            }
            session.actionQuery += characters
        }
        return true
    }
}
