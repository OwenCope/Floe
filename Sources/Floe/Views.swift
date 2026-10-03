//
//  Views.swift
//  Project: Floe
//
//  Copyright (Floe) © 2026 René Jiménez
//  Licensed under the GNU GPLv3

import AppKit
import SwiftUI
import ThawUI

struct LauncherView: View {
    @ObservedObject var model: LauncherModel
    @ObservedObject var settings = AppSettings.shared
    @Environment(\.colorScheme) private var colorScheme

    /// Clear space between the glass and the window's edge. The window casts no shadow of its own,
    /// because AppKit outlines the window's rectangle and that shows as square corners behind the
    /// rounded glass; the margin leaves the glass room to draw its own depth.
    static let margin: CGFloat = 40

    static func contentSize(menuBarSearch: Bool) -> NSSize {
        menuBarSearch ? NSSize(width: 600, height: 400) : NSSize(width: 750, height: 474)
    }

    /// The window is the content plus the margin on every side.
    static func windowSize(menuBarSearch: Bool) -> NSSize {
        let size = contentSize(menuBarSearch: menuBarSearch)
        return NSSize(width: size.width + margin * 2, height: size.height + margin * 2)
    }

    var body: some View {
        GlassEffectContainer {
            if let setup = model.setup {
                SetupView(model: model, request: setup)
            } else if let session = model.session, session.command.mode == "view" {
                SessionContainer(model: model, session: session)
            } else if model.isSearchingMenuBar {
                MenuBarSearchView(model: model)
            } else {
                RootView(model: model)
            }
        }
        .frame(
            width: Self.contentSize(menuBarSearch: model.isSearchingMenuBar).width,
            height: Self.contentSize(menuBarSearch: model.isSearchingMenuBar).height
        )
        .modifier(LauncherPanelAppearance(
            tint: settings.launcherTint(for: colorScheme),
            border: settings.launcherShowsBorder ? settings.launcherBorder : nil,
            hasShadow: settings.launcherShowsShadow
        ))
        .padding(Self.margin)
    }
}

/// Thaw's menu-bar appearance, applied to the launcher's glass: a tint layered
/// between the glass and the content at the configured strength, an optional
/// border, and a drop shadow that follows the rounded shape — the window's own
/// shadow is a square, because the window is larger than the launcher by
/// `margin`. Internal so the Appearance pane can preview with the same layering.
struct LauncherPanelAppearance: ViewModifier {
    let tint: LauncherTint
    let border: LauncherBorder?
    let hasShadow: Bool

    private var shape: RoundedRectangle {
        RoundedRectangle(cornerRadius: ThawRadius.panel, style: .continuous)
    }

    func body(content: Content) -> some View {
        // The tint is the content's background, so the order is glass, tint,
        // content: a colour wash must never sit on top of the launcher's text.
        let tinted = content.background {
            if let style = tint.backgroundStyle {
                shape.fill(style)
            }
        }
        .thawGlass(.panel, in: shape)
        let bordered = Group {
            if let border {
                tinted.overlay(shape.strokeBorder(border.color.color, lineWidth: border.width))
            } else {
                tinted
            }
        }
        return Group {
            if hasShadow {
                bordered.shadow(color: .black.opacity(0.35), radius: 14, y: 6)
            } else {
                bordered
            }
        }
    }
}

// MARK: Shared chrome

struct SearchBar<Accessory: View>: View {
    let placeholder: String
    @Binding var text: String
    let focusToken: Int
    var isLoading = false
    @ViewBuilder var accessory: Accessory

    var body: some View {
        SearchQueryField(prompt: placeholder, text: $text, focusToken: focusToken, isLoading: isLoading) { accessory }
    }
}

struct RowBackground: ViewModifier {
    let selected: Bool

    func body(content: Content) -> some View {
        content
            .padding(.horizontal, ThawSpacing.row)
            .frame(height: 38)
            .modifier(SearchRowBackground(selected: selected))
    }
}

struct Footer<Leading: View>: View {
    var primary: String?
    var primaryKey = "↵"
    var hasActions = false
    @ViewBuilder var leading: Leading

