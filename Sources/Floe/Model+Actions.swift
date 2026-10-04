//
//  Model+Actions.swift
//  Project: Floe
//
//  Copyright (Floe) © 2026 René Jiménez
//  Licensed under the GNU AGPLv3

import AppKit

/// The Actions menus of the root search and the file search.
extension LauncherModel {
    private var actionHost: ActionHost {
        ActionHost(
            showHUD: { [weak self] in self?.showHUD($0) },
            dismiss: { [weak self] in
                self?.hidePanel()
                self?.reset()
            }
        )
    }

    var selectedRootItem: RootItem? {
        results.indices.contains(selection) ? results[selection].item : nil
    }

    func rootActions(for item: RootItem) -> [ItemAction?] {
        var actions: [ItemAction?] = [
            ItemAction(title: "Open", symbol: "return") { [weak self] in self?.activate(item) },
        ]
        switch item {
        case let .app(app):
            actions += [nil] + AppActions.actions(for: app, host: actionHost)
        case let .command(command):
            actions.append(ItemAction(title: "Configure Extension…", symbol: "gearshape") { [weak self] in
                self?.hidePanel()
                self?.openSettings(command.extensionName)
            })
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
        default: true
        }
    }

    func fileActions(for file: FileResult) -> [ItemAction?] {
        [
            ItemAction(title: "Open", symbol: "return") { [weak self] in self?.openSelectedFile() },
        ] + FileActions.actions(for: file.url, host: actionHost)
    }
}
