//
//  ExtensionViews.swift
//  Project: Floe
//
//  Copyright (Floe) © 2026 René Jiménez
//  Licensed under the GNU AGPLv3

import AppKit
import SwiftUI
import ThawUI

// MARK: Extension command

struct ExtensionView: View {
    @ObservedObject var model: LauncherModel
    @ObservedObject var session: ExtensionSession

    var body: some View {
        let view = session.view
        let actions = session.actions
        ZStack {
            VStack(spacing: 0) {
                if view?.type == "Form" {
                    PanelHeader(
                        title: view?.string("navigationTitle") ?? session.command.title,
                        icon: session.command.icon,
                        assetsPath: session.command.assetsPath,
                        isLoading: view?.bool("isLoading") ?? false
                    )
                } else {
                    SearchBar(
                        placeholder: view?.string("searchBarPlaceholder") ?? (session.isList ? "Search…" : session.command.title),
                        text: $session.searchText,
                        focusToken: model.focusToken,
                        isLoading: view?.bool("isLoading") ?? (view == nil)
                    ) {
                        if let dropdown = view?.slot("searchBarAccessory") {
                            DropdownView(node: dropdown, session: session)
                        }
                    }
                }
                Group {
                    if let view {
                        switch view.type {
                        case "List", "Grid": ListBody(session: session, view: view)
                        case "Detail": DetailBody(node: view, assetsPath: session.command.assetsPath)
                        case "Form": FormBody(session: session, focusToken: model.focusToken)
                        default: Placeholder(title: "\(view.type) isn't supported yet", detail: "Floe renders List, Grid, Detail and Form.", systemImage: "hammer")
                        }
                    } else {
                        Color.clear
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .overlay(alignment: .bottomTrailing) {
                    if session.actionMenuOpen {
                        ActionMenu(session: session)
                    }
                }
                .thawAnimation(ThawMotion.quick, value: session.actionMenuOpen)
                Footer(primary: actions.first?.string("title"), primaryKey: view?.type == "Form" ? "⌘↵" : "↵", hasActions: actions.count > 1) {
                    if let toast = session.toast {
                        ToastView(session: session, toast: toast)
                    } else {
                        IconView(value: session.command.icon ?? "icon:Terminal", assetsPath: session.command.assetsPath, size: 16)
                        Text(view?.string("navigationTitle") ?? session.command.title).foregroundStyle(.secondary).lineLimit(1)
                    }
                }
            }
            if let alert = session.alert {
                ConfirmAlertOverlay(session: session, alert: alert)
            }
        }
    }
}

struct Placeholder: View {
    let title: String
    var detail: String?
    var systemImage = "magnifyingglass"
    var body: some View {
        ThawEmptyState(systemImage: systemImage, title: LocalizedStringKey(title), caption: detail.map { LocalizedStringKey($0) })
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct ToastView: View {
    @ObservedObject var session: ExtensionSession
    let toast: ToastState
    var body: some View {
        HStack(spacing: 7) {
            if toast.style == "animated" {
                ProgressView().controlSize(.small)
            } else {
                Circle().fill(toast.style == "failure" ? Color.red : Color.green).frame(width: 8, height: 8)
            }
            Text(toast.title).fontWeight(.medium).lineLimit(1)
            if let message = toast.message {
                Text(message).foregroundStyle(.secondary).lineLimit(1)
            }
            if let primary = toast.primaryTitle {
                Button(primary) { session.runToastAction(primary: true) }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
                KeyCap("⌘↵")
            }
            if let secondary = toast.secondaryTitle {
                Button(secondary) { session.runToastAction(primary: false) }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

/// An in-panel `confirmAlert` dialog: a scrim over the content with a centered card.
struct ConfirmAlertOverlay: View {
    @ObservedObject var session: ExtensionSession
    let alert: AlertState
    @FocusState private var confirmFocused: Bool

    var body: some View {
        ZStack {
            Color.black.opacity(0.15)
            VStack(alignment: .leading, spacing: ThawSpacing.row) {
                Text(alert.title)
                    .font(ThawType.heading)
                if let message = alert.message, !message.isEmpty {
                    Text(message)
                        .font(ThawType.body)
                        .foregroundStyle(.secondary)
                }
                HStack(spacing: ThawSpacing.base) {
                    Spacer(minLength: 0)
                    Button(alert.dismissTitle) { session.resolveAlert(false) }
                        .keyboardShortcut(.cancelAction)
                    if alert.isDestructive {
                        Button(alert.primaryTitle) { session.resolveAlert(true) }
                            .foregroundStyle(.red)
                            .keyboardShortcut(.defaultAction)
                            .focused($confirmFocused)
                    } else {
                        Button(alert.primaryTitle) { session.resolveAlert(true) }
                            .buttonStyle(.borderedProminent)
                            .keyboardShortcut(.defaultAction)
                            .focused($confirmFocused)
                    }
                }
                .padding(.top, ThawSpacing.tight)
            }
            .padding(ThawSpacing.gutter)
            .frame(width: 340)
            .background(.background, in: RoundedRectangle(cornerRadius: ThawRadius.card, style: .continuous))
            .onAppear { confirmFocused = true }
        }
    }
}

struct DropdownView: View {
    let node: Node
    let session: ExtensionSession

    var body: some View {
        let items = node.descendants(ofType: "Dropdown.Item")
        let current = items.first { $0.props["value"] as? String == node.props["value"] as? String }
        Menu {
            ForEach(items) { item in
                Button(item.string("title") ?? "") { session.event(node, "onChange", [item.props["value"] as? String ?? ""]) }
            }
        } label: {
            Text(current?.string("title") ?? node.string("placeholder") ?? "Select")
        }
        .menuStyle(.button)
        .fixedSize()
    }
}

struct ActionMenu: View {
    @ObservedObject var session: ExtensionSession

    var body: some View {
        let entries = session.menuEntries
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: ThawSpacing.compact) {
                if let submenu = session.actionPath.last {
                    Image(systemName: "chevron.left").font(ThawType.caption).foregroundStyle(.secondary)
                    Text(submenu.string("title") ?? "Submenu").fontWeight(.medium)
                }
                Text(session.actionQuery.isEmpty ? "Search actions…" : session.actionQuery)
                    .foregroundStyle(session.actionQuery.isEmpty ? .tertiary : .primary)
                Spacer()
            }
            .padding(.horizontal, ThawSpacing.row)
            .frame(height: 30)
            Divider().padding(.bottom, ThawSpacing.tight)
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(Array(entries.enumerated()), id: \.element.id) { index, entry in
                        if let section = entry.section, !section.isEmpty, index == 0 || entries[index - 1].section != section {
                            SectionTitle(title: section, isFirst: index == 0)
                        }
                        row(entry, selected: index == session.actionSelection)
                            .onTapGesture { session.activateMenuEntry(at: index) }
                    }
                    if entries.isEmpty {
                        Text("No matching actions").foregroundStyle(.secondary).padding(ThawSpacing.row)
                    }
                }
            }
            .frame(maxHeight: 300)
            .fixedSize(horizontal: false, vertical: true)
        }
        .font(ThawType.body)
        .padding(ThawSpacing.compact)
        .frame(width: 320)
        .thawGlass(.panel, in: RoundedRectangle(cornerRadius: ThawRadius.card, style: .continuous))
        .padding(ThawSpacing.row)
    }

    private func row(_ entry: MenuEntry, selected: Bool) -> some View {
        let action = entry.node
        return HStack(spacing: 9) {
            IconView(value: action.props["icon"], assetsPath: session.command.assetsPath, size: 15)
            Text(action.string("title") ?? "Action")
                .foregroundStyle(action.props["style"] as? String == "destructive" ? Color.red : Color.primary)
                .lineLimit(1)
            Spacer()
            if let label = Shortcuts.label(action.props["shortcut"]) {
                KeyCap(label)
            }
            if entry.isSubmenu {
                Image(systemName: "chevron.right").font(ThawType.caption).foregroundStyle(.secondary)
            }
        }
        .modifier(RowBackground(selected: selected))
    }
}
