//
//  SettingsView.swift
//  Project: Floe
//
//  Copyright (Floe) © 2026 René Jiménez
//  Licensed under the GNU GPLv3

import AppKit
import SwiftUI
import ThawUI

final class SettingsWindowController {
    private var window: NSWindow?
    private let model: LauncherModel
    private let selection = SettingsSelection()

    init(model: LauncherModel) {
        self.model = model
    }

    func show(extensionName: String? = nil, page: SettingsPage? = nil) {
        selection.page = page ?? extensionName.map(SettingsPage.extension) ?? selection.page
        if window == nil {
            let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 820, height: 560),
                                  styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
                                  backing: .buffered, defer: false)
            window.title = "Floe Settings"
            window.titlebarAppearsTransparent = true
            window.toolbarStyle = .unified
            window.isReleasedWhenClosed = false
            window.contentView = NSHostingView(rootView: SettingsView(model: model, settings: .shared, selection: selection))
            window.center()
            self.window = window
        }
        NSApp.activate()
        window?.makeKeyAndOrderFront(nil)
    }
}

enum SettingsPage: Hashable {
    case general
    case applications
    case about
    case `extension`(String)
}

final class SettingsSelection: ObservableObject {
    @Published var page: SettingsPage = .general
}

struct SettingsView: View {
    @ObservedObject var model: LauncherModel
    @ObservedObject var settings: AppSettings
    @ObservedObject var selection: SettingsSelection

    var body: some View {
        NavigationSplitView {
            SettingsSidebarPaneList(model: model, settings: settings, selection: selection)
                .navigationSplitViewColumnWidth(min: SettingsSidebarPaneList.listWidth, ideal: SettingsSidebarPaneList.listWidth, max: 250)
        } detail: {
            detail
                // The system toolbar is the pane header: it names the pane and
                // stays put while the form scrolls under it.
                .navigationSubtitle(subtitle)
                // Fill the detail column so the Form's scrollbar sits on the
                // window's trailing edge.
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                // Content fades under the glass toolbar instead of stopping at a hard band.
                .scrollEdgeEffectStyle(.soft, for: .top)
        }
    }

    @ViewBuilder
    private var detail: some View {
        switch selection.page {
        case .general:
            GeneralSettingsView(model: model, settings: settings)
        case .applications:
            ApplicationSettingsView(model: model, settings: settings)
        case .about:
            AboutSettingsPane()
        case .extension(let name):
            ExtensionSettingsView(model: model, settings: settings,
                                  commands: model.allCommands.filter { $0.extensionName == name })
                .id(name)
        }
    }

    /// Where an extension comes from, under its name in the toolbar.
    private var subtitle: String {
        guard case .extension(let name) = selection.page,
              let command = model.allCommands.first(where: { $0.extensionName == name }) else { return "" }
        let count = model.allCommands.filter { $0.extensionName == name }.count
        let commands = count == 1 ? "1 command" : "\(count) commands"
        return command.source == .raycast ? "From Raycast · \(commands)" : commands
    }
}

// MARK: - SettingsSidebarPaneList

/// Thaw 3's settings sidebar: a standard source list, so selection, keyboard and VoiceOver
/// come from AppKit rather than from hand-drawn rows.
private struct SettingsSidebarPaneList: View {
    @ObservedObject var model: LauncherModel
    @ObservedObject var settings: AppSettings
    @ObservedObject var selection: SettingsSelection

    static let listWidth: CGFloat = 210

    /// Width of the icon column, so labels line up whatever each symbol's
    /// own width is.
    private static let iconColumn: CGFloat = 22

    @Environment(\.colorScheme) private var colorScheme

    /// The accent, deepened in dark mode so a light one such as yellow keeps
    /// its contrast against the selected label.
    private var accent: Color {
        colorScheme == .dark ? Color.accentColor.mix(with: .black, by: 0.4) : Color.accentColor
    }

    private struct Row: Identifiable {
        let page: SettingsPage
        let title: String
        let symbol: String?
        let icon: String?
        let assetsPath: String
        var isDimmed = false
        var id: SettingsPage { page }
    }