    var body: some View {
        VStack(spacing: 0) {
            Divider()
            HStack(spacing: 10) {
                leading
                Spacer()
                if let primary {
                    Text(primary).fontWeight(.medium)
                    KeyCap(primaryKey)
                }
                if hasActions {
                    Divider().frame(height: 14)
                    Text("Actions").foregroundStyle(.secondary)
                    KeyCap("⌘K")
                }
            }
            .font(ThawType.footnote)
            .padding(.horizontal, ThawSpacing.gutter)
            .frame(height: 38)
        }
    }
}

struct KeyCap: View {
    let label: String
    init(_ label: String) {
        self.label = label
    }

    var body: some View {
        KeyCapView(text: label, font: ThawType.caption.weight(.medium))
    }
}

// MARK: Root search

struct RootView: View {
    @ObservedObject var model: LauncherModel

    var body: some View {
        let results = model.results
        VStack(spacing: 0) {
            SearchBar(placeholder: "Search apps and commands…", text: $model.query, focusToken: model.focusToken, isLoading: model.isLoadingCatalog) { EmptyView() }
            if results.isEmpty, !model.isLoadingCatalog {
                ThawEmptyState(
                    systemImage: "magnifyingglass",
                    title: "Nothing matches",
                    caption: "Try part of an app's or a command's name, or an alias."
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 0) {
                            ForEach(Array(results.enumerated()), id: \.element.id) { index, result in
                                if let section = result.section, index == 0 || results[index - 1].section != section {
                                    SectionTitle(title: section, isFirst: index == 0)
                                }
                                RootRow(model: model, item: result.item, selected: index == model.selection)
                                    .id(result.id)
                                    .onTapGesture { model.activate(result.item) }
                            }
                        }
                    }
                    .contentMargins(.all, ThawSpacing.base, for: .scrollContent)
                    .onChange(of: model.selection) {
                        if results.indices.contains(model.selection) {
                            proxy.scrollTo(results[model.selection].id)
                        }
                    }
                }
            }
            bottomBar(results: results)
        }
    }

    /// The Thaw-style bottom bar: settings on the left, the selected row's
    /// actions with their key equivalents on the right.
    private func bottomBar(results: [RootResult]) -> some View {
        HStack(spacing: ThawSpacing.row) {
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

            Spacer(minLength: 0)

            if let selected = results.indices.contains(model.selection) ? results[model.selection].item : nil {
                ShortcutHintButton(title: "Favorite") { model.toggleFavorite(selected) } hint: {
                    KeyCapView(text: "⌘")
                    Text(verbatim: "+")
                    KeyCapView(text: "⇧")
                    KeyCapView(text: "F")
                }
                ShortcutHintButton(title: "Open") { model.activate(selected) } hint: {
                    KeyCapView(systemImage: "return")
                }
            }
        }
        .padding(.horizontal, ThawSpacing.inset)
        .padding(.vertical, ThawSpacing.row)
    }
}

struct SectionTitle: View {
    let title: String
    var isFirst = false

    var body: some View {
        SearchSectionHeader(title: title)
    }
}

struct RootRow: View {
    let model: LauncherModel
    let item: RootItem
    let selected: Bool

    var body: some View {
        PaletteRow(title: item.title, subtitle: nil, selected: selected) {
            RootIcon(item: item)
        } trailing: {
            HStack(spacing: ThawSpacing.compact) {
                // Raycast-style: the kind sits on the row's right edge instead
                // of a second line, so the name uses the full width.
                Text(item.kind)
                    .font(ThawType.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                if model.isFavorite(item) {
                    Image(systemName: "star.fill").font(ThawType.caption).foregroundStyle(.yellow)
                        .accessibilityLabel("Favorite")
                }
                if let alias = model.alias(for: item) {
                    KeyCap(alias)
                }
            }
        }
    }
}

struct RootIcon: View {
    let item: RootItem
    var body: some View {
        switch item {
        case let .app(app):
            AppIconView(path: app.url.path, size: 24)
        case let .command(command):
            IconView(value: command.icon ?? "icon:Terminal", assetsPath: command.assetsPath, size: 24)
        case .menuBarSearch:
            IconView(value: "icon:MenubarRectangle", assetsPath: "", size: 24)
        case .settings:
            IconView(value: "icon:Gear", assetsPath: "", size: 24)
        }
    }
}

// MARK: Extension command

struct ExtensionView: View {
    @ObservedObject var model: LauncherModel
    @ObservedObject var session: ExtensionSession

