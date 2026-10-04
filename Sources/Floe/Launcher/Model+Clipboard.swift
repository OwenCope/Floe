//
//  Model+Clipboard.swift
//  Project: Floe
//
//  Copyright (Floe) © 2026 René Jiménez
//  Licensed under the GNU AGPLv3

import AppKit
import Combine

/// The clipboard history in the panel: opening it, and pasting, copying, pinning and deleting an entry.
extension LauncherModel {
    /// Where the Clipboard History command goes now.
    var clipboardDestination: ClipboardDestination {
        settings.clipboardDestination(installed: appLookup)
    }

    /// Switches the panel to the clipboard history, or opens the app chosen to keep it.
    func openClipboardHistory() {
        let destination = clipboardDestination
        guard destination == .floe else {
            openClipboardApp(destination)
            return
        }
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

    /// Hands the command to the chosen app. One that cannot be opened is named in the HUD.
    private func openClipboardApp(_ destination: ClipboardDestination) {
        hidePanel()
        reset()
        switch destination {
        case .floe: break
        case let .app(app): clipboardOpener.app(app.url)
        case let .link(url, app): clipboardOpener.link(url, app?.url)
        case let .unavailable(_, message): showHUD(message)
        }
    }

    /// Follows the clipboard role as Settings changes it: Floe's history view closes, and the row is drawn again.
    func followClipboardRole() -> AnyCancellable {
        settings.$clipboardHandler.removeDuplicates()
            .combineLatest(settings.$clipboardApp.removeDuplicates(), settings.$clipboardURL.removeDuplicates())
            .dropFirst()
            // After the publisher's willSet, so the new value is the one read.
            .sink { [weak self] handler, _, _ in
                DispatchQueue.main.async {
                    if handler != .floe {
                        self?.isShowingClipboardHistory = false
                    }
                    self?.refresh()
                }
            }
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