    /// General and Applications first, then each extension, About last, as in Thaw.
    private var rows: [Row] {
        var seen = Set<String>()
        let extensions = model.allCommands
            .filter { seen.insert($0.extensionName).inserted }
            .sorted { $0.extensionTitle.localizedCaseInsensitiveCompare($1.extensionTitle) == .orderedAscending }
            .map { command in
                Row(page: .extension(command.extensionName), title: command.extensionTitle, symbol: nil,
                    icon: command.icon ?? "icon:Terminal", assetsPath: command.assetsPath,
                    isDimmed: settings.disabledExtensions.contains(command.extensionName))
            }
        return [
            Row(page: .general, title: "General", symbol: "gearshape", icon: nil, assetsPath: ""),
            Row(page: .applications, title: "Applications", symbol: "square.grid.2x2", icon: nil, assetsPath: ""),
        ] + extensions + [
            Row(page: .about, title: "About", symbol: "info.circle", icon: nil, assetsPath: ""),
        ]
    }

    var body: some View {
        // No Sections: an outline-backed list crashes AppKit on macOS 27.0 and 27.2
        // (freed row view in sizeLastColumnToFit).
        List(selection: Binding(get: { Optional(selection.page) }, set: { if let page = $0 { selection.page = page } })) {
            ForEach(rows) { row in
                Label {
                    Text(row.title)
                        .font(ThawType.detail.weight(.medium))
                        .foregroundStyle(row.isDimmed ? Color.secondary : Color.primary)
                        .lineLimit(1)
                } icon: {
                    Group {
                        if let symbol = row.symbol {
                            Image(systemName: symbol)
                                .font(ThawType.symbol.weight(.medium))
                                .foregroundStyle(Color.secondary)
                        } else {
                            IconView(value: row.icon, assetsPath: row.assetsPath, size: 16)
                                .opacity(row.isDimmed ? 0.5 : 1)
                        }
                    }
                    .frame(width: Self.iconColumn)
                }
                // Only the selection fill carries the accent. Applied per row,
                // where the sidebar reads it.
                .listItemTint(row.page == selection.page ? .preferred(accent) : .monochrome)
                .tag(row.page)
            }
        }
        .listStyle(.sidebar)
        // The selection fill uses the same deepened accent.
        .tint(accent)
        // Medium rows whatever the system's sidebar size: at Large the labels
        // and symbols crowd a settings window this narrow.
        .environment(\.sidebarRowSize, .medium)
        .scrollContentBackground(.hidden)
        .contentMargins(.horizontal, ThawSpacing.base, for: .scrollContent)
        .scrollEdgeEffectStyle(.soft, for: .top)
    }
}

struct GeneralSettingsView: View {
    @ObservedObject var model: LauncherModel
    @ObservedObject var settings: AppSettings

