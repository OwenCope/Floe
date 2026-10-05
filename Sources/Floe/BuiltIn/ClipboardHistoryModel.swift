//
//  ClipboardHistoryModel.swift
//  Project: Floe
//
//  Copyright (Floe) © 2026 René Jiménez
//  Licensed under the GNU AGPLv3

import AppKit

/// The clipboard history in the panel: its query and selection, and pasting, copying, pinning
/// and deleting an entry. The copies themselves are `ClipboardHistoryStore`'s.
final class ClipboardHistoryModel: ObservableObject {
    @Published var query = "" {
        didSet { selection = 0 }
    }

    @Published var selection = 0
    var host = ModeHost()
    private let usage: UsageStore
    /// Asked for on first use: the user's own store starts with the first thing that reads it.
    private let store: () -> ClipboardHistoryStore

    init(usage: UsageStore, store: @escaping () -> ClipboardHistoryStore = { .shared }) {
        self.usage = usage
        self.store = store
    }

    /// History entries matching the query, pins first, then newest first.
    func filteredEntries() -> [ClipboardEntry] {
        ClipboardSearchScope.matching(store().entries, query: query)
    }

    var selectedEntry: ClipboardEntry? {
        let entries = filteredEntries()
        return entries.indices.contains(selection) ? entries[selection] : nil
    }

    /// Copies the entry, then pastes with Command-V when Accessibility allows it.
    func paste(_ entry: ClipboardEntry) {
        usage.recordUse(of: RootItem.clipboardHistory.id)
        guard ClipboardHistoryStore.writeToPasteboard(entry) else { return }
        host.dismiss()
        if ClipboardHistoryStore.canPasteDirectly {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                ClipboardHistoryStore.simulatePaste()
            }
        } else {
            host.showHUD("Copied. Press ⌘V to paste.")
        }
    }

    func copy(_ entry: ClipboardEntry) {
        guard ClipboardHistoryStore.writeToPasteboard(entry) else { return }
        host.showHUD("Copied")
    }

    func delete(_ entry: ClipboardEntry) {
        store().delete(entry)
        selection = max(0, min(selection, filteredEntries().count - 1))
    }

    func togglePin(_ entry: ClipboardEntry) {
        store().togglePin(entry)
    }

    /// The panel's keys while the history is on screen. Returns true when the key was consumed.
    func handleKey(_ event: NSEvent) -> Bool {
        if let delta = Shortcuts.navigationDelta(event.keyCode) {
            let count = filteredEntries().count
            selection = max(0, min(selection + delta, count - 1))
            return true
        }
        switch event.keyCode {
        case 36, 76:
            if let entry = selectedEntry {
                paste(entry)
            }
        case 51:
            if let entry = selectedEntry {
                delete(entry)
            }
        case 53:
            if query.isEmpty {
                host.close()
            } else {
                query = ""
            }
        default: return false
        }
        return true
    }
}
