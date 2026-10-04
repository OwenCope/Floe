//
//  Views.swift
//  Project: Floe
//
//  Copyright (Floe) © 2026 René Jiménez
//  Licensed under the GNU AGPLv3

import AppKit
import QuickLook
import QuickLookThumbnailing
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

    var body: some View {
        let size = model.panelState.contentSize(in: settings.launcherLayout)
        GlassEffectContainer {
            if let setup = model.setup {
                SetupView(model: model, request: setup)
            } else if let session = model.session, session.command.mode == "view" {
                SessionContainer(model: model, session: session)
            } else if model.isSearchingMenuBar {
                MenuBarSearchView(model: model)
            } else if model.isShowingClipboardHistory {
                ClipboardHistoryView(model: model)
            } else if model.isSearchingFiles {
                FileSearchView(model: model, fileSearch: model.fileSearch)
            } else {
                RootView(model: model, isCollapsed: model.panelState.isCollapsed(in: settings.launcherLayout))
            }
        }
        .frame(width: size.width, height: size.height, alignment: .top)
        .modifier(LauncherPanelAppearance(
            glass: settings.launcherGlass,
            tint: settings.launcherTint(for: colorScheme),
            border: settings.launcherShowsBorder ? settings.launcherBorder : nil,
            hasShadow: settings.launcherShowsShadow
        ))
        .padding(Self.margin)
        // The window is resized a moment before or after the content: the search bar stays at the top meanwhile.
        .frame(maxHeight: .infinity, alignment: .top)
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
    var isCollapsed = false

    var body: some View {
        let results = model.results
        VStack(spacing: 0) {
            SearchBar(placeholder: "Search apps and commands…", text: $model.query, focusToken: model.focusToken, isLoading: model.isLoadingCatalog || model.isAwaitingResults) { EmptyView() }
            if isCollapsed {
                EmptyView()
            } else if results.isEmpty, !model.isLoadingCatalog, !model.isAwaitingResults {
                ThawEmptyState(
                    systemImage: "magnifyingglass",
                    title: LocalizedStringKey(model.activeScope?.scope.emptyTitle ?? "Nothing matches"),
                    caption: model.activeScope == nil ? "Try part of an app's or a command's name, or an alias." : nil
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
            if !isCollapsed {
                bottomBar(results: results)
            }
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
                if !selected.isScopeResult {
                    ShortcutHintButton(title: "Favorite") { model.toggleFavorite(selected) } hint: {
                        KeyCapView(text: "⌘")
                        Text(verbatim: "+")
                        KeyCapView(text: "⇧")
                        KeyCapView(text: "F")
                    }
                }
                ShortcutHintButton(title: "Actions…") { model.showActions() } hint: {
                    KeyCapView(text: "⌘")
                    Text(verbatim: "+")
                    KeyCapView(text: "K")
                }
                // The actions menu hangs off this button, so it has to be reachable as an AppKit view.
                .background { ActionsAnchor(model: model) { $0.selectedRootItem.map($0.rootActions) ?? [] } }
                ShortcutHintButton(title: model.primaryActionTitle(for: selected)) { model.activate(selected) } hint: {
                    KeyCapView(systemImage: "return")
                }
            }
        }
        .buttonStyle(SearchPanelButtonStyle())
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
        PaletteRow(title: item.title, subtitle: nil, selected: selected, matched: Fuzzy.match(model.query, item.title)?.matched ?? []) {
            RootIcon(item: item)
        } trailing: {
            HStack(spacing: ThawSpacing.compact) {
                // Raycast-style: the kind sits on the row's right edge instead
                // of a second line, so the name uses the full width.
                Text(item.rowLabel)
                    .font(ThawType.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                if case let .command(command) = item, model.isInMenuBar(command) {
                    Image(systemName: "checkmark").font(ThawType.caption).foregroundStyle(.secondary)
                        .accessibilityLabel("In the menu bar")
                }
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
        case let .script(script):
            IconView(value: script.icon ?? "icon:Terminal", assetsPath: "", size: 24)
        case .menuBarSearch:
            IconView(value: "icon:MenubarRectangle", assetsPath: "", size: 24)
        case .emojiSearch:
            Text("😀").font(.system(size: 20))
        case .clipboardHistory:
            IconView(value: "icon:Clipboard", assetsPath: "", size: 24)
        case .fileSearch, .searchFiles:
            IconView(value: "icon:Document", assetsPath: "", size: 24)
        case .settings:
            IconView(value: "icon:Gear", assetsPath: "", size: 24)
        case let .system(command):
            SymbolTile(symbol: command.symbol)
        case let .note(action, _):
            SymbolTile(symbol: action.symbol)
        case .thaw:
            // Thaw's own icon, so its rows read as that app's and not as one more system command.
            AppIconView(path: Thaw.applicationURL?.path ?? "", size: 24)
        case let .finderSelection(_, app):
            AppIconView(path: app.url.path, size: 24)
        case let .settingsPane(pane):
            SymbolTile(symbol: pane.symbol)
        case .snippet:
            SymbolTile(symbol: "text.quote", tint: .teal)
        case .event:
            SymbolTile(symbol: "calendar", tint: .red)
        case .calculator:
            IconView(value: "icon:PlusForwardslashMinus", assetsPath: "", size: 24)
        case let .emoji(entry):
            Text(entry.character).font(.system(size: 20))
        case let .quicklink(link, _, _, _):
            Image(systemName: link.symbol)
                .font(.system(size: 24 * 0.55))
                .foregroundStyle(.orange)
                .frame(width: 24, height: 24)
                .background(.quinary, in: RoundedRectangle(cornerRadius: 24 * 0.22, style: .continuous))
                .clipShape(RoundedRectangle(cornerRadius: 24 * 0.22, style: .continuous))
        case let .file(file):
            AppIconView(path: file.url.path, size: 24)
        case let .browserTab(row):
            // The browser's icon says where the tab is; a browser that refused shows the raised hand.
            if case .tab = row, let path = row.browser.applicationURL?.path {
                AppIconView(path: path, size: 24)
            } else {
                SymbolTile(symbol: "hand.raised")
            }
        case let .clipboardEntry(entry):
            SymbolTile(symbol: entry.kind.symbol)
        case let .menuBarItem(extra, _):
            if let owner = extra.ownerURL {
                AppIconView(path: owner.path, size: 24)
            } else {
                SymbolTile(symbol: "menubar.rectangle")
            }
        case .menuBarAccess:
            SymbolTile(symbol: "hand.raised")
        }
    }
}

/// A symbol on the rounded tile the built-in results use where an app has its icon.
struct SymbolTile: View {
    let symbol: String
    var tint = Color.primary

    var body: some View {
        Image(systemName: symbol)
            .font(.system(size: 13, weight: .medium))
            .foregroundStyle(tint)
            .frame(width: 24, height: 24)
            .background(.quinary, in: RoundedRectangle(cornerRadius: 24 * 0.22, style: .continuous))
    }
}

// MARK: Clipboard history

/// Saved copies: a searchable list with Pinned and day sections, and a preview
/// with metadata. Return pastes (Command-V when Accessibility allows it),
/// Escape goes back to the root search.
struct ClipboardHistoryView: View {
    @ObservedObject var model: LauncherModel
    @ObservedObject var history = ClipboardHistoryStore.shared
    @ObservedObject var settings = AppSettings.shared

    var body: some View {
        VStack(spacing: 0) {
            SearchBar(placeholder: "Search clipboard history…", text: $model.clipboardQuery, focusToken: model.focusToken) { EmptyView() }
            content
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            bottomBar()
        }
    }

    @ViewBuilder
    private var content: some View {
        if !settings.clipboardHistoryEnabled {
            ThawEmptyState(
                systemImage: "doc.on.clipboard",
                title: "Clipboard history is off",
                caption: "Turn on Save clipboard history in Settings to keep copies here."
            )
        } else {
            let entries = model.filteredClipboardEntries()
            if history.entries.isEmpty {
                ThawEmptyState(
                    systemImage: "doc.on.clipboard",
                    title: "Nothing copied yet",
                    caption: "Copies you make show up here."
                )
            } else if entries.isEmpty {
                ThawEmptyState(
                    systemImage: "magnifyingglass",
                    title: "No copies match",
                    caption: "Try part of the copied text, link or app name."
                )
            } else {
                HStack(spacing: 0) {
                    list(entries: entries)
                    Divider()
                    preview
                        .frame(width: 250)
                }
            }
        }
    }

    private func list(entries: [ClipboardEntry]) -> some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    let pinned = entries.filter(\.pinned)
                    let rest = entries.filter { !$0.pinned }
                    if !pinned.isEmpty {
                        SearchSectionHeader(title: "Pinned")
                        ForEach(pinned) { entry in row(entry, entries: entries) }
                    }
                    ForEach(dayGroups(rest), id: \.title) { group in
                        SearchSectionHeader(title: group.title)
                        ForEach(group.entries) { entry in row(entry, entries: entries) }
                    }
                }
            }
            .contentMargins(.all, ThawSpacing.base, for: .scrollContent)
            .onChange(of: model.clipboardSelection) {
                if entries.indices.contains(model.clipboardSelection) {
                    proxy.scrollTo(entries[model.clipboardSelection].id)
                }
            }
        }
    }

    private func row(_ entry: ClipboardEntry, entries: [ClipboardEntry]) -> some View {
        let index = entries.firstIndex(where: { $0.id == entry.id }) ?? 0
        let selected = index == model.clipboardSelection
        return HStack(spacing: 10) {
            Image(systemName: symbol(for: entry.kind))
                .foregroundStyle(.secondary)
                .frame(width: 18)
            VStack(alignment: .leading, spacing: 1) {
                Text(entry.title.isEmpty ? kindName(for: entry.kind) : entry.title)
                    .lineLimit(1)
                Text(rowSubtitle(for: entry))
                    .font(ThawType.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 8)
            if entry.pinned {
                Image(systemName: "pin.fill").font(ThawType.caption).foregroundStyle(.secondary)
                    .accessibilityLabel("Pinned")
            }
        }
        .font(ThawType.body)
        .modifier(RowBackground(selected: selected))
        .id(entry.id)
        .onTapGesture(count: 2) { model.pasteClipboardEntry(entry) }
        .onTapGesture { model.clipboardSelection = index }
    }

    @ViewBuilder
    private var preview: some View {
        if let entry = model.selectedClipboardEntry {
            ScrollView {
                VStack(alignment: .leading, spacing: 10) {
                    if entry.kind == .image, let image = history.image(for: entry) {
                        Image(nsImage: image)
                            .resizable()
                            .scaledToFit()
                            .frame(maxHeight: 160)
                    } else if let text = entry.text {
                        Text(text)
                            .textSelection(.enabled)
                            .font(.system(size: 12))
                    }
                    if entry.kind == .file {
                        ForEach(entry.filePaths ?? [], id: \.self) { path in
                            Text(URL(fileURLWithPath: path).lastPathComponent)
                                .font(.system(size: 12))
                                .lineLimit(1)
                        }
                    }
                    Divider()
                    metadata(title: "Kind", value: kindName(for: entry.kind))
                    metadata(title: "Copied", value: Self.dateFormatter.string(from: entry.date))
                    if let app = entry.sourceApp {
                        metadata(title: "App", value: app)
                    }
                    metadata(title: "Detail", value: detail(for: entry))
                }
                .padding(14)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        } else {
            ThawEmptyState(systemImage: "doc.on.clipboard", title: "Select a copy to preview it")
        }
    }

    private func metadata(title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title).font(.system(size: 11)).foregroundStyle(.secondary)
            Text(value).font(.system(size: 12)).textSelection(.enabled)
        }
    }

    private func bottomBar() -> some View {
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
            if let entry = model.selectedClipboardEntry {
                ShortcutHintButton(title: entry.pinned ? "Unpin" : "Pin") { model.toggleClipboardPin(entry) } hint: {
                    KeyCapView(systemImage: "pin")
                }
                ShortcutHintButton(title: "Delete") { model.deleteClipboardEntry(entry) } hint: {
                    KeyCapView(text: "⌫")
                }
                ShortcutHintButton(title: "Copy") { model.copyClipboardEntry(entry) } hint: {
                    KeyCapView(text: "⌘C")
                }
                ShortcutHintButton(title: "Paste") { model.pasteClipboardEntry(entry) } hint: {
                    KeyCapView(systemImage: "return")
                }
            }
        }
        .padding(.horizontal, ThawSpacing.inset)
        .padding(.vertical, ThawSpacing.row)
    }

    private func symbol(for kind: ClipboardEntry.Kind) -> String {
        switch kind {
        case .text: "doc.text"
        case .link: "link"
        case .image: "photo"
        case .file: "folder"
        }
    }

    private func kindName(for kind: ClipboardEntry.Kind) -> String {
        switch kind {
        case .text: "Text"
        case .link: "Link"
        case .image: "Image"
        case .file: "File"
        }
    }

    private func rowSubtitle(for entry: ClipboardEntry) -> String {
        var parts: [String] = [Self.timeFormatter.string(from: entry.date)]
        if let app = entry.sourceApp {
            parts.append(app)
        }
        if entry.kind == .link, let text = entry.text, let host = URL(string: text)?.host {
            parts.append(host)
        }
        return parts.joined(separator: " · ")
    }

    private func detail(for entry: ClipboardEntry) -> String {
        switch entry.kind {
        case .text, .link:
            let count = (entry.text ?? "").count
            return count == 1 ? "1 character" : "\(count) characters"
        case .file:
            let count = entry.filePaths?.count ?? 0
            return count == 1 ? "1 file" : "\(count) files"
        case .image:
            if let name = entry.imageFile,
               let size = try? FileManager.default.attributesOfItem(atPath: ClipboardHistoryStore.directory.appendingPathComponent(name).path)[.size] as? Int
            {
                return Self.byteFormatter.string(fromByteCount: Int64(size))
            }
            return "Image"
        }
    }

    private struct DayGroup {
        let title: String
        let entries: [ClipboardEntry]
    }

    private func dayGroups(_ entries: [ClipboardEntry]) -> [DayGroup] {
        let calendar = Calendar.current
        var today: [ClipboardEntry] = []
        var yesterday: [ClipboardEntry] = []
        var byDay: [Date: [ClipboardEntry]] = [:]
        for entry in entries {
            if calendar.isDateInToday(entry.date) {
                today.append(entry)
            } else if calendar.isDateInYesterday(entry.date) {
                yesterday.append(entry)
            } else {
                let day = calendar.startOfDay(for: entry.date)
                byDay[day, default: []].append(entry)
            }
        }
        var groups: [DayGroup] = []
        if !today.isEmpty {
            groups.append(DayGroup(title: "Today", entries: today))
        }
        if !yesterday.isEmpty {
            groups.append(DayGroup(title: "Yesterday", entries: yesterday))
        }
        for day in byDay.keys.sorted(by: >) {
            groups.append(DayGroup(title: Self.dateFormatter.string(from: day), entries: byDay[day] ?? []))
        }
        return groups
    }

    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter
    }()

    private static let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .none
        formatter.timeStyle = .short
        return formatter
    }()

    private static let byteFormatter: ByteCountFormatter = {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        return formatter
    }()
}

