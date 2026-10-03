//
//  Model.swift
//  Project: Floe
//
//  Copyright (Floe) © 2026 René Jiménez
//  Licensed under the GNU GPLv3

import AppKit

struct MenuBarResult: Identifiable {
    let extra: MenuBarExtra
    let section: String?
    var id: String { extra.id }
}

/// Fields to fill in before a command can run: its required preferences, or its arguments.
struct SetupRequest {
    enum Kind { case preferences, arguments }
    let command: ExtensionCommand
    let kind: Kind
    let fields: [FieldSpec]
}

final class LauncherModel: ObservableObject {
    @Published var query = "" { didSet { refresh() } }
    @Published private(set) var results: [RootResult] = []
    @Published var selection = 0
    @Published private(set) var session: ExtensionSession?
    @Published private(set) var setup: SetupRequest?
    /// Field values for `setup`, as text; checkboxes are "true" or "false".
    @Published var setupValues: [String: String] = [:]
    @Published var setupError: String?
    /// Bumped whenever the panel is shown so the search field can take focus again.
    @Published var focusToken = 0
    /// Every command found, including those of disabled extensions; the settings window lists these.
    @Published private(set) var allCommands: [ExtensionCommand] = []

    /// True while the panel shows the menu bar item search instead of the root search.
    @Published private(set) var isSearchingMenuBar = false
    @Published var menuBarQuery = "" { didSet { refreshMenuBar() } }
    @Published private(set) var menuBarResults: [MenuBarResult] = []
    @Published var menuBarSelection = 0
    @Published private(set) var isScanningMenuBar = false
    @Published private(set) var menuBarAccessGranted = MenuBarExtras.isTrusted
    /// The item being renamed with Edit Name, and the text typed so far.
    @Published var renamingMenuBarItem: String?
    @Published var menuBarRenameDraft = ""
    private var menuBarExtras: [MenuBarExtra] = []
    private let menuBarRecents = MenuBarSearchRecents()
    let menuBarPreviews = MenuBarPreviews()

    var hidePanel: () -> Void = {}
    var showPanel: () -> Void = {}
    var showHUD: (String) -> Void = { _ in }
    /// Opens the settings window, optionally on one extension's page.
    var openSettings: (String?) -> Void = { _ in }
    /// Pops the Actions menu under its button in the menu bar search's bottom bar.
    var showMenuBarActions: () -> Void = {}

    private let settings = AppSettings.shared
    private let usage = UsageStore.shared
    private var pendingReset: DispatchWorkItem?
    @Published private(set) var apps = AppEntry.scan()
    private var commands: [ExtensionCommand] {
        allCommands.filter { !settings.disabledExtensions.contains($0.extensionName) }
    }

    init() {
        reloadCommands()
    }

    func reloadCommands() {
        allCommands = ExtensionCommand.scan(includeRaycast: settings.includeRaycastExtensions)
        refresh()
    }

    private func refresh() {
        selection = 0
        let all = commands.map(RootItem.command) + apps.map(RootItem.app) + [RootItem.menuBarSearch, RootItem.settings]
        results = query.isEmpty ? browseResults(all) : searchResults(all)
    }