    var body: some View {
        let view = session.view
        let actions = session.actions
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
                    ToastView(toast: toast)
                } else {
                    IconView(value: session.command.icon ?? "icon:Terminal", assetsPath: session.command.assetsPath, size: 16)
                    Text(view?.string("navigationTitle") ?? session.command.title).foregroundStyle(.secondary).lineLimit(1)
                }
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

// MARK: List

struct ListBody: View {
    @ObservedObject var session: ExtensionSession
    let view: Node

    var body: some View {
        let rows = session.rows
        let selected = session.selectedRow
        if rows.isEmpty {
            let empty = view.content.first { $0.type == "EmptyView" }
            if view.bool("isLoading") {
                Color.clear
            } else {
                Placeholder(title: empty?.string("title") ?? "No Results", detail: empty?.string("description"))
            }
        } else {
            HStack(spacing: 0) {
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 0) {
                            ForEach(Array(rows.enumerated()), id: \.element.id) { index, row in
                                if let title = row.sectionTitle, index == 0 || rows[index - 1].sectionTitle != title {
                                    Text(title)
                                        .font(ThawType.caption.weight(.semibold))
                                        .foregroundStyle(.secondary)
                                        .padding(.horizontal, 10)
                                        .padding(.top, index == 0 ? 2 : 10)
                                        .padding(.bottom, 4)
                                }
                                ListRow(
                                    node: row.node,
                                    assetsPath: session.command.assetsPath,
                                    selected: row.id == selected?.id,
                                    compact: view.bool("isShowingDetail")
                                )
                                .id(row.id)
                                .onTapGesture(count: 2) {
                                    session.selection = index
                                    if let action = session.actions.first {
                                        session.run(action)
                                    }
                                }
                                .onTapGesture { session.selection = index }
                            }
                        }
                        .padding(8)
                    }
                    .onChange(of: selected?.id) {
                        if let id = selected?.id {
                            proxy.scrollTo(id)
                        }
                    }
                }
                if view.bool("isShowingDetail"), let detail = selected?.node.slot("detail") {
                    Divider()
                    DetailBody(node: detail, assetsPath: session.command.assetsPath).frame(width: 430)
                }
            }
        }
    }
}

struct ListRow: View {
    let node: Node
    let assetsPath: String
    let selected: Bool
    let compact: Bool

    var body: some View {
        HStack(spacing: 10) {
            if let icon = node.props["icon"] ?? node.props["content"] {
                IconView(value: icon, assetsPath: assetsPath, size: 18)
            }
            Text(node.string("title") ?? "").lineLimit(1)
            if !compact, let subtitle = node.string("subtitle") {
                Text(subtitle).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer(minLength: 8)
            if !compact {
                ForEach(Array((node.props["accessories"] as? [[String: Any]] ?? []).enumerated()), id: \.offset) { _, accessory in
                    AccessoryView(accessory: accessory, assetsPath: assetsPath)
                }
            }
        }
        .font(ThawType.body)
        .modifier(RowBackground(selected: selected))
    }
}

struct AccessoryView: View {
    let accessory: [String: Any]
    let assetsPath: String

    var body: some View {
        HStack(spacing: 4) {
            if let icon = accessory["icon"] {
                IconView(value: icon, assetsPath: assetsPath, size: 13)
            }
            if let text = PropFormat.text(accessory["text"]) {
                Text(text).foregroundStyle(Palette.color(PropFormat.color(accessory["text"])) ?? .secondary)
            }
            if let tag = PropFormat.text(accessory["tag"]) {
                let color = Palette.color(PropFormat.color(accessory["tag"])) ?? .secondary
                Text(tag)
                    .foregroundStyle(color)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(color.opacity(0.15), in: .rect(cornerRadius: 5))
            }
            if let date = PropFormat.date(accessory["date"]) {
                Text(date, format: .relative(presentation: .numeric, unitsStyle: .narrow)).foregroundStyle(.secondary)
            }
        }
        .font(.system(size: 12))
        .lineLimit(1)
    }
}

// MARK: Detail

struct DetailBody: View {
    let node: Node
    let assetsPath: String

