//
//  ClipboardHistoryView.swift
//  Project: Floe
//
//  Copyright (Floe) © 2026 René Jiménez
//  Licensed under the GNU AGPLv3

import Algorithms
import AppKit
import SwiftUI
import ThawUI

/// Saved copies: a searchable list with Pinned and day sections, and a preview
/// with metadata. Return pastes (Command-V when Accessibility allows it),
/// Escape goes back to the root search.
struct ClipboardHistoryView: View {
    @ObservedObject var clipboard: ClipboardHistoryModel
    /// For the gear. Not observed: nothing here is drawn from it.
    let launcher: LauncherModel
    let focusToken: Int
    @ObservedObject var history = ClipboardHistoryStore.shared
    @ObservedObject var settings = AppSettings.shared

    var body: some View {
        VStack(spacing: 0) {
            SearchBar(placeholder: "Search clipboard history…", text: $clipboard.query, focusToken: focusToken) { EmptyView() }
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
            let entries = clipboard.filteredEntries()
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
                    let (rest, pinned) = entries.partitioned(by: \.pinned)
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
            .onChange(of: clipboard.selection) {
                if entries.indices.contains(clipboard.selection) {
                    proxy.scrollTo(entries[clipboard.selection].id)
                }
            }
        }
    }

    private func row(_ entry: ClipboardEntry, entries: [ClipboardEntry]) -> some View {
        let index = entries.firstIndex(where: { $0.id == entry.id }) ?? 0
        let selected = index == clipboard.selection
        return HStack(spacing: 10) {
            Image(systemName: entry.kind.symbol)
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
        .onTapGesture(count: 2) { clipboard.paste(entry) }
        .onTapGesture { clipboard.selection = index }
    }

    @ViewBuilder
    private var preview: some View {
        if let entry = clipboard.selectedEntry {
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
            OpenSettingsButton(model: launcher)
            Spacer(minLength: 0)
            if let entry = clipboard.selectedEntry {
                ShortcutHintButton(title: entry.pinned ? "Unpin" : "Pin") { clipboard.togglePin(entry) } hint: {
                    KeyCapView(systemImage: "pin")
                }
                ShortcutHintButton(title: "Delete") { clipboard.delete(entry) } hint: {
                    KeyCapView(text: "⌫")
                }
                ShortcutHintButton(title: "Copy") { clipboard.copy(entry) } hint: {
                    KeyCapView(text: "⌘C")
                }
                ShortcutHintButton(title: "Paste") { clipboard.paste(entry) } hint: {
                    KeyCapView(systemImage: "return")
                }
            }
        }
        .padding(.horizontal, ThawSpacing.inset)
        .padding(.vertical, ThawSpacing.row)
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