    /// No query: favourites, then recently used, then commands and applications.
    private func browseResults(_ all: [RootItem]) -> [RootResult] {
        let byID = Dictionary(all.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let favorites = settings.favorites.compactMap { byID[$0] }
        let favoriteIDs = Set(favorites.map(\.id))
        let suggestions = all
            .filter { !favoriteIDs.contains($0.id) && usage.frecency(of: $0.id) > 0 }
            .sorted { usage.frecency(of: $0.id) > usage.frecency(of: $1.id) }
            .prefix(5)
        let shown = favoriteIDs.union(suggestions.map(\.id))
        let rest = all.filter { !shown.contains($0.id) }
        return favorites.map { RootResult(item: $0, section: "Favorites") }
            + suggestions.map { RootResult(item: $0, section: "Suggestions") }
            + rest.filter { if case .app = $0 { false } else { true } }.map { RootResult(item: $0, section: "Commands") }
            + rest.filter { if case .app = $0 { true } else { false } }.map { RootResult(item: $0, section: "Applications") }
    }

    /// With a query: match quality first, nudged by how often and how recently each item is used.
    private func searchResults(_ all: [RootItem]) -> [RootResult] {
        all.compactMap { item -> (RootItem, Double)? in
            guard let match = score(item) else { return nil }
            let boost = min(20, usage.frecency(of: item.id) * 2) + (settings.favorites.contains(item.id) ? 5 : 0)
            return (item, Double(match) + boost)
        }
        .sorted { $0.1 > $1.1 }
        .prefix(40)
        .map { RootResult(item: $0.0, section: nil) }
    }

    /// An exact alias wins outright; an alias prefix ranks with a title prefix.
    private func score(_ item: RootItem) -> Int? {
        let titleScore = Fuzzy.score(query, item.title)
        guard let alias = alias(for: item)?.lowercased() else { return titleScore }
        if alias == query.lowercased() { return 1000 }
        if alias.hasPrefix(query.lowercased()) { return max(titleScore ?? 0, 95) }
        return titleScore
    }

    func alias(for item: RootItem) -> String? {
        item.settingsKey.flatMap { settings.aliases[$0] }.flatMap { $0.isEmpty ? nil : $0 }
    }

    func isFavorite(_ item: RootItem) -> Bool {
        settings.favorites.contains(item.id)
    }

    func toggleFavorite(_ item: RootItem) {
        if let index = settings.favorites.firstIndex(of: item.id) {
            settings.favorites.remove(at: index)
            showHUD("Removed from Favorites")
        } else {
            settings.favorites.append(item.id)
            showHUD("Added to Favorites")
        }
        refresh()
    }

    /// Opens an app, or hides it if it's already in front, like a per-app hotkey in Thaw.
    func toggleApp(_ app: AppEntry) {
        usage.recordUse(of: RootItem.app(app).id)
        if let running = NSWorkspace.shared.frontmostApplication, running.bundleURL?.standardizedFileURL == app.url.standardizedFileURL {
            running.hide()
        } else {
            NSWorkspace.shared.open(app.url)
        }
    }

    func reloadApps() {
        apps = AppEntry.scan()
        refresh()
    }

    func activate(_ item: RootItem) {
        usage.recordUse(of: item.id)
        switch item {
        case .app(let app):
            NSWorkspace.shared.open(app.url)
            hidePanel()
            reset()
        case .command(let command):
            run(command)
        case .menuBarSearch:
            openMenuBarSearch()
        case .settings:
            hidePanel()
            openSettings(nil)
        }
    }

    // MARK: Menu bar items

    /// Switches the panel to the menu bar item search and rescans the menu bar.
    func openMenuBarSearch() {
        if let session { end(session) }
        setup = nil
        isSearchingMenuBar = true
        if !settings.rememberMenuBarQuery { menuBarQuery = "" }
        showPanel()
        focusToken += 1
        scanMenuBar()
    }

    func closeMenuBarSearch() {
        isSearchingMenuBar = false
        focusToken += 1
    }

    private func scanMenuBar() {
        menuBarAccessGranted = MenuBarExtras.isTrusted
        guard menuBarAccessGranted else {
            menuBarExtras = []
            refreshMenuBar()
            return
        }
        isScanningMenuBar = menuBarExtras.isEmpty
        DispatchQueue.global(qos: .userInitiated).async {
            let extras = MenuBarExtras.scan()
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                menuBarExtras = extras
                isScanningMenuBar = false
                refreshMenuBar()
                menuBarPreviews.capture(extras)
            }
        }
    }

