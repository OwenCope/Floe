//
//  Model+Modes.swift
//  Project: Floe
//
//  Copyright (Floe) © 2026 René Jiménez
//  Licensed under the GNU AGPLv3

import Foundation

/// The modes with a model of their own, and what the launcher model lends each of them.
extension LauncherModel {
    /// Called once from `init`. The hooks are read when they are called, so the app delegate's are the ones used.
    func connectModes() {
        menuBarSearch.host = modeHost { [weak self] in self?.closeMenuBarSearch() }
        clipboardHistory.host = modeHost { [weak self] in self?.closeClipboardHistory() }
        fileSearch.host = modeHost { [weak self] in self?.closeFileSearch() }
        fileSearch.preferredApps = { [weak self] in self?.preferredApps ?? [] }
    }

    func modeHost(close: @escaping () -> Void) -> ModeHost {
        ModeHost(
            showHUD: { [weak self] in self?.showHUD($0) },
            hidePanel: { [weak self] in self?.hidePanel() },
            dismiss: { [weak self] in
                self?.hidePanel()
                self?.reset()
            },
            refocus: { [weak self] in self?.focusToken += 1 },
            close: close,
            showActions: { [weak self] in self?.showActions() },
            paste: { [weak self] in self?.paste(text: $0) }
        )
    }
}
