//
//  SettingsSearchNavigation.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3
//
//  Floe changes © 2026 René Jiménez, under the same license.
//
//  Thaw 3's Settings/Search/SettingsSearchNavigation.swift. Thaw's pending request opens a
//  disclosure in the target pane; Floe's scrolls the pane to the chosen control.

import Foundation

/// Coordinates settings search and sidebar selection so a scroll request cannot leak into a
/// later, unrelated navigation.
@MainActor
enum SettingsSearchNavigation {
    static func selectSearchResult(_ entry: SearchEntry, selection: SettingsSelection, search: SearchModel) {
        search.requestedAnchor = entry.anchor
        selection.page = entry.pane
        search.searchText = ""
    }

    /// A sidebar jump ends the search, or the detail column keeps stale results.
    static func selectSidebarPane(_ page: SettingsPage, selection: SettingsSelection, search: SearchModel) {
        search.searchText = ""
        guard selection.page != page else {
            return
        }
        search.requestedAnchor = nil
        selection.page = page
    }

    /// Hands the pending anchor to the pane that is about to scroll to it, once.
    static func consumeAnchor(search: SearchModel) -> String? {
        guard let anchor = search.requestedAnchor else {
            return nil
        }
        search.requestedAnchor = nil
        return anchor
    }
}