// MARK: File search

/// The file search: a query field above a list of files beside a preview of
/// the selected file, and the file's actions below.
struct FileSearchView: View {
    @ObservedObject var model: LauncherModel
    @ObservedObject var fileSearch: FileSearch

    var body: some View {
        VStack(spacing: 0) {
            SearchBar(placeholder: "Search files…", text: $model.fileSearchQuery, focusToken: model.focusToken, isLoading: fileSearch.isSearching) { EmptyView() }
            content
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            bottomBar
        }
    }

    /// Either the matching files or the state that explains why there are none.
    @ViewBuilder
    private var content: some View {
        let results = fileSearch.results
        if fileSearch.isSearching, results.isEmpty {
            ThawEmptyState(systemImage: "doc", title: "Searching files…", isLoading: true)
        } else if results.isEmpty, model.fileSearchQuery.isEmpty {
            ThawEmptyState(
                systemImage: "doc",
                title: "No recent files",
                caption: "Files you open will show up here."
            )
        } else if results.isEmpty {
            ThawEmptyState(
                systemImage: "magnifyingglass",
                title: "No files match",
                caption: "Try part of a file's name."
            )
        } else {
            HStack(spacing: 0) {
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 0) {
                            ForEach(Array(results.enumerated()), id: \.element.id) { index, file in
                                FileSearchRow(file: file, selected: index == model.fileSearchSelection)
                                    .id(file.id)
                                    .onTapGesture(count: 2) { model.openSelectedFile() }
                                    .onTapGesture { model.fileSearchSelection = index }
                            }
                        }
                    }
                    .contentMargins(.all, ThawSpacing.base, for: .scrollContent)
                    .onChange(of: model.fileSearchSelection) {
                        if results.indices.contains(model.fileSearchSelection) {
                            proxy.scrollTo(results[model.fileSearchSelection].id)
                        }
                    }
                }
                Divider()
                if let file = model.selectedFile {
                    FilePreview(file: file)
                        .frame(width: 250)
                } else {
                    Color.clear.frame(width: 250)
                }
            }
        }
    }

    private var bottomBar: some View {
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

            ShortcutHintButton(title: "Open") { model.openSelectedFile() } hint: {
                KeyCapView(systemImage: "return")
            }
            ShortcutHintButton(title: "Show in Finder") { model.revealSelectedFile() } hint: {
                KeyCapView(text: "⌘")
                KeyCapView(systemImage: "return")
            }
            // Copy Path keeps its shortcut and moves into the menu, with the rest of what a file can do.
            ShortcutHintButton(title: "Actions…") { model.showActions() } hint: {
                KeyCapView(text: "⌘")
                Text(verbatim: "+")
                KeyCapView(text: "K")
            }
            .background { ActionsAnchor(model: model) { $0.selectedFile.map($0.fileActions) ?? [] } }
        }
        .buttonStyle(SearchPanelButtonStyle())
        .padding(.horizontal, ThawSpacing.inset)
        .padding(.vertical, ThawSpacing.row)
    }
}

