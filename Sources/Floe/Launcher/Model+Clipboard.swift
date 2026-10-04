//
//  Model+Clipboard.swift
//  Project: Floe
//
//  Copyright (Floe) © 2026 René Jiménez
//  Licensed under the GNU AGPLv3

import AppKit

/// The clipboard history in the panel: opening it, and pasting, copying, pinning and deleting an entry.
extension LauncherModel {
    /// Switches the panel to the clipboard history.
    func openClipboardHistory() {
        if let session {
            end(session)
        }
        setup = nil
        isSearchingMenuBar = false
        isShowingClipboardHistory = true
        clipboardQuery = ""
        clipboardSelection = 0
        showPanel()
        focusToken += 1
    }

    func closeClipboardHistory() {
        isShowingClipboardHistory = false
        focusToken += 1
    }

    /// History entries matching the clipboard query, pins first, then newest first.
    func filteredClipboardEntries() -> [ClipboardEntry] {
        ClipboardSearchScope.matching(ClipboardHistoryStore.shared.entries, query: clipboardQuery)
    }

    var selectedClipboardEntry: ClipboardEntry? {
        let entries = filteredClipboardEntries()
        return entries.indices.contains(clipboardSelection) ? entries[clipboardSelection] : nil
    }

    /// Copies the entry, then pastes with Command-V when Accessibility allows it.
    func pasteClipboardEntry(_ entry: ClipboardEntry) {
        usage.recordUse(of: RootItem.clipboardHistory.id)
        guard ClipboardHistoryStore.writeToPasteboard(entry) else { return }
        hidePanel()
        reset()
        if ClipboardHistoryStore.canPasteDirectly {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                ClipboardHistoryStore.simulatePaste()
            }
        } else {
            showHUD("Copied. Press ⌘V to paste.")
        }
    }

    func copyClipboardEntry(_ entry: ClipboardEntry) {
        guard ClipboardHistoryStore.writeToPasteboard(entry) else { return }
        showHUD("Copied")
    }

    func deleteClipboardEntry(_ entry: ClipboardEntry) {
        ClipboardHistoryStore.shared.delete(entry)
        clipboardSelection = max(0, min(clipboardSelection, filteredClipboardEntries().count - 1))
    }

    func toggleClipboardPin(_ entry: ClipboardEntry) {
        ClipboardHistoryStore.shared.togglePin(entry)
    }
}