    var body: some View {
        HStack(spacing: 0) {
            ScrollView {
                MarkdownView(text: node.string("markdown") ?? "")
                    .padding(18)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            if let metadata = node.slot("metadata") {
                Divider()
                ScrollView {
                    VStack(alignment: .leading, spacing: 10) {
                        ForEach(metadata.content) { MetadataRow(node: $0, assetsPath: assetsPath) }
                    }
                    .padding(14)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(width: 210)
            }
        }
    }
}

struct MetadataRow: View {
    let node: Node
    let assetsPath: String

    var body: some View {
        if node.type == "Metadata.Separator" {
            Divider()
        } else {
            VStack(alignment: .leading, spacing: 3) {
                Text(node.string("title") ?? "").font(.system(size: 11)).foregroundStyle(.secondary)
                switch node.type {
                case "Metadata.Link":
                    if let target = node.string("target"), let url = URL(string: target) {
                        Link(node.string("text") ?? target, destination: url)
                    }
                case "Metadata.TagList":
                    HStack(spacing: 4) {
                        ForEach(node.content) { tag in
                            let color = Palette.color(tag.props["color"]) ?? .secondary
                            Text(tag.string("text") ?? "")
                                .foregroundStyle(color)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(color.opacity(0.15), in: .rect(cornerRadius: 5))
                        }
                    }
                default:
                    HStack(spacing: 5) {
                        if let icon = node.props["icon"] {
                            IconView(value: icon, assetsPath: assetsPath, size: 13)
                        }
                        Text(PropFormat.text(node.props["text"]) ?? "").textSelection(.enabled)
                    }
                }
            }
            .font(.system(size: 12))
        }
    }
}

/// Draws the blocks MarkdownParser finds, with inline styling from AttributedString.
struct MarkdownView: View {
    let text: String

    private func inline(_ string: String) -> AttributedString {
        (try? AttributedString(markdown: string, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace))) ?? AttributedString(string)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ForEach(Array(MarkdownParser.blocks(text).enumerated()), id: \.offset) { _, block in
                switch block {
                case let .heading(level, text):
                    Text(inline(text)).font(.system(size: [22, 18, 15][min(level, 3) - 1], weight: .semibold))
                case let .paragraph(text):
                    Text(inline(text))
                case let .bullet(text):
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text("•").foregroundStyle(.secondary)
                        Text(inline(text))
                    }
                case let .code(text):
                    Text(text)
                        .font(.system(size: 12, design: .monospaced))
                        .padding(10)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color.primary.opacity(0.07), in: .rect(cornerRadius: 8))
                case let .image(url):
                    AsyncImage(url: url) { image in
                        image.resizable().scaledToFit()
                    } placeholder: {
                        Color.primary.opacity(0.05)
                    }
                    .frame(maxHeight: 260)
                case .rule:
                    Divider()
                }
            }
        }
        .font(.system(size: 13))
        .textSelection(.enabled)
    }
}

// MARK: Icons and colors

enum Palette {
    static func color(_ value: Any?) -> Color? {
        guard let string = value as? String else { return nil }
        if string.hasPrefix("#"), let hex = UInt32(string.dropFirst().prefix(6), radix: 16) {
            return Color(red: Double(hex >> 16 & 0xFF) / 255, green: Double(hex >> 8 & 0xFF) / 255, blue: Double(hex & 0xFF) / 255)
        }
        switch string.replacingOccurrences(of: "color:", with: "") {
        case "Red": return .red
        case "Orange": return .orange
        case "Yellow": return .yellow
        case "Green": return .green
        case "Blue": return .blue
        case "Purple": return .purple
        case "Magenta": return .pink
        case "PrimaryText": return .primary
        case "SecondaryText": return .secondary
        default: return nil
        }
    }
}

struct IconView: View {
    let value: Any?
    let assetsPath: String
    var size: CGFloat = 18