    var body: some View {
        Form {
            ThawSection("Floe") {
                HotkeyRecorder(keyCombination: $settings.toggleHotkey,
                               onRecordingChange: { settings.isRecordingHotkey = $0 }) {
                    Text("Open Floe")
                }
                Toggle("Launch at Login", isOn: Binding(get: { settings.launchAtLogin }, set: { settings.launchAtLogin = $0 }))
                Picker(selection: $settings.popToRootDelay) {
                    Text("Immediately").tag(0)
                    Text("After 30 seconds").tag(30)
                    Text("After 90 seconds").tag(90)
                    Text("After 5 minutes").tag(300)
                } label: {
                    Text("Return to root search")
                    Text("How long a closed launcher keeps the command you had open.")
                }
            }
            ThawSection("Menu Bar Items") {
                HotkeyRecorder(
                    keyCombination: Binding(get: { settings.commandHotkeys[RootItem.menuBarSearchKey] },
                                            set: { settings.commandHotkeys[RootItem.menuBarSearchKey] = $0 }),
                    onRecordingChange: { settings.isRecordingHotkey = $0 }
                ) {
                    Text("Search Menu Bar Items")
                    Text("Find an item in the menu bar and open its menu.")
                }
                TextField("Alias", text: Binding(
                    get: { settings.aliases[RootItem.menuBarSearchKey] ?? "" },
                    set: { settings.aliases[RootItem.menuBarSearchKey] = $0.isEmpty ? nil : $0 }
                ), prompt: Text("None"))
                LabeledContent("Accessibility") {
                    if MenuBarExtras.isTrusted {
                        Text("Allowed").foregroundStyle(.secondary)
                    } else {
                        Button("Grant Access") { model.requestMenuBarAccess() }
                    }
                }
                LabeledContent {
                    if MenuBarPreviews.hasAccess {
                        Text("Allowed").foregroundStyle(.secondary)
                    } else {
                        Button("Grant Access") { MenuBarPreviews.requestAccess() }
                    }
                } label: {
                    Text("Screen Recording")
                    Text("Only for the item previews in the search.")
                }
            }
            ThawSection("Extensions") {
                Toggle(isOn: $settings.includeRaycastExtensions) {
                    Text("Include extensions installed in Raycast")
                    Text("Reads ~/.config/raycast/extensions. Their Raycast settings don't carry over.")
                }
                LabeledContent("Extensions folder") {
                    Button("Show in Finder") { NSWorkspace.shared.activateFileViewerSelecting([Paths.extensions]) }
                }
                LabeledContent("Runtime") {
                    if Paths.isBunBundled {
                        Text("Bun, bundled with the app").foregroundStyle(.secondary)
                    } else if let bun = Paths.bun {
                        Text(bun).foregroundStyle(.secondary).textSelection(.enabled)
                    } else {
                        Text("Bun not found. Install it with brew install bun.").foregroundStyle(.red)
                    }
                }
            }
        }
        .formStyle(.grouped)
        .navigationTitle("General")
    }
}

/// Aliases and hotkeys for apps. Rows are plain text so the page stays cheap with hundreds of apps;
/// the editing controls exist only for the selected app.
struct ApplicationSettingsView: View {
    @ObservedObject var model: LauncherModel
    @ObservedObject var settings: AppSettings
    @State private var filter = ""
    @State private var selection: URL?

    var body: some View {
        let apps = model.apps.filter { filter.isEmpty || $0.name.localizedCaseInsensitiveContains(filter) }
        VStack(spacing: 0) {
            editor
            Divider()
            List(apps, id: \.url, selection: $selection) { app in
                let key = Self.key(app)
                HStack(spacing: ThawSpacing.row) {
                    AppIconView(path: app.url.path, size: 18)
                    Text(app.name).lineLimit(1)
                    Spacer()
                    if let alias = settings.aliases[key] { KeyCap(alias) }
                    Text(settings.commandHotkeys[key]?.displayValue ?? "")
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
            }
            .overlay {
                if apps.isEmpty { ContentUnavailableView.search(text: filter) }
            }
        }
        .searchable(text: $filter, placement: .toolbar, prompt: "Filter applications")
        .navigationTitle("Applications")
    }

    private static func key(_ app: AppEntry) -> String {
        RootItem.app(app).settingsKey ?? app.url.path
    }

    @ViewBuilder
    private var editor: some View {
        if let app = model.apps.first(where: { $0.url == selection }) {
            let key = Self.key(app)
            Form {
                ThawSection {
                    HStack(spacing: ThawSpacing.compact) {
                        AppIconView(path: app.url.path, size: 14)
                        Text(app.name)
                    }
                } content: {
                    TextField("Alias", text: Binding(
                        get: { settings.aliases[key] ?? "" },
                        set: { settings.aliases[key] = $0.isEmpty ? nil : $0 }
                    ), prompt: Text("None"))
                    HotkeyRecorder(
                        keyCombination: Binding(get: { settings.commandHotkeys[key] }, set: { settings.commandHotkeys[key] = $0 }),
                        onRecordingChange: { settings.isRecordingHotkey = $0 }
                    ) {
                        Text("Hotkey")
                        Text("Opens the app, or hides it if it's already in front.")
                    }
                }
            }
            .formStyle(.grouped)
            .scrollDisabled(true)
            .frame(height: 170)
            .id(key)
        } else {
            Text("Select an app to give it an alias or a hotkey.")
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity)
                .frame(height: 64)
        }
    }
}

/// App icons are slow to fetch one by one on the main thread; fetch once per path and reuse.
struct AppIconView: View {
    let path: String
    let size: CGFloat
    @State private var image: NSImage?

