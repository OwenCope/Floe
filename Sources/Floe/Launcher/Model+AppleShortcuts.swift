//
//  Model+AppleShortcuts.swift
//  Project: Floe
//
//  Copyright (Floe) © 2026 René Jiménez
//  Licensed under the GNU AGPLv3

import AppKit
import SwiftUI

/// The launcher's side of the user's shortcuts: the switch, the list for the search, and running one.
extension LauncherModel {
    /// The switch in Settings, Privacy. Off, the Shortcuts tool is never started.
    var findsShortcuts: Bool {
        settings.searchSources.contains(SearchSourceInfo.shortcuts.id)
    }

    /// What the search may show: nothing the moment the switch goes off.
    var shortcutsForSearch: [AppleShortcut] {
        guard findsShortcuts else { return [] }
        return shortcutLibrary.shortcuts
    }

    /// Asks for the list again. The task is nil when the switch is off, and is for tests to wait on.
    @discardableResult
    func reloadShortcuts() -> Task<Void, Never>? {
        shortcutLibrary.refresh(isOn: findsShortcuts) { [weak self] in
            // Nothing to redraw without a query: the shortcuts are only searched for.
            guard let self, !query.isEmpty else { return }
            refresh()
        }
    }

    /// Return on a shortcut: the panel goes, the run goes on behind it, and only a failure is heard of.
    func run(_ shortcut: AppleShortcut) {
        hidePanel()
        reset()
        _ = shortcutLibrary.run(shortcut) { [weak self] in self?.showHUD($0) }
    }

    func openInShortcuts(_ shortcut: AppleShortcut) {
        hidePanel()
        reset()
        _ = shortcutLibrary.openInShortcuts(shortcut) { [weak self] in self?.showHUD($0) }
    }

    /// The Actions menu of a shortcut, after Run.
    func shortcutActions(for shortcut: AppleShortcut) -> [ItemAction?] {
        [
            nil,
            ItemAction(title: "Open in Shortcuts", symbol: "arrow.up.forward.app") { [weak self] in self?.openInShortcuts(shortcut) },
            ItemAction(title: "Copy Name", symbol: "doc.on.doc") { [weak self] in
                NSPasteboard.general.copy(shortcut.name)
                self?.showHUD("Copied \(shortcut.name)")
            },
        ]
    }
}

/// The Shortcuts app's icon says where a shortcut runs; a plain tile stands in on a Mac without the app.
struct AppleShortcutIcon: View {
    static let applicationPath = "/System/Applications/Shortcuts.app"
    private static let hasApplication = FileManager.default.fileExists(atPath: applicationPath)

    var body: some View {
        if Self.hasApplication {
            AppIconView(path: Self.applicationPath, size: 24)
        } else {
            SymbolTile(symbol: "square.2.layers.3d")
        }
    }
}