    private enum Resolved {
        case symbol(String), image(NSImage), remote(URL), text(String), none
    }

    /// Icons render at 18-32 points, so decoded bitmaps are kept at a 3x pixel target and the cache
    /// holds a bounded byte budget: a 1024 px asset then costs kilobytes instead of ~4 megabytes.
    private static let cache: NSCache<NSString, NSImage> = {
        let cache = NSCache<NSString, NSImage>()
        cache.totalCostLimit = 32 * 1024 * 1024
        return cache
    }()

    private static let symbols: [String: String] = [
        "Globe": "globe", "Star": "star.fill", "Clipboard": "doc.on.clipboard", "Link": "link", "Trash": "trash",
        "Finder": "folder", "Folder": "folder", "Document": "doc", "Calendar": "calendar", "Clock": "clock",
        "Person": "person", "Gear": "gearshape", "MagnifyingGlass": "magnifyingglass", "Terminal": "terminal",
        "Sidebar": "sidebar.right", "ArrowRight": "arrow.right", "Eye": "eye", "Bubble": "bubble.left",
        "Checkmark": "checkmark", "XMarkCircle": "xmark.circle", "Plus": "plus", "Pencil": "pencil",
        "Download": "arrow.down.circle", "Upload": "arrow.up.circle", "Bookmark": "bookmark", "Heart": "heart",
        "Info": "info.circle", "Warning": "exclamationmark.triangle", "Code": "chevron.left.forwardslash.chevron.right",
        "Window": "macwindow", "AppWindow": "macwindow", "Image": "photo", "Message": "message", "Envelope": "envelope",
        "ArrowClockwise": "arrow.clockwise", "Circle": "circle", "Dot": "circle.fill", "Lock": "lock", "Key": "key",
        "Tag": "tag", "Text": "text.alignleft", "List": "list.bullet", "Play": "play.fill", "Pause": "pause.fill",
    ]

    @Environment(\.colorScheme) private var colorScheme