    private static let cache = NSCache<NSString, NSImage>()

    var body: some View {
        Group {
            if let image = image ?? Self.cache.object(forKey: path as NSString) {
                Image(nsImage: image).resizable()
            } else {
                Color.clear
            }
        }
        .frame(width: size, height: size)
        .task(id: path) {
            guard Self.cache.object(forKey: path as NSString) == nil else { return }
            let icon = NSWorkspace.shared.icon(forFile: path)
            Self.cache.setObject(icon, forKey: path as NSString)
            image = icon
        }
    }
}

struct ExtensionSettingsView: View {
    @ObservedObject var model: LauncherModel
    @ObservedObject var settings: AppSettings
    let commands: [ExtensionCommand]

    var body: some View {
        if let first = commands.first {
            Form {
                ThawSection {
                    Toggle(isOn: Binding(
                        get: { !settings.disabledExtensions.contains(first.extensionName) },
                        set: { enabled in
                            if enabled { settings.disabledExtensions.remove(first.extensionName) } else { settings.disabledExtensions.insert(first.extensionName) }
                        }
                    )) {
                        HStack(spacing: ThawSpacing.compact) {
                            Text("Enabled")
                            if first.source == .raycast { ThawBadge("Raycast") }
                        }
                        Text((first.extensionDir.path as NSString).abbreviatingWithTildeInPath)
                    }
                }
                if !first.extensionPreferences.isEmpty {
                    ThawSection("Preferences") {
                        PreferencesEditor(fields: first.extensionPreferences, extensionName: first.extensionName, command: nil)
                    }
                }
                ForEach(commands) { command in
                    ThawSection {
                        HStack(spacing: ThawSpacing.compact) {
                            IconView(value: command.icon ?? "icon:Terminal", assetsPath: command.assetsPath, size: 14)
                            Text(command.title)
                            if command.mode == "no-view" { ThawBadge("No View") }
                        }
                    } content: {
                        CommandSettingsRows(settings: settings, command: command)
                    }
                }
            }
            .formStyle(.grouped)
            .navigationTitle(first.extensionTitle)
        }
    }
}

struct CommandSettingsRows: View {
    @ObservedObject var settings: AppSettings
    let command: ExtensionCommand

    var body: some View {
        TextField("Alias", text: Binding(
            get: { settings.aliases[command.id] ?? "" },
            set: { settings.aliases[command.id] = $0.isEmpty ? nil : $0 }
        ), prompt: Text("None"))
        HotkeyRecorder(
            keyCombination: Binding(get: { settings.commandHotkeys[command.id] }, set: { settings.commandHotkeys[command.id] = $0 }),
            onRecordingChange: { settings.isRecordingHotkey = $0 }
        ) {
            Text("Hotkey")
        }
        if !command.commandPreferences.isEmpty {
            PreferencesEditor(fields: command.commandPreferences, extensionName: command.extensionName, command: command)
        }
    }
}

/// Edits stored preference values; saved on each change, passwords to the Keychain.
struct PreferencesEditor: View {
    let fields: [FieldSpec]
    let extensionName: String
    let command: ExtensionCommand?
    @State private var values: [String: String] = [:]
    @State private var loaded = false

    var body: some View {
        ForEach(fields) { field in
            FieldEditor(field: field, value: Binding(
                get: { values[field.name] ?? "" },
                set: { values[field.name] = $0 }
            ))
        }
        .onAppear(perform: load)
        .onChange(of: values) { save() }
    }

    private func load() {
        values = Dictionary(uniqueKeysWithValues: fields.map { field in
            let stored = PreferenceStore.value(field, extensionName: extensionName, command: command) ?? field.defaultValue
            return (field.name, stored.map(LauncherModel.text(from:)) ?? (field.type == "dropdown" ? field.options.first?.value ?? "" : ""))
        })
        loaded = true
    }

    private func save() {
        guard loaded else { return }
        let typed = fields.reduce(into: [String: Any]()) { result, field in
            let text = values[field.name] ?? ""
            result[field.name] = field.type == "checkbox" ? (text == "true") : text
        }
        PreferenceStore.save(typed, fields: fields, extensionName: extensionName, command: command)
    }
}
