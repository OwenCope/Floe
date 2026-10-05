//
//  MenuBarSearchView.swift
//  Project: Floe
//
//  Copyright (Floe) © 2026 René Jiménez
//  Licensed under the GNU AGPLv3

import SwiftUI
import ThawUI

/// The menu bar search in the face of Thaw 3's inspector panel: a field in a glass capsule above the list,
/// rows with each item's owning app and name, and a bar of actions below.
struct MenuBarSearchView: View {
    @ObservedObject var search: MenuBarSearchModel
    /// For the gear and the Actions menu. Not observed: nothing here is drawn from it.
    let launcher: LauncherModel
    let focusToken: Int
    @ObservedObject var settings: AppSettings = .shared

    @Environment(\.panelPieces) private var pieces

    var body: some View {
        Group {
            if pieces == nil {
                GlassEffectContainer {
                    content
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .safeAreaBar(edge: .top, spacing: 0) { queryField }
                        .safeAreaBar(edge: .bottom, spacing: 0) { bottomBar }
                }
            } else {
                // The field is its own piece, so only the bottom bar is left to sit over the list.
                PanelSections {
                    queryField
                } content: {
                    content
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .safeAreaBar(edge: .bottom, spacing: 0) { bottomBar }
                }
            }
        }
        .scrollEdgeEffectStyle(.automatic, for: .vertical)
    }

    // MARK: Query field

    private var queryField: some View {
        SearchQueryField(
            prompt: String(localized: "Search menu bar items…", bundle: .floe),
            text: $search.query,
            focusToken: focusToken,
            isLoading: search.isScanning
        ) { EmptyView() }
    }

    // MARK: Content

    /// Either the matching rows or the state that explains why there are none.
    @ViewBuilder
    private var content: some View {
        let hasQuery = !search.query.trimmingCharacters(in: .whitespaces).isEmpty
        if !search.accessGranted {
            // Distinct from "nothing matched": without Accessibility the walk returns an empty list.
            ThawEmptyState(
                systemImage: "hand.raised",
                title: "Accessibility is off",
                caption: "Floe needs Accessibility to list your menu bar items.",
                actionTitle: "Grant Access",
                action: { search.requestAccess() }
            )
        } else if search.isScanning, search.results.isEmpty {
            ThawEmptyState(systemImage: "menubar.rectangle", title: "Reading your menu bar…", isLoading: true)
        } else if hasQuery, search.results.isEmpty {
            ThawEmptyState(
                systemImage: "magnifyingglass",
                title: "No items match",
                caption: "Try part of the item's name or the app that owns it."
            )
        } else if search.results.isEmpty {
            ThawEmptyState(
                systemImage: "menubar.rectangle",
                title: "No menu bar items found",
                caption: "Floe lists the items apps put in the menu bar."
            )
        } else {
            rows
        }
    }

    private var rows: some View {
        let results = search.results
        return ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(Array(results.enumerated()), id: \.element.id) { index, result in
                        // One view per item, title included: a lazy stack walks the whole list when rows vary in count.
                        VStack(spacing: 0) {
                            if let section = result.section, index == 0 || results[index - 1].section != section {
                                SearchSectionHeader(title: section)
                            }
                            InspectorItemRow(
                                extra: result.extra,
                                name: search.displayName(for: result.extra),
                                renameDraft: search.renamingItem == result.extra.id ? $search.renameDraft : nil
                            )
                            .modifier(SearchRowBackground(selected: index == search.selection))
                            .onTapGesture(count: 2) { search.open(result.extra) }
                            .onTapGesture { search.selection = index }
                        }
                        .id(result.id)
                    }
                }
            }
            .scrollIndicatorsFlash(onAppear: true)
            .contentMargins(.all, ThawSpacing.base, for: .scrollContent)
            .scrollContentBackground(.hidden)
            .onChange(of: search.selection) {
                if results.indices.contains(search.selection) {
                    proxy.scrollTo(results[search.selection].id)
                }
            }
        }
    }

    // MARK: Bottom bar

    private var bottomBar: some View {
        HStack {
            OpenSettingsButton(model: launcher)

            Toggle("Remember last search", isOn: $settings.rememberMenuBarQuery)
                .toggleStyle(.switch)
                .controlSize(.mini)

            Spacer()

            if search.renamingItem != nil {
                ShortcutHintButton(title: String(localized: "Cancel", bundle: .floe)) { search.cancelRename() } hint: {
                    KeyCapView(text: "⎋", font: ThawType.detail)
                }
                ShortcutHintButton(title: String(localized: "Rename", bundle: .floe, comment: "A button that saves the new name of a menu bar item.")) { search.commitRename() } hint: {
                    KeyCapView(systemImage: "return")
                }
            } else if let extra = search.selectedExtra {
                ShortcutHintButton(title: String(localized: "Edit Name", bundle: .floe)) { search.beginRenamingSelection() } hint: {
                    KeyCapView(text: "⌘")
                    Text(verbatim: "+")
                    KeyCapView(text: "E")
                }
                ActionsButton(model: launcher) { $0.menuBarSearch.selectedExtra.map($0.menuBarSearch.actions) ?? [] }
                ShortcutHintButton(title: String(localized: "Click Item", bundle: .floe, comment: "A button that clicks the selected menu bar item.")) { search.open(extra) } hint: {
                    KeyCapView(systemImage: "return")
                }
            }
        }
        .buttonStyle(SearchPanelButtonStyle())
        .padding(ThawSpacing.compact)
        .padding(.horizontal, ThawSpacing.tight)
    }
}