struct FileSearchRow: View {
    let file: FileResult
    let selected: Bool

    private var parentName: String {
        file.url.deletingLastPathComponent().lastPathComponent
    }

    var body: some View {
        PaletteRow(title: file.name, subtitle: nil, selected: selected) {
            AppIconView(path: file.url.path, size: 24)
        } trailing: {
            Text(parentName)
                .font(ThawType.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(file.name), \(parentName)")
    }
}

struct FilePreview: View {
    let file: FileResult

    private var values: URLResourceValues {
        let keys: Set<URLResourceKey> = [.localizedTypeDescriptionKey, .fileSizeKey, .isDirectoryKey, .contentModificationDateKey]
        return (try? file.url.resourceValues(forKeys: keys)) ?? URLResourceValues()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            FileThumbnail(url: file.url, maxHeight: 180)
            Text(file.name)
                .font(.system(size: 15, weight: .semibold))
                .lineLimit(2)
            VStack(alignment: .leading, spacing: 6) {
                if let kind = values.localizedTypeDescription {
                    FileMetaRow(label: "Kind") { Text(kind).lineLimit(1) }
                }
                if values.isDirectory != true, let size = values.fileSize {
                    FileMetaRow(label: "Size") {
                        Text(ByteCountFormatter.string(fromByteCount: Int64(size), countStyle: .file))
                    }
                }
                if let modified = values.contentModificationDate {
                    FileMetaRow(label: "Modified") {
                        Text(modified.formatted(date: .abbreviated, time: .shortened))
                    }
                }
                if let lastUsed = file.lastUsed {
                    FileMetaRow(label: "Last opened") {
                        Text(lastUsed.formatted(date: .abbreviated, time: .shortened))
                    }
                }
                FileMetaRow(label: "Where") {
                    Text(file.displayPath).lineLimit(1).truncationMode(.middle).textSelection(.enabled)
                }
            }
            Spacer(minLength: 0)
            HStack(spacing: 8) {
                Text("↵ Open").foregroundStyle(.secondary)
                Text("⌘Y Quick Look").foregroundStyle(.secondary)
                Text("⌘⇧C Copy Path").foregroundStyle(.secondary)
            }
            .font(.system(size: 11))
        }
        .padding(ThawSpacing.gutter)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

struct FileMetaRow<Content: View>: View {
    let label: String
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(label).font(.system(size: 11)).foregroundStyle(.secondary)
            content.font(.system(size: 12))
        }
    }
}

/// A file's Quick Look thumbnail, or its Finder icon while that loads. Clicking it, or ⌘Y anywhere in the
/// preview, opens the full Quick Look panel.
struct FileThumbnail: View {
    let url: URL
    var maxHeight: CGFloat = 180
    @State private var thumbnail: NSImage?
    @State private var quickLook: URL?

    var body: some View {
        Button { quickLook = url } label: {
            Group {
                if let thumbnail {
                    Image(nsImage: thumbnail)
                        .resizable()
                        .scaledToFit()
                        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                        .shadow(color: .black.opacity(0.25), radius: 6, y: 2)
                } else {
                    AppIconView(path: url.path, size: 96)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: maxHeight, alignment: .center)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .keyboardShortcut("y", modifiers: .command)
        .help("Quick Look  ⌘Y")
        .accessibilityLabel("Quick Look \(url.lastPathComponent)")
        .quickLookPreview($quickLook)
        .task(id: url) { await load() }
    }

    private func load() async {
        thumbnail = nil
        let request = QLThumbnailGenerator.Request(
            fileAt: url,
            size: CGSize(width: 512, height: 512),
            scale: NSScreen.main?.backingScaleFactor ?? 2,
            representationTypes: .thumbnail
        )
        if let representation = try? await QLThumbnailGenerator.shared.generateBestRepresentation(for: request) {
            thumbnail = representation.nsImage
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
        guard let context = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: space,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )
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
