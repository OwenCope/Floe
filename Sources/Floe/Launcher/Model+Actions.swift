//
//  Model+Actions.swift
//  Project: Floe
//
//  Copyright (Floe) © 2026 René Jiménez
//  Licensed under the GNU AGPLv3

import AppKit

/// The Actions menu of the root search.
extension LauncherModel {
    private var actionHost: ActionHost {
        ActionHost(
            showHUD: { [weak self] in self?.showHUD($0) },
            dismiss: { [weak self] in
                self?.hidePanel()
                self?.reset()
            },
            preferredApps: preferredApps
        )
    }

    var selectedRootItem: RootItem? {
        results.indices.contains(selection) ? results[selection].item : nil
    }

    /// What Return does to a result, as its button and the first row of its menu say it.
    func primaryActionTitle(for item: RootItem) -> String {
        switch item {
        case let .command(command) where command.mode == "menu-bar":
            isInMenuBar(command) ? "Remove from Menu Bar" : "Add to Menu Bar"
        case .clipboardEntry: "Paste"
        case .askAI: "Ask"
        case .sshHost: "Connect"
        case .menuBarItem: "Click Item"
        case .browserTab(.tab): "Switch to Tab"
        default: "Open"
        }
    }

    /// Opens a scope's row the way its own view does: the file, the pasted entry, the clicked item.
    func openScopeResult(_ item: RootItem) {
        switch item {
        case let .file(file): fileSearch.open(file)
        case let .clipboardEntry(entry): clipboardHistory.paste(entry)
        case let .menuBarItem(extra, _): menuBarSearch.open(extra)
        case .menuBarAccess: openMenuBarSearch()
        case let .browserTab(.tab(tab)): switchToBrowserTab(tab)
        case let .browserTab(.access(browser)): SystemCommand.askForAutomation(toControl: browser.name)
        case let .webAddress(address): open(address)
        default: break
        }
    }

    /// Brings a tab forward once the panel is gone. A refusal is answered here, where the user asked for the tab.
    private func switchToBrowserTab(_ tab: BrowserTab) {
        hidePanel()
        reset()
        BrowserTabs.activate(tab) { [weak self] outcome in
            switch outcome {
            case .text(BrowserTabScripts.switched): break
            case .refused: SystemCommand.askForAutomation(toControl: tab.browser.name)
            case .text, .failed: self?.showHUD("That tab is no longer open")
            }
        }
    }

    func rootActions(for item: RootItem) -> [ItemAction?] {
        var actions: [ItemAction?] = [
            ItemAction(title: primaryActionTitle(for: item), symbol: "return") { [weak self] in self?.activate(item) },
        ]
        switch item {
        case let .app(app):
            actions += [nil] + AppActions.actions(for: app, host: actionHost)
        case let .command(command):
            actions.append(ItemAction(title: "Configure Extension…", symbol: "gearshape") { [weak self] in
                self?.hidePanel()
                self?.openSettings(command.extensionName)
            })
        case let .file(file):
            actions += FileActions.actions(for: file.url, host: actionHost)
        case let .sshHost(host, _):
            actions += SSHHostActions.actions(for: host, host: actionHost)
        case let .clipboardEntry(entry):
            actions.append(ItemAction(title: "Copy", symbol: "doc.on.doc") { [weak self] in self?.clipboardHistory.copy(entry) })
        default:
            break
        }
        if Self.keepsItsPlace(item) {
            let favorite = isFavorite(item)
            actions += [
                nil,
                ItemAction(title: favorite ? "Remove from Favorites" : "Add to Favorites", symbol: favorite ? "star.slash" : "star") { [weak self] in
                    self?.toggleFavorite(item)
                },
            ]
        }
        return actions
    }

    /// Whether a result is there the next time the launcher opens, so a favorite of it means something.
    static func keepsItsPlace(_ item: RootItem) -> Bool {
        switch item {
        case .calculator, .emoji, .searchFiles, .event, .quicklink: false
        case .file, .clipboardEntry, .menuBarItem, .menuBarAccess: false
        case .browserTab: false
        case .askAI, .webAddress: false
        default: true
        }
    }
}
