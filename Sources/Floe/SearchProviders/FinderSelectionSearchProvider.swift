//
//  FinderSelectionSearchProvider.swift
//  Project: Floe
//
//  Copyright (Floe) © 2026 René Jiménez
//  Licensed under the GNU AGPLv3

import Foundation

/// "Open Finder Selection in Ghostty" and the same for the editor: one row per role that has an app.
struct FinderSelectionSearchProvider: SearchProvider {
    func contribution(for context: SearchContext) -> SearchContribution {
        SearchContribution(ranked: context.preferredApps.map { RootItem.finderSelection($0.role, app: $0.app) })
    }
}