    private func resolve(_ value: Any?) -> Resolved {
        let pixels = Self.pixelSize(for: size)
        if let dict = value as? [String: Any] {
            if let path = dict["fileIcon"] as? String {
                return cachedImage(key: "fileIcon:\(path)", pixels: pixels) { NSWorkspace.shared.icon(forFile: path) }.map(Resolved.image) ?? .none
            }
            // Raycast's { source: { light, dark } } picks per appearance.
            if let source = dict["source"] as? [String: Any] {
                return resolve(colorScheme == .dark ? source["dark"] ?? source["light"] : source["light"] ?? source["dark"])
            }
            return resolve(dict["source"] ?? dict["value"])
        }
        guard let string = value as? String, !string.isEmpty else { return .none }
        if string.hasPrefix("icon:") {
            let name = String(string.dropFirst(5))
            // Raycast names are CamelCase (ArrowUpCircle); most map onto SF Symbols as arrow.up.circle.
            let dotted = name.replacing(#/([a-z0-9])([A-Z])/#) { "\($0.1).\($0.2)" }.lowercased()
            let candidates = [Self.symbols[name], dotted, name.lowercased()].compactMap(\.self)
            let symbol = candidates.first { NSImage(systemSymbolName: $0, accessibilityDescription: nil) != nil }
            return .symbol(symbol ?? "square.dashed")
        }
        if string.hasPrefix("http"), let url = URL(string: string) {
            return .remote(url)
        }
        if string.hasPrefix("data:"), let comma = string.firstIndex(of: ",") {
            let image = cachedImage(key: string, pixels: pixels) {
                let payload = String(string[string.index(after: comma)...])
                let data = string[..<comma].contains(";base64")
                    ? Data(base64Encoded: payload)
                    : (payload.removingPercentEncoding ?? payload).data(using: .utf8)
                return data.flatMap(NSImage.init(data:))
            }
            return image.map(Resolved.image) ?? .none
        }
        // Asset names repeat across extensions (most ship an "icon.png"), so the cache key is the full path.
        if let path = assetPath(string), let image = cachedImage(key: path, pixels: pixels, load: { NSImage(contentsOfFile: path) }) {
            return .image(image)
        }
        return string.count <= 2 ? .text(string) : .none
    }

    /// An absolute path, or a file in the extension's assets; prefers Raycast's `name@dark.ext` variant in dark mode.
    private func assetPath(_ name: String) -> String? {
        let path = (name as NSString).isAbsolutePath ? name : URL(fileURLWithPath: assetsPath).appendingPathComponent(name).path
        if colorScheme == .dark {
            let url = URL(fileURLWithPath: path)
            let dark = url.deletingPathExtension().path + "@dark." + url.pathExtension
            if FileManager.default.fileExists(atPath: dark) {
                return dark
            }
        }
        return FileManager.default.fileExists(atPath: path) ? path : nil
    }

    private func cachedImage(key: String, pixels: Int, load: () -> NSImage?) -> NSImage? {
        if let cached = Self.cache.object(forKey: key as NSString) {
            return cached
        }
        guard let loaded = load() else { return nil }
        let image = Self.downsampled(loaded, to: pixels)
        let bytes = image.representations.reduce(0) { $0 + $1.pixelsWide * $1.pixelsHigh * 4 }
        Self.cache.setObject(image, forKey: key as NSString, cost: bytes)
        return image
    }

    /// Draws the image's bitmap into at most `pixels` on its longer side; smaller images pass through.
    private static func downsampled(_ image: NSImage, to pixels: Int) -> NSImage {
        guard let source = image.cgImage(forProposedRect: nil, context: nil, hints: nil),
              max(source.width, source.height) > pixels
        else { return image }
        let scale = CGFloat(pixels) / CGFloat(max(source.width, source.height))
        let width = max(1, Int((CGFloat(source.width) * scale).rounded()))
        let height = max(1, Int((CGFloat(source.height) * scale).rounded()))
        let space = CGColorSpace(name: CGColorSpace.sRGB) ?? source.colorSpace ?? CGColorSpaceCreateDeviceRGB()
        guard let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                                      space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { return image }
        context.interpolationQuality = .high
        context.draw(source, in: CGRect(x: 0, y: 0, width: width, height: height))
        guard let drawn = context.makeImage() else { return image }
        let result = NSImage(size: NSSize(width: width, height: height))
        result.addRepresentation(NSBitmapImageRep(cgImage: drawn))
        return result
    }

    static func pixelSize(for points: CGFloat) -> Int {
        Int((points * 3).rounded())
    }

    /// tintColor and mask can sit at any level: { value: { source, tintColor } } is common.
    private static func attribute(_ key: String, in value: Any?) -> Any? {
        guard let dict = value as? [String: Any] else { return nil }
        return dict[key] ?? attribute(key, in: dict["value"]) ?? attribute(key, in: dict["source"])
    }

    var body: some View {
        let tint = Palette.color(Self.attribute("tintColor", in: value))
        let isCircle = Self.attribute("mask", in: value) as? String == "circle"
        // Every icon sits in the same glass squircle, Raycast-style: bare
        // symbols next to squircled asset icons read as two different things.
        let squircle = self.squircle(isCircle)
        return Group {
            switch resolve(value) {
            case let .symbol(name):
                Image(systemName: name)
                    .font(.system(size: size * 0.55))
                    .foregroundStyle(tint ?? .secondary)
            case let .image(image):
                // A tint makes the image a template, as Raycast does for monochrome assets.
                if let tint {
                    Image(nsImage: image)
                        .resizable().scaledToFit()
                        .foregroundStyle(tint)
                } else {
                    Image(nsImage: image)
                        .resizable().scaledToFill()
                }
            case let .remote(url):
                AsyncImage(url: url) { $0.resizable().scaledToFill() } placeholder: { Color.clear }
            case let .text(text):
                Text(text).font(.system(size: size * 0.55))
            case .none:
                Color.clear
            }
        }
        .frame(width: size, height: size)
        .background(.quinary, in: squircle)
        .clipShape(squircle)
    }

    private func squircle(_ isCircle: Bool) -> RoundedRectangle {
        isCircle
            ? RoundedRectangle(cornerRadius: size / 2, style: .continuous)
            : RoundedRectangle(cornerRadius: size * 0.22, style: .continuous)
    }
}
