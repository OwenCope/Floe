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
    @ObservedObject var model: LauncherModel
    @ObservedObject var settings: AppSettings = .shared

    var body: some View {
        GlassEffectContainer {
            content
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .safeAreaBar(edge: .top, spacing: 0) { queryField }
                .safeAreaBar(edge: .bottom, spacing: 0) { bottomBar }
        }
        .scrollEdgeEffectStyle(.automatic, for: .vertical)
    }

    // MARK: Query field

    private var queryField: some View {
        SearchQueryField(
            prompt: "Search menu bar items…",
            text: $model.menuBarQuery,
            focusToken: model.focusToken,
            isLoading: model.isScanningMenuBar
        ) { EmptyView() }
    }

    // MARK: Content

    /// Either the matching rows or the state that explains why there are none.
    @ViewBuilder
    private var content: some View {
        let hasQuery = !model.menuBarQuery.trimmingCharacters(in: .whitespaces).isEmpty
        if !model.menuBarAccessGranted {
            // Distinct from "nothing matched": without Accessibility the walk returns an empty list.
            ThawEmptyState(
                systemImage: "hand.raised",
                title: "Accessibility is off",
                caption: "Floe needs Accessibility to list your menu bar items.",
                actionTitle: "Grant Access",
                action: { model.requestMenuBarAccess() }
            )
        } else if model.isScanningMenuBar, model.menuBarResults.isEmpty {
            ThawEmptyState(systemImage: "menubar.rectangle", title: "Reading your menu bar…", isLoading: true)
        } else if hasQuery, model.menuBarResults.isEmpty {
            ThawEmptyState(
                systemImage: "magnifyingglass",
                title: "No items match",
                caption: "Try part of the item's name or the app that owns it."
            )
        } else if model.menuBarResults.isEmpty {
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
        let results = model.menuBarResults
        return ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(Array(results.enumerated()), id: \.element.id) { index, result in
                        if let section = result.section, index == 0 || results[index - 1].section != section {
                            SearchSectionHeader(title: section)
                        }
                        InspectorItemRow(
                            extra: result.extra,
                            name: model.displayName(for: result.extra),
                            renameDraft: model.renamingMenuBarItem == result.extra.id ? $model.menuBarRenameDraft : nil
                        )
                        .modifier(SearchRowBackground(selected: index == model.menuBarSelection))
                        .id(result.id)
                        .onTapGesture(count: 2) { model.openMenuBarExtra(result.extra) }
                        .onTapGesture { model.menuBarSelection = index }
                    }
                }
            }
            .scrollIndicatorsFlash(onAppear: true)
            .contentMargins(.all, ThawSpacing.base, for: .scrollContent)
            .scrollContentBackground(.hidden)
            .onChange(of: model.menuBarSelection) {
                if results.indices.contains(model.menuBarSelection) {
                    proxy.scrollTo(results[model.menuBarSelection].id)
                }
            }
        }
    }

    // MARK: Bottom bar

    private var bottomBar: some View {
        HStack {
            Button {
                model.hidePanel()
                model.openSettings(nil)
            } label: {
                Image(systemName: "gearshape")
                    .resizable()
                    .scaledToFit()
                    .foregroundStyle(.secondary)
                    .padding(ThawSpacing.hairline)
            }
            .help("Open Settings")
            .accessibilityLabel("Open Settings")

            Toggle("Remember last search", isOn: $settings.rememberMenuBarQuery)
                .toggleStyle(.switch)
                .controlSize(.mini)

            Spacer()

            if model.renamingMenuBarItem != nil {
                ShortcutHintButton(title: "Cancel") { model.cancelRename() } hint: {
                    KeyCapView(text: "⎋", font: ThawType.detail)
                }
                ShortcutHintButton(title: "Rename") { model.commitRename() } hint: {
                    KeyCapView(systemImage: "return")
                }
            } else if let extra = model.selectedMenuBarExtra {
                ShortcutHintButton(title: "Edit Name") { model.beginRenamingSelection() } hint: {
                    KeyCapView(text: "⌘")
                    Text(verbatim: "+")
                    KeyCapView(text: "E")
                }
                ShortcutHintButton(title: "Actions…") { model.showActions() } hint: {
                    KeyCapView(text: "⌘")
                    Text(verbatim: "+")
                    KeyCapView(text: "K")
                }
                // The actions menu hangs off this button, so it has to be reachable as an AppKit view.
                .background { ActionsAnchor(model: model) { $0.selectedMenuBarExtra.map($0.menuBarActions) ?? [] } }
                ShortcutHintButton(title: "Click Item") { model.openMenuBarExtra(extra) } hint: {
                    KeyCapView(systemImage: "return")
                }
            }
        }
        .buttonStyle(SearchPanelButtonStyle())
        .padding(ThawSpacing.compact)
        .padding(.horizontal, ThawSpacing.tight)
    }
}