    func requestMenuBarAccess() {
        MenuBarExtras.requestAccess()
        // The grant happens in System Settings; check again when the user comes back.
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) { [weak self] in self?.scanMenuBar() }
    }

    /// No query: recently opened items, then every item in menu bar order. With a query: items whose
    /// name or owning app matches.
    private func refreshMenuBar() {
        menuBarSelection = 0
        let query = menuBarQuery.trimmingCharacters(in: .whitespaces)
        guard !query.isEmpty else {
            let recents = menuBarRecents.resolve(in: menuBarExtras)
            let recentIDs = Set(recents.map(\.id))
            menuBarResults = recents.map { MenuBarResult(extra: $0, section: "Recent") }
                + menuBarExtras.filter { !recentIDs.contains($0.id) }.map { MenuBarResult(extra: $0, section: "Menu Bar") }
            return
        }
        menuBarResults = menuBarExtras
            .compactMap { extra -> (MenuBarExtra, Int)? in
                let byName = Fuzzy.score(query, displayName(for: extra))
                let byOwner = Fuzzy.score(query, extra.ownerName).map { $0 - 10 }
                guard let score = [byName, byOwner].compactMap({ $0 }).max() else { return nil }
                return (extra, score)
            }
            .sorted { $0.1 > $1.1 }
            .map { MenuBarResult(extra: $0.0, section: nil) }
    }

    /// The owning app's name, when it says something the item's name doesn't.
    func ownerLine(for extra: MenuBarExtra) -> String? {
        extra.ownerName.isEmpty || extra.ownerName == extra.name ? nil : extra.ownerName
    }

    /// The name the user gave the item, else the one its app reports.
    func displayName(for extra: MenuBarExtra) -> String {
        settings.menuBarItemNames[extra.id].flatMap { $0.isEmpty ? nil : $0 } ?? extra.name
    }

    var selectedMenuBarExtra: MenuBarExtra? {
        menuBarResults.indices.contains(menuBarSelection) ? menuBarResults[menuBarSelection].extra : nil
    }

    func beginRenamingSelection() {
        guard let extra = selectedMenuBarExtra else { return }
        menuBarRenameDraft = displayName(for: extra)
        renamingMenuBarItem = extra.id
    }

    /// An empty name goes back to the one the app reports.
    func commitRename() {
        guard let id = renamingMenuBarItem else { return }
        let name = menuBarRenameDraft.trimmingCharacters(in: .whitespaces)
        settings.menuBarItemNames[id] = name.isEmpty ? nil : name
        renamingMenuBarItem = nil
        let selected = menuBarSelection
        refreshMenuBar()
        menuBarSelection = min(selected, max(menuBarResults.count - 1, 0))
        focusToken += 1
    }

    func cancelRename() {
        renamingMenuBarItem = nil
        focusToken += 1
    }

    /// Things Floe can do with an item; Thaw's moving between sections stays with Thaw.
    func menuBarActions(for extra: MenuBarExtra) -> [(title: String, symbol: String, run: () -> Void)?] {
        var actions: [(title: String, symbol: String, run: () -> Void)?] = [
            ("Click Item", "cursorarrow.click", { [weak self] in self?.openMenuBarExtra(extra) }),
            ("Edit Name", "pencil", { [weak self] in self?.beginRenamingSelection() }),
            ("Copy Name", "doc.on.doc", { [weak self] in
                guard let self else { return }
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(displayName(for: extra), forType: .string)
                showHUD("Copied \(displayName(for: extra))")
            }),
        ]
        if settings.menuBarItemNames[extra.id] != nil {
            actions.append(("Restore Original Name", "arrow.uturn.backward", { [weak self] in
                self?.settings.menuBarItemNames[extra.id] = nil
                self?.refreshMenuBar()
            }))
        }
        if let url = extra.ownerURL {
            actions.append(nil)
            actions.append(("Open \(extra.ownerName)", "app", { [weak self] in
                NSWorkspace.shared.open(url)
                self?.hidePanel()
            }))
            actions.append(("Show \(extra.ownerName) in Finder", "folder", { [weak self] in
                NSWorkspace.shared.activateFileViewerSelecting([url])
                self?.hidePanel()
            }))
        }
        return actions
    }

    func openMenuBarExtra(_ extra: MenuBarExtra) {
        menuBarRecents.record(extra)
        hidePanel()
        reset()
        // Pressed once the panel is gone, so the menu opens over the app the user came from.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { MenuBarExtras.open(extra) }
    }

    /// `FLOE_AUTORUN=extension/command` opens a command at startup, for screenshots and debugging.
    func autorun() {
        guard let target = ProcessInfo.processInfo.environment["FLOE_AUTORUN"],
              let command = commands.first(where: { $0.id == target }) else { return }
        run(command)
    }

    /// Runs a command, first asking for missing required preferences and then for its arguments.
    func run(_ command: ExtensionCommand, arguments: [String: Any]? = nil) {
        if let session { end(session) }
        let missing = PreferenceStore.missingRequired(for: command)
        if !missing.isEmpty {
            beginSetup(SetupRequest(command: command, kind: .preferences, fields: command.preferences))
        } else if arguments == nil, !command.arguments.isEmpty {
            beginSetup(SetupRequest(command: command, kind: .arguments, fields: command.arguments))
        } else {
            if command.mode == "view" { showPanel() }
            launch(command, arguments: arguments ?? [:])
        }
    }

    private func beginSetup(_ request: SetupRequest) {
        var values: [String: String] = [:]
        for field in request.fields {
            let scope = request.command.commandPreferences.contains { $0.name == field.name } ? request.command : nil
            let stored = request.kind == .preferences
                ? PreferenceStore.value(field, extensionName: request.command.extensionName, command: scope) ?? field.defaultValue
                : field.defaultValue
            values[field.name] = stored.map(Self.text(from:)) ?? (field.type == "dropdown" ? field.options.first?.value : nil) ?? ""
        }
        setupValues = values
        setupError = nil
        setup = request
        showPanel()
        focusToken += 1
    }

    func submitSetup() {
        guard let request = setup else { return }
        let missing = request.fields.filter { $0.required && $0.type != "checkbox" && (setupValues[$0.name] ?? "").isEmpty }
        guard missing.isEmpty else {
            setupError = "Fill in \(missing.map(\.title).joined(separator: ", "))."
            return
        }
        let values = request.fields.reduce(into: [String: Any]()) { result, field in
            let text = setupValues[field.name] ?? ""
            result[field.name] = field.type == "checkbox" ? (text == "true") : text
        }
        setup = nil
        switch request.kind {
        case .preferences:
            let command = request.command
            PreferenceStore.save(values, fields: command.extensionPreferences, extensionName: command.extensionName, command: nil)
            PreferenceStore.save(values, fields: command.commandPreferences, extensionName: command.extensionName, command: command)
            run(command)
        case .arguments:
            run(request.command, arguments: values)
        }
    }

    func cancelSetup() {
        setup = nil
        focusToken += 1
    }

    static func text(from value: Any) -> String {
        if let bool = value as? Bool { return bool ? "true" : "false" }
        return value as? String ?? "\(value)"
    }

    private func launch(_ command: ExtensionCommand, arguments: [String: Any]) {
        let session = ExtensionSession(command: command, arguments: arguments)
        session.onMessage = { [weak self, weak session] message in
            guard let self, let session else { return }
            self.handle(message, from: session)
        }
        self.session = session
        session.start()
    }

    private func handle(_ message: [String: Any], from session: ExtensionSession) {
        switch message["type"] as? String {
        case "exit", "popToRoot":
            let wasBackground = session.command.mode != "view"
            end(session)
            if wasBackground { hidePanel() }
        case "crashed" where session.command.mode != "view":
            end(session)
            showHUD("\(session.command.title) failed")
        case "close":
            hidePanel()
        case "hud":
            showHUD(message["title"] as? String ?? "")
            hidePanel()
        case "copy":
            copy(message["text"] as? String ?? "")
        case "paste":
            // Pasting into the frontmost app needs Accessibility access, so for now this only copies.
            copy(message["text"] as? String ?? "")
            showHUD("Copied. Press ⌘V to paste.")
            hidePanel()
        case "open":
            open(message["target"] as? String ?? "", application: message["application"] as? String)
        case "openPreferences":
            hidePanel()
            openSettings(session.command.extensionName)
        default:
            break
        }
    }

    private func end(_ session: ExtensionSession) {
        // Trailing messages (a HUD after closeMainWindow, say) still need to be read.
        session.stop(after: 0.5)
        if self.session === session {
            self.session = nil
            focusToken += 1
        }
    }

    /// The panel closed. The open command survives for the configured delay, so reopening resumes it.
    func panelDidHide() {
        pendingReset?.cancel()
        let delay = settings.popToRootDelay
        guard delay > 0, session != nil || setup != nil else {
            reset()
            return
        }
        let work = DispatchWorkItem { [weak self] in self?.reset() }
        pendingReset = work
        DispatchQueue.main.asyncAfter(deadline: .now() + .seconds(delay), execute: work)
    }

    func panelWillShow() {
        pendingReset?.cancel()
        pendingReset = nil
    }

    /// Runs the command that failed again, with the same arguments.
    func retry() {
        guard let session else { return }
        let command = session.command, arguments = session.arguments
        end(session)
        run(command, arguments: arguments)
    }

    func copyFailure() {
        guard let session, let failure = session.failure else { return }
        copy("\(session.command.extensionTitle) › \(session.command.title)\n\(failure.message)\n\n\(failure.details)")
        showHUD("Copied error details")
    }

    /// Back to the root search, ending any open command.
    func reset() {
        pendingReset?.cancel()
        pendingReset = nil
        if let session { end(session) }
        setup = nil
        isSearchingMenuBar = false
        query = ""
    }

    private func copy(_ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }

    private func open(_ target: String, application: String?) {
        if let application {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/open")
            process.arguments = ["-a", application, target]
            try? process.run()
        } else if let url = URL(string: target), url.scheme != nil {
            NSWorkspace.shared.open(url)
        } else {
            NSWorkspace.shared.open(URL(fileURLWithPath: (target as NSString).expandingTildeInPath))
        }
    }

    // MARK: Keyboard

    /// Returns true when the key was consumed.
    func handleKey(_ event: NSEvent) -> Bool {
        let flags = event.modifierFlags.intersection([.command, .shift, .option, .control])
        if setup != nil {
            switch event.keyCode {
            case 53: cancelSetup()
            case 36, 76: submitSetup()
            default: return false
            }
            return true
        }
        if event.keyCode == 43, flags == .command {
            hidePanel()
            openSettings(nil)
            return true
        }
        if isSearchingMenuBar, renamingMenuBarItem != nil {
            switch event.keyCode {
            case 36, 76: commitRename()
            case 53: cancelRename()
            default: return false
            }
            return true
        }
        if isSearchingMenuBar, flags == .command, event.keyCode == 14 {
            beginRenamingSelection()
            return true
        }
        if isSearchingMenuBar, flags == .command, event.keyCode == 40 {
            showMenuBarActions()
            return true
        }
        if isSearchingMenuBar {
            if let delta = Self.navigationDelta(event.keyCode) {
                menuBarSelection = max(0, min(menuBarSelection + delta, menuBarResults.count - 1))
                return true
            }
            switch event.keyCode {
            case 36, 76:
                if menuBarResults.indices.contains(menuBarSelection) { openMenuBarExtra(menuBarResults[menuBarSelection].extra) }
            case 53:
                if menuBarQuery.isEmpty { closeMenuBarSearch() } else { menuBarQuery = "" }
            default: return false
            }
            return true
        }
        if let session, session.command.mode == "view", session.failure != nil {
            switch event.keyCode {
            case 36: retry()
            case 53: end(session)
            case 8 where flags == [.command, .shift]: copyFailure()
            default: return false
            }
            return true
        }
        if let session, session.command.mode == "view" {
            return handleSessionKey(event, flags, session)
        }
        if let delta = Self.navigationDelta(event.keyCode) {
            selection = max(0, min(selection + delta, results.count - 1))
            return true
        }
        switch event.keyCode {
        case 36: if results.indices.contains(selection) { activate(results[selection].item) }
        case 53: if query.isEmpty { hidePanel() } else { query = "" }
        case 3 where flags == [.command, .shift]:
            if results.indices.contains(selection) { toggleFavorite(results[selection].item) }
        default: return false
        }
        return true
    }

    /// ↑↓ move by one, Page Up/Down by a screenful, Home/End to the ends.
    static func navigationDelta(_ keyCode: UInt16) -> Int? {
        switch keyCode {
        case 125: 1
        case 126: -1
        case 121: 9
        case 116: -9
        case 119: Int.max / 2
        case 115: -(Int.max / 2)
        default: nil
        }
    }

    private func handleSessionKey(_ event: NSEvent, _ flags: NSEvent.ModifierFlags, _ session: ExtensionSession) -> Bool {
        let actions = session.actions
        // In a form, arrows and Return belong to the fields; ⌘↵ submits.
        if session.view?.type == "Form", !session.actionMenuOpen {
            switch event.keyCode {
            case 125, 126: return false
            case 36 where flags != .command: return false
            case 36:
                if let action = actions.first { session.run(action) }
                return true
            default: break
            }
        }
        if session.actionMenuOpen, handleActionMenuKey(event, flags, session) {
            return true
        }
        if let delta = Self.navigationDelta(event.keyCode) {
            session.moveSelection(by: delta)
            return true
        }
        switch event.keyCode {
        case 53:
            session.send(["type": "pop"])
        case 33 where flags == .command:
            session.send(["type": "pop"])
        case 36:
            let index = flags == .command ? 1 : 0
            if actions.indices.contains(index) { session.run(actions[index]) }
        case 40 where flags == .command:
            session.actionMenuOpen = true
        default:
            guard !flags.isEmpty, let action = actions.first(where: { Self.matches($0.props["shortcut"], event, flags) }) else { return false }
            session.run(action)
        }
        return true
    }

    /// While the action menu is open, typing searches it, ↵ runs or opens a submenu, ← and Esc step back.
    private func handleActionMenuKey(_ event: NSEvent, _ flags: NSEvent.ModifierFlags, _ session: ExtensionSession) -> Bool {
        if let delta = Self.navigationDelta(event.keyCode) {
            session.moveSelection(by: delta)
            return true
        }
        switch event.keyCode {
        case 36, 76: session.activateMenuEntry(at: session.actionSelection)
        case 53, 123: session.closeSubmenuOrMenu()
        case 124:
            let entries = session.menuEntries
            if entries.indices.contains(session.actionSelection), entries[session.actionSelection].isSubmenu {
                session.openSubmenu(entries[session.actionSelection].node)
            }
        case 40 where flags == .command: session.actionMenuOpen = false
        case 51: if !session.actionQuery.isEmpty { session.actionQuery.removeLast() }
        default:
            // Plain typing (Shift allowed) filters; anything with ⌘, ⌃ or ⌥ falls through to shortcuts.
            guard flags.subtracting(.shift).isEmpty, let characters = event.characters,
                  !characters.isEmpty, characters.unicodeScalars.allSatisfy({ !CharacterSet.controlCharacters.contains($0) }) else {
                return false
            }
            session.actionQuery += characters
        }
        return true
    }

    private static func matches(_ shortcut: Any?, _ event: NSEvent, _ flags: NSEvent.ModifierFlags) -> Bool {
        guard let shortcut = shortcut as? [String: Any], let key = shortcut["key"] as? String else { return false }
        var expected: NSEvent.ModifierFlags = []
        for modifier in shortcut["modifiers"] as? [String] ?? [] {
            switch modifier {
            case "cmd": expected.insert(.command)
            case "shift": expected.insert(.shift)
            case "opt", "alt": expected.insert(.option)
            case "ctrl": expected.insert(.control)
            default: break
            }
        }
        return expected == flags && event.charactersIgnoringModifiers?.lowercased() == key.lowercased()
    }
}
