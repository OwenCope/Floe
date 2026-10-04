//
//  Model.swift
//  Project: Floe
//
//  Copyright (Floe) © 2026 René Jiménez
//  Licensed under the GNU AGPLv3

import AppKit
import ApplicationServices

struct MenuBarResult: Identifiable {
    let extra: MenuBarExtra
    let section: String?
    var id: String {
        extra.id
    }
}

/// Fields to fill in before a command can run: its required preferences, or its arguments.
struct SetupRequest {
    enum Kind { case preferences, arguments }
    let command: ExtensionCommand
    let kind: Kind
    let fields: [FieldSpec]
}

final class LauncherModel: ObservableObject {
    @Published var query = "" {
        didSet { refresh() }
    }

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
    /// Every script command found in the Scripts folder.
    @Published private(set) var allScripts: [ScriptCommand] = []
    /// System Settings' panes, found once at launch: they only change with the system.
    private var settingsPanes: [SystemSettingsPane] = []
    /// Files in the Scripts folder that failed to parse, for the settings pane.
    @Published private(set) var scriptFailures: [ScriptFailure] = []
    /// True until the first apps and commands scans have both published, or a snapshot was injected.
    @Published private(set) var isLoadingCatalog = true

    /// True while the panel shows the file search instead of the root search.
    @Published private(set) var isSearchingFiles = false
    @Published var fileSearchQuery = "" {
        didSet {
            fileSearchSelection = 0
            fileSearch.search(fileSearchQuery)
        }
    }

    @Published var fileSearchSelection = 0
    let fileSearch = FileSearch()

    /// True while the panel shows the menu bar item search instead of the root search.
    @Published private(set) var isSearchingMenuBar = false
    /// True while the panel shows the clipboard history instead of the root search.
    @Published private(set) var isShowingClipboardHistory = false
    @Published var clipboardQuery = "" {
        didSet { clipboardSelection = 0 }
    }

    @Published var clipboardSelection = 0
    @Published var menuBarQuery = "" {
        didSet { refreshMenuBar() }
    }

    @Published private(set) var menuBarResults: [MenuBarResult] = []
    @Published var menuBarSelection = 0
    @Published private(set) var isScanningMenuBar = false
    @Published private(set) var menuBarAccessGranted = MenuBarExtras.isTrusted
    /// The item being renamed with Edit Name, and the text typed so far.
    @Published var renamingMenuBarItem: String?
    @Published var menuBarRenameDraft = ""
    private var menuBarExtras: [MenuBarExtra] = []
    private let menuBarRecents = MenuBarSearchRecents()

    // The app delegate replaces these; the defaults keep the model usable without a window.
    var hidePanel: () -> Void = { /* no panel */ }
    var showPanel: () -> Void = { /* no panel */ }
    var showHUD: (String) -> Void = { _ in
        // No HUD.
    }

    /// Opens the settings window, optionally on one extension's page.
    var openSettings: (String?) -> Void = { _ in
        // No settings window.
    }

    /// Pops the Actions menu of the search that is on screen: root, files or menu bar items.
    var showActions: () -> Void = { /* set by the Actions button */ }

    private let settings: AppSettings
    private let usage: UsageStore
    private let scanner: any CatalogScanning
    /// Bumped per request, so a result can tell whether its request is still the newest one.
    private var appsGeneration = 0
    private var commandsGeneration = 0
    private var scriptsGeneration = 0
    private var appsTask: Task<Void, Never>?
    private var commandsTask: Task<Void, Never>?
    private var scriptsTask: Task<Void, Never>?
    private var hasLoadedApps = false
    private var hasLoadedCommands = false
    private var hasLoadedScripts = false
    private var didAutorun = false
    private var pendingReset: DispatchWorkItem?
    /// Watches the open command's extension while it is one being developed (see HotReload.swift).
    private var sourceWatcher: DirectoryWatcher?
    @Published private(set) var apps: [AppEntry] = []
    private var commands: [ExtensionCommand] {
        allCommands.filter { !settings.disabledExtensions.contains($0.extensionName) }
    }

    /// Every command that may run on its own: a menu-bar command only once it was put in the menu bar.
    /// Controllers read this and filter by mode.
    var enabledCommands: [ExtensionCommand] {
        commands.filter { $0.mode != "menu-bar" || settings.menuBarCommands.contains($0.id) }
    }

    func isInMenuBar(_ command: ExtensionCommand) -> Bool {
        settings.menuBarCommands.contains(command.id)
    }

    /// Gives a menu-bar command its status item, or takes it away again.
    func toggleMenuBarCommand(_ command: ExtensionCommand) {
        if settings.menuBarCommands.remove(command.id) != nil {
            showHUD("Removed from Menu Bar")
        } else {
            settings.menuBarCommands.insert(command.id)
            showHUD("Added to Menu Bar")
        }
        refresh()
    }

    /// True when a command can run unattended: no missing required preferences or arguments.
    func canRunUnattended(_ command: ExtensionCommand) -> Bool {
        PreferenceStore.missingRequired(for: command).isEmpty
            && command.arguments.allSatisfy { !$0.required }
    }

    /// Construction never scans: without a snapshot the model starts with the built-in entries only,
    /// and `startCatalogLoading()` fills in the rest once the UI is wired up.
    init(
        scanner: any CatalogScanning = CatalogLoader(),
        settings: AppSettings = .shared,
        usage: UsageStore = .shared,
        snapshot: CatalogSnapshot? = nil
    ) {
        self.scanner = scanner
        self.settings = settings
        self.usage = usage
        if let snapshot {
            apps = snapshot.apps
            allCommands = snapshot.commands
            allScripts = snapshot.scripts
            scriptFailures = snapshot.scriptFailures
            settingsPanes = snapshot.settingsPanes
            hasLoadedApps = true
            hasLoadedCommands = true
            hasLoadedScripts = true
            isLoadingCatalog = false
        }
        EmojiCatalog.preload()
        CalendarAgenda.shared.onChange = { [weak self] in self?.refresh() }
        refresh()
    }

    /// Kicks off the initial scans in the worker. Called after the panel and its subscriptions exist,
    /// so their publications are heard from the start.
    func startCatalogLoading() {
        reloadApps()
        reloadCommands()
        reloadScripts()
        Task { [weak self, scanner] in
            let panes = await scanner.scanSettingsPanes()
            await self?.finishSettingsPanes(panes)
        }
    }

    @MainActor
    private func finishSettingsPanes(_ panes: [SystemSettingsPane]) {
        settingsPanes = panes
        // Nothing to redraw without a query: the panes are only searched for.
        if !query.isEmpty {
            refresh()
        }
    }

    func reloadCommands() {
        commandsGeneration += 1
        let generation = commandsGeneration
        // Read once, here: the worker never sees the mutable settings object.
        let includeRaycast = settings.includeRaycastExtensions
        isLoadingCatalog = true
        commandsTask = Task { [weak self, scanner] in
            let commands = await scanner.scanCommands(includeRaycast: includeRaycast)
            await self?.finishCommands(generation: generation, commands: commands)
        }
    }

    func reloadScripts() {
        scriptsGeneration += 1
        let generation = scriptsGeneration
        isLoadingCatalog = true
        scriptsTask = Task { [weak self, scanner] in
            let scan = await scanner.scanScripts()
            await self?.finishScripts(generation: generation, scan: scan)
        }
    }

    /// Publication happens on the main actor; a stale generation is dropped without touching state,
    /// so rescans keep the previous results visible while they run.
    @MainActor
    private func finishScripts(generation: Int, scan: ScriptScan) {
        guard generation == scriptsGeneration else { return }
        scriptsTask = nil
        hasLoadedScripts = true
        isLoadingCatalog = !hasLoadedApps || !hasLoadedCommands || !hasLoadedScripts
        allScripts = scan.commands
        scriptFailures = scan.failures
        refresh()
    }

    /// Joins the script scan in flight, following any newer request that replaces it while the
    /// caller waits.
    @MainActor
    func waitForScripts() async {
        while let task = scriptsTask {
            await task.value
        }
    }

    /// Publication happens on the main actor; a stale generation is dropped without touching state,
    /// so rescans keep the previous results visible while they run.
    @MainActor
    private func finishApps(generation: Int, apps newApps: [AppEntry]) {
        guard generation == appsGeneration else { return }
        appsTask = nil
        hasLoadedApps = true
        isLoadingCatalog = !hasLoadedApps || !hasLoadedCommands || !hasLoadedScripts
        apps = newApps
        refresh()
    }

    @MainActor
    private func finishCommands(generation: Int, commands newCommands: [ExtensionCommand]) {
        guard generation == commandsGeneration else { return }
        commandsTask = nil
        hasLoadedCommands = true
        isLoadingCatalog = !hasLoadedApps || !hasLoadedCommands || !hasLoadedScripts
        allCommands = newCommands
        refresh()
    }

    /// Joins the command scan in flight, following any newer request that replaces it while the
    /// caller waits. Suspending leaves the main actor free, and results are published before the
    /// joined task finishes, so a caller that returns sees the current catalog or nothing pending.
    @MainActor
    func waitForCommands() async {
        while let task = commandsTask {
            await task.value
        }
    }

    private func refresh() {
        selection = 0
        var all = commands.map(RootItem.command) + allScripts.map(RootItem.script) + apps.map(RootItem.app)
            + [RootItem.menuBarSearch, RootItem.emojiSearch, RootItem.clipboardHistory, RootItem.fileSearch, RootItem.settings]
            + SystemCommand.allCases.map(RootItem.system) + SnippetStore.shared.snippets.map(RootItem.snippet)
            + settings.notesApp.actions.map { RootItem.note($0, text: "") } + Thaw.actions().map(RootItem.thaw)
        let frecency = { [usage] (id: String) in usage.frecency(of: id) }
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        let links = QuicklinkStore.shared.links
        let panes = settingsPanes.map(RootItem.settingsPane)
        if query.isEmpty {
            results = Ranking.browse(all, searchOnly: panes, favorites: settings.favorites, frecency: frecency)
        } else {
            all += panes
            // Quicklink names and keywords rank alongside everything else, through the keyword alias.
            if !trimmed.isEmpty {
                all += links.map { RootItem.quicklink($0, queryText: trimmed, fallback: false, keywordSearch: false) }
            }
            // A script matches when the query starts with its title and the rest is its arguments.
            let scriptHits = allScripts.compactMap { script -> RootItem? in
                guard script.argumentsText(in: query) != nil else { return nil }
                return .script(script)
            }
            let searched = Ranking.search(all, query: query, favorites: settings.favorites, alias: alias(for:), frecency: frecency)
            let hitIDs = Set(scriptHits.map(\.id))
            results = scriptHits.map { RootResult(item: $0, section: nil) } + searched.filter { !hitIDs.contains($0.item.id) }
            if let answer = Calculator.evaluate(query) {
                results.insert(RootResult(item: .calculator(answer), section: "Calculator"), at: 0)
            }
            // `keyword rest` searches that link first: `gh floe` offers Search GitHub for "floe" first.
            if !trimmed.isEmpty, let keywordResult = Self.keywordSearchResult(query: trimmed, links: links) {
                results.removeAll { $0.id == keywordResult.id }
                results.insert(keywordResult, at: 0)
            }
            // `note buy milk` leads with the note it would make.
            if let note = Notes.request(in: trimmed, app: settings.notesApp) {
                let row = RootResult(item: .note(note.action, text: note.text), section: nil)
                results.removeAll { $0.id == row.id }
                results.insert(row, at: 0)
            }
            // Enabled fallbacks in user order at the bottom.
            if !trimmed.isEmpty {
                results += links.filter(\.isFallback).map { link in
                    RootResult(item: .quicklink(link, queryText: trimmed, fallback: true, keywordSearch: false), section: "Fallbacks")
                }
            }
        }
        let agenda = CalendarAgenda.shared.events(matching: query)
        if !agenda.isEmpty {
            let today = agenda.filter { Calendar.current.isDateInToday($0.startDate) }
            let tomorrow = agenda.filter { !Calendar.current.isDateInToday($0.startDate) }
            let rows = today.map { RootResult(item: .event($0), section: "Today") }
                + tomorrow.map { RootResult(item: .event($0), section: "Tomorrow") }
            results.insert(contentsOf: rows, at: 0)
        }
        if query.hasPrefix(":") {
            let matches = EmojiCatalog.search(
                term: String(query.dropFirst()),
                frecency: { [usage] in usage.frecency(of: EmojiResult.id(for: $0)) }
            )
            results.insert(
                contentsOf: matches.map { RootResult(item: .emoji($0), section: "Emoji & Symbols") },
                at: 0
            )
        }
        if !query.isEmpty {
            results.append(RootResult(item: .searchFiles(query), section: nil))
        }
    }

    /// The `keyword rest` row for a query starting with a quicklink's keyword and a space, if any.
    private static func keywordSearchResult(query: String, links: [Quicklink]) -> RootResult? {
        guard let match = links.first(where: { query.hasPrefix($0.keyword + " ") }) else { return nil }
        let rest = String(query.dropFirst(match.keyword.count + 1))
        return RootResult(item: .quicklink(match, queryText: rest, fallback: false, keywordSearch: true), section: nil)
    }

    func alias(for item: RootItem) -> String? {
        if case let .quicklink(link, _, _, _) = item {
            return link.keyword
        }
        return item.settingsKey.flatMap { settings.aliases[$0] }.flatMap { $0.isEmpty ? nil : $0 }
    }

    func isFavorite(_ item: RootItem) -> Bool {
        settings.favorites.contains(item.id)
    }

    func toggleFavorite(_ item: RootItem) {
        if case .searchFiles = item {
            // The fallback row names a query, not a thing: it has no favorites entry.
            return
        }
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
        appsGeneration += 1
        let generation = appsGeneration
        isLoadingCatalog = true
        appsTask = Task { [weak self, scanner] in
            let apps = await scanner.scanApps()
            await self?.finishApps(generation: generation, apps: apps)
        }
    }

    /// `FLOE_AUTORUN=extension/command` opens a command at startup, for screenshots and debugging.
    /// It waits for the command load that is current when it runs and attempts the command once;
    /// later rescans never rerun it.
    func autorun(
        target: String? = ProcessInfo.processInfo.environment["FLOE_AUTORUN"],
        launch: ((ExtensionCommand) -> Void)? = nil
    ) {
        Task { @MainActor [weak self] in
            await self?.waitForCommands()
            guard let self, !didAutorun else { return }
            didAutorun = true
            guard let target, let command = commands.first(where: { $0.id == target }) else { return }
            if let launch {
                launch(command)
            } else {
                run(command)
            }
        }
    }

    func activate(_ item: RootItem) {
        if case let .calculator(answer) = item {
            NSPasteboard.general.copy(answer.copyText)
            showHUD("Copied \(answer.copyText)")
            return
        }
        if case let .emoji(entry) = item {
            pasteEmojiResult(entry)
            return
        }
        if case .searchFiles = item {
            // A transient row for the query text: opening it records no frecency entry.
        } else {
            usage.recordUse(of: item.id)
        }
        switch item {
        case let .app(app):
            NSWorkspace.shared.open(app.url)
            hidePanel()
            reset()
        case let .command(command):
            run(command)
        case let .script(script):
            let text = script.argumentsText(in: query) ?? ""
            run(script, argumentStrings: ScriptRunner.splitArguments(text))
        case .menuBarSearch:
            openMenuBarSearch()
        case .emojiSearch:
            query = ":"
            focusToken += 1
        case .clipboardHistory:
            openClipboardHistory()
        case .fileSearch:
            openFileSearch(with: query)
        case let .searchFiles(searchQuery):
            openFileSearch(with: searchQuery)
        case .settings:
            hidePanel()
            openSettings(nil)
        case let .quicklink(link, queryText, _, _):
            if let destination = url(for: link, query: queryText) {
                NSWorkspace.shared.open(destination)
            }
            hidePanel()
            reset()
        case let .system(command):
            runSystemCommand(command)
        case let .note(action, text):
            hidePanel()
            reset()
            Notes.perform(action, text: text, app: settings.notesApp, template: settings.notesURLTemplate) { [weak self] message in
                if let message {
                    self?.showHUD(message)
                }
            }
        case let .thaw(action):
            hidePanel()
            reset()
            if !Thaw.perform(action) {
                showHUD("Thaw isn't installed")
            }
        case let .settingsPane(pane):
            if let url = pane.url {
                NSWorkspace.shared.open(url)
            }
            hidePanel()
            reset()
        case let .snippet(snippet):
            paste(text: SnippetStore.shared.expanded(snippet))
        case let .event(event):
            if let destination = event.meetingURL ?? event.calendarURL {
                NSWorkspace.shared.open(destination)
            }
            hidePanel()
            reset()
        case .calculator, .emoji:
            break
        }
    }

    /// Risky commands ask first; the panel goes away before anything runs.
    private func runSystemCommand(_ command: SystemCommand) {
        hidePanel()
        reset()
        if let question = command.confirmation {
            guard Confirm.destructive(command.title, detail: question, button: command.title) else { return }
        }
        if let flip = command.flip {
            showHUD(flip())
            return
        }
        command.perform()
    }

    /// Copies an emoji without pasting; ⌘↵ on a result.
    func copyEmojiResult(_ entry: EmojiResult) {
        usage.recordUse(of: EmojiResult.id(for: entry.character))
        NSPasteboard.general.copy(entry.character)
        showHUD("Copied \(entry.character)")
    }

    /// Pastes an emoji into the frontmost app: onto the clipboard plus a ⌘V once the panel is
    /// gone, when Accessibility access is granted; otherwise the copy plus a "Copied" HUD.
    func pasteEmojiResult(_ entry: EmojiResult) {
        usage.recordUse(of: EmojiResult.id(for: entry.character))
        NSPasteboard.general.copy(entry.character)
        guard AXIsProcessTrusted() else {
            showHUD("Copied")
            return
        }
        hidePanel()
        reset()
        // Pressed once the panel is gone, so the keystroke lands in the app the user came from.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
            let source = CGEventSource(stateID: .hidSystemState)
            let down = CGEvent(keyboardEventSource: source, virtualKey: 0x09, keyDown: true)
            down?.flags = .maskCommand
            let up = CGEvent(keyboardEventSource: source, virtualKey: 0x09, keyDown: false)
            up?.flags = .maskCommand
            down?.post(tap: .cghidEventTap)
            up?.post(tap: .cghidEventTap)
        }
    }

    // MARK: Menu bar items

    /// Switches the panel to the menu bar item search and rescans the menu bar.
    func openMenuBarSearch() {
        if let session {
            end(session)
        }
        setup = nil
        isShowingClipboardHistory = false
        isSearchingMenuBar = true
        if !settings.rememberMenuBarQuery {
            menuBarQuery = ""
        }
        showPanel()
        focusToken += 1
        scanMenuBar()
    }

    func closeMenuBarSearch() {
        isSearchingMenuBar = false
        focusToken += 1
    }

    // MARK: Clipboard history

    /// Switches the panel to the clipboard history.
    func openClipboardHistory() {
        if let session {
            end(session)
        }
        setup = nil
        isSearchingMenuBar = false
        isShowingClipboardHistory = true
        clipboardQuery = ""
        clipboardSelection = 0
        showPanel()
        focusToken += 1
    }

    func closeClipboardHistory() {
        isShowingClipboardHistory = false
        focusToken += 1
    }

    /// History entries matching the clipboard query, pins first, then newest first.
    func filteredClipboardEntries() -> [ClipboardEntry] {
        let entries = ClipboardHistoryStore.shared.entries
        let tokens = clipboardQuery.lowercased().split(separator: " ")
        let matching = tokens.isEmpty ? entries : entries.filter { entry in
            let haystack = "\(entry.title) \(entry.text ?? "") \((entry.filePaths ?? []).joined(separator: " ")) \(entry.sourceApp ?? "")".lowercased()
            return tokens.allSatisfy { haystack.contains($0) }
        }
        return matching.sorted { lhs, rhs in
            if lhs.pinned != rhs.pinned {
                return lhs.pinned
            }
            return lhs.date > rhs.date
        }
    }

    var selectedClipboardEntry: ClipboardEntry? {
        let entries = filteredClipboardEntries()
        return entries.indices.contains(clipboardSelection) ? entries[clipboardSelection] : nil
    }

    /// Copies the entry, then pastes with Command-V when Accessibility allows it.
    func pasteClipboardEntry(_ entry: ClipboardEntry) {
        usage.recordUse(of: RootItem.clipboardHistory.id)
        guard ClipboardHistoryStore.writeToPasteboard(entry) else { return }
        hidePanel()
        reset()
        if ClipboardHistoryStore.canPasteDirectly {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                ClipboardHistoryStore.simulatePaste()
            }
        } else {
            showHUD("Copied. Press ⌘V to paste.")
        }
    }

    func copyClipboardEntry(_ entry: ClipboardEntry) {
        guard ClipboardHistoryStore.writeToPasteboard(entry) else { return }
        showHUD("Copied")
    }

    func deleteClipboardEntry(_ entry: ClipboardEntry) {
        ClipboardHistoryStore.shared.delete(entry)
        clipboardSelection = max(0, min(clipboardSelection, filteredClipboardEntries().count - 1))
    }

    func toggleClipboardPin(_ entry: ClipboardEntry) {
        ClipboardHistoryStore.shared.togglePin(entry)
    }

    // MARK: File search

    /// Switches the panel to the file search, starting with the given text.
    func openFileSearch(with text: String) {
        if let session {
            end(session)
        }
        setup = nil
        isSearchingFiles = true
        fileSearchQuery = text
        showPanel()
        focusToken += 1
    }

    func closeFileSearch() {
        isSearchingFiles = false
        fileSearch.cancel()
        focusToken += 1
    }

    var selectedFile: FileResult? {
        fileSearch.results.indices.contains(fileSearchSelection) ? fileSearch.results[fileSearchSelection] : nil
    }

    func openSelectedFile() {
        guard let file = selectedFile else { return }
        fileSearch.open(file)
        hidePanel()
        reset()
    }

    func revealSelectedFile() {
        guard let file = selectedFile else { return }
        fileSearch.reveal(file)
        hidePanel()
        reset()
    }

    func copySelectedFilePath() {
        guard let file = selectedFile else { return }
        NSPasteboard.general.copy(file.url.path)
        showHUD("Copied")
    }

    private func scanMenuBar() {
        menuBarAccessGranted = MenuBarExtras.isTrusted
        guard menuBarAccessGranted else {
            menuBarExtras = []
            refreshMenuBar()
            return
        }
        isScanningMenuBar = menuBarExtras.isEmpty
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let extras = MenuBarExtras.scan()
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                menuBarExtras = extras
                isScanningMenuBar = false
                refreshMenuBar()
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
                Ranking.menuBarScore(query: query, name: displayName(for: extra), owner: extra.ownerName).map { (extra, $0) }
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
    func menuBarActions(for extra: MenuBarExtra) -> [ItemAction?] {
        var actions: [ItemAction?] = [
            ItemAction(title: "Click Item", symbol: "cursorarrow.click") { [weak self] in self?.openMenuBarExtra(extra) },
            ItemAction(title: "Edit Name", symbol: "pencil") { [weak self] in self?.beginRenamingSelection() },
            ItemAction(title: "Copy Name", symbol: "doc.on.doc") { [weak self] in
                guard let self else { return }
                NSPasteboard.general.copy(displayName(for: extra))
                showHUD("Copied \(displayName(for: extra))")
            },
        ]
        if settings.menuBarItemNames[extra.id] != nil {
            actions.append(ItemAction(title: "Restore Original Name", symbol: "arrow.uturn.backward") { [weak self] in
                self?.settings.menuBarItemNames[extra.id] = nil
                self?.refreshMenuBar()
            })
        }
        if let url = extra.ownerURL {
            actions.append(nil)
            actions.append(ItemAction(title: "Open \(extra.ownerName)", symbol: "app") { [weak self] in
                NSWorkspace.shared.open(url)
                self?.hidePanel()
            })
            actions.append(ItemAction(title: "Show \(extra.ownerName) in Finder", symbol: "folder") { [weak self] in
                NSWorkspace.shared.activateFileViewerSelecting([url])
                self?.hidePanel()
            })
        }
        return actions
    }

    func openMenuBarExtra(_ extra: MenuBarExtra) {
        menuBarRecents.record(extra.id)
        hidePanel()
        reset()
        // Pressed once the panel is gone, so the menu opens over the app the user came from.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { MenuBarExtras.open(extra) }
    }

    /// Runs a script command with the given argv. Arguments come from the text typed after its
    /// title; output follows its mode: a window for fullOutput, a HUD for compact and inline,
    /// nothing for silent. Failures show a HUD with the last stderr line.
    func run(_ script: ScriptCommand, argumentStrings: [String] = []) {
        if script.needsConfirmation {
            let alert = NSAlert()
            alert.messageText = "Run \(script.title)?"
            alert.informativeText = script.displayPackage
            alert.addButton(withTitle: "Run")
            alert.addButton(withTitle: "Cancel")
            guard alert.runModal() == .alertFirstButtonReturn else { return }
        }
        usage.recordUse(of: RootItem.script(script).id)
        hidePanel()
        reset()
        Task { [weak self] in
            let result: ShellResult
            do {
                result = try await ScriptRunner.run(script, arguments: argumentStrings)
            } catch {
                await MainActor.run { [weak self] in
                    self?.showHUD("\(script.title) failed: \(error.localizedDescription)")
                }
                return
            }
            await MainActor.run { [weak self] in
                guard let self else { return }
                guard result.succeeded else {
                    let line = ScriptRunner.lastLine(result.errorOutput) ?? ScriptRunner.lastLine(result.output)
                        ?? "exit code \(result.status)"
                    showHUD("\(script.title) failed: \(line)")
                    return
                }
                switch script.mode {
                case .silent:
                    break
                case .inline, .compact:
                    let line = ScriptRunner.lastLine(result.output) ?? "Done"
                    showHUD(line)
                case .fullOutput:
                    ScriptOutputWindow.show(title: script.title, output: result.trimmedOutput)
                }
            }
        }
    }

    /// Runs a command, first asking for missing required preferences and then for its arguments.
    func run(_ command: ExtensionCommand, arguments: [String: Any]? = nil) {
        let missing = PreferenceStore.missingRequired(for: command)
        // Running a menu-bar command is choosing whether it has a status item.
        if command.mode == "menu-bar", missing.isEmpty {
            toggleMenuBarCommand(command)
            return
        }
        if let session {
            end(session)
        }
        if !missing.isEmpty {
            beginSetup(SetupRequest(command: command, kind: .preferences, fields: command.preferences))
        } else if arguments == nil, !command.arguments.isEmpty {
            beginSetup(SetupRequest(command: command, kind: .arguments, fields: command.arguments))
        } else {
            if command.mode == "view" {
                showPanel()
            }
            launch(command, arguments: arguments ?? [:])
        }
    }

    private func beginSetup(_ request: SetupRequest) {
        var values: [String: String] = [:]
        for field in request.fields {
            let scope = request.command.commandPreferences.contains { $0.name == field.name } ? request.command : nil
            let stored = request.kind == .preferences
                ? PreferenceStore.value(field, extensionName: request.command.extensionName, command: scope)
                : nil
            values[field.name] = FieldValues.initialText(for: field, stored: stored)
        }
        setupValues = values
        setupError = nil
        setup = request
        showPanel()
        focusToken += 1
    }

    func submitSetup() {
        guard let request = setup else { return }
        let missing = FieldValues.missing(request.fields, texts: setupValues)
        guard missing.isEmpty else {
            setupError = "Fill in \(missing.map(\.title).joined(separator: ", "))."
            return
        }
        let values = FieldValues.typed(setupValues, fields: request.fields)
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

    private func launch(_ command: ExtensionCommand, arguments: [String: Any]) {
        let session = ExtensionSession(command: command, arguments: arguments)
        session.onMessage = { [weak self, weak session] message in
            guard let self, let session else { return }
            self.handle(message, from: session)
        }
        self.session = session
        session.start()
        sourceWatcher = HotReload.watcher(for: command) { [weak self, weak session] paths in
            guard let self, let session else { return }
            self.reload(session, changed: paths)
        }
    }

    /// A file of the open command's extension was saved: runs the command again as `retry` does.
    /// A panel that is hidden while its command waits to be resumed stays hidden.
    private func reload(_ watched: ExtensionSession, changed paths: [String]) {
        guard session === watched else { return }
        if HotReload.changesManifest(paths) {
            reloadCommands()
        }
        if pendingReset == nil {
            retry()
        } else {
            end(watched)
            launch(watched.command, arguments: watched.arguments)
        }
    }

    private func handle(_ message: [String: Any], from session: ExtensionSession) {
        switch message["type"] as? String {
        case "exit", "popToRoot":
            let wasBackground = session.command.mode != "view"
            end(session)
            if wasBackground {
                hidePanel()
            }
        case "crashed" where session.command.mode != "view":
            end(session)
            showHUD("\(session.command.title) failed")
        case "close":
            hidePanel()
        case "hud":
            showHUD(message["title"] as? String ?? "")
            hidePanel()
        case "copy":
            copy(text: message["text"] as? String ?? "", html: message["html"] as? String, file: message["file"] as? String)
        case "paste":
            paste(text: message["text"] as? String ?? "", html: message["html"] as? String, file: message["file"] as? String)
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
            sourceWatcher = nil
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
        reloadScripts()
    }

    /// Runs the command that failed again, with the same arguments.
    func retry() {
        guard let session else { return }
        let command = session.command
        let arguments = session.arguments
        end(session)
        run(command, arguments: arguments)
    }

    func copyFailure() {
        guard let session, let failure = session.failure else { return }
        copy(text: "\(session.command.extensionTitle) › \(session.command.title)\n\(failure.message)\n\n\(failure.details)")
        showHUD("Copied error details")
    }

    /// Back to the root search, ending any open command.
    func reset() {
        pendingReset?.cancel()
        pendingReset = nil
        if let session {
            end(session)
        }
        setup = nil
        isSearchingMenuBar = false
        isShowingClipboardHistory = false
        isSearchingFiles = false
        fileSearch.cancel()
        query = ""
    }

    private func copy(text: String, html: String? = nil, file: String? = nil) {
        PasteboardContent.write(text: text, html: html, file: file)
    }

    private func paste(text: String, html: String? = nil, file: String? = nil) {
        PasteboardContent.write(text: text, html: html, file: file)
        if AXIsProcessTrusted() {
            hidePanel()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                KeySimulation.paste()
            }
        } else {
            showHUD("Copied. Press ⌘V to paste.")
            hidePanel()
        }
    }

    /// Handles `open`, `copy`, `paste` and `hud` from sessions the panel doesn't own (menu-bar extras,
    /// background runs). Background runs never open the panel.
    func handleBackgroundMessage(_ message: [String: Any]) {
        switch message["type"] as? String {
        case "hud":
            showHUD(message["title"] as? String ?? "")
        case "copy":
            copy(text: message["text"] as? String ?? "", html: message["html"] as? String, file: message["file"] as? String)
        case "paste":
            // A background run never takes the keyboard from the user; it only copies.
            copy(text: message["text"] as? String ?? "", html: message["html"] as? String, file: message["file"] as? String)
            showHUD("Copied. Press ⌘V to paste.")
        case "open":
            open(message["target"] as? String ?? "", application: message["application"] as? String)
        default:
            break
        }
    }

    private func open(_ target: String, application: String?) {
        let url = URL(string: target).flatMap { $0.scheme == nil ? nil : $0 }
            ?? URL(fileURLWithPath: (target as NSString).expandingTildeInPath)
        if let application, let app = applicationURL(for: application) {
            NSWorkspace.shared.open([url], withApplicationAt: app, configuration: NSWorkspace.OpenConfiguration())
        } else {
            NSWorkspace.shared.open(url)
        }
    }

    /// Extensions name an app by path, bundle identifier or display name.
    private func applicationURL(for application: String) -> URL? {
        if (application as NSString).isAbsolutePath {
            return URL(fileURLWithPath: application)
        }
        return NSWorkspace.shared.urlForApplication(withBundleIdentifier: application)
            ?? apps.first { $0.name.caseInsensitiveCompare(application) == .orderedSame }?.url
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
            showActions()
            return true
        }
        if isSearchingMenuBar {
            if let delta = Shortcuts.navigationDelta(event.keyCode) {
                menuBarSelection = max(0, min(menuBarSelection + delta, menuBarResults.count - 1))
                return true
            }
            switch event.keyCode {
            case 36, 76:
                if menuBarResults.indices.contains(menuBarSelection) {
                    openMenuBarExtra(menuBarResults[menuBarSelection].extra)
                }
            case 53:
                if menuBarQuery.isEmpty {
                    closeMenuBarSearch()
                } else {
                    menuBarQuery = ""
                }
            default: return false
            }
            return true
        }
        if let session, session.command.mode == "view", session.alert != nil {
            switch event.keyCode {
            case 36, 76: session.resolveAlert(true)
            case 53: session.resolveAlert(false)
            default: return false
            }
            return true
        }
        if isShowingClipboardHistory {
            if let delta = Shortcuts.navigationDelta(event.keyCode) {
                let count = filteredClipboardEntries().count
                clipboardSelection = max(0, min(clipboardSelection + delta, count - 1))
                return true
            }
            switch event.keyCode {
            case 36, 76:
                if let entry = selectedClipboardEntry {
                    pasteClipboardEntry(entry)
                }
            case 51:
                if let entry = selectedClipboardEntry {
                    deleteClipboardEntry(entry)
                }
            case 53:
                if clipboardQuery.isEmpty {
                    closeClipboardHistory()
                } else {
                    clipboardQuery = ""
                }
            default: return false
            }
            return true
        }
        if isSearchingFiles {
            if let delta = Shortcuts.navigationDelta(event.keyCode) {
                fileSearchSelection = max(0, min(fileSearchSelection + delta, fileSearch.results.count - 1))
                return true
            }
            switch event.keyCode {
            case 36 where flags == .command, 76 where flags == .command:
                revealSelectedFile()
            case 36, 76:
                openSelectedFile()
            case 53:
                if fileSearchQuery.isEmpty {
                    closeFileSearch()
                } else {
                    fileSearchQuery = ""
                }
            case 8 where flags == [.command, .shift]:
                copySelectedFilePath()
            case 40 where flags == .command:
                showActions()
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
        if let delta = Shortcuts.navigationDelta(event.keyCode) {
            selection = max(0, min(selection + delta, results.count - 1))
            return true
        }
        switch event.keyCode {
        case 36: if results.indices.contains(selection) {
                let item = results[selection].item
                if case let .emoji(entry) = item, flags == .command {
                    copyEmojiResult(entry)
                } else {
                    activate(item)
                }
            }
        case 53: if query.isEmpty {
                hidePanel()
            } else {
                query = ""
            }
        case 3 where flags == [.command, .shift]:
            if results.indices.contains(selection) {
                toggleFavorite(results[selection].item)
            }
        case 40 where flags == .command:
            showActions()
        default: return false
        }
        return true
    }

    private func handleSessionKey(_ event: NSEvent, _ flags: NSEvent.ModifierFlags, _ session: ExtensionSession) -> Bool {
        let actions = session.actions
        // In a form, arrows and Return belong to the fields; ⌘↵ submits.
        if session.view?.type == "Form", !session.actionMenuOpen {
            switch event.keyCode {
            case 125, 126: return false
            case 36 where flags != .command: return false
            case 36:
                if let action = actions.first {
                    session.run(action)
                }
                return true
            default: break
            }
        }
        if session.actionMenuOpen, handleActionMenuKey(event, flags, session) {
            return true
        }
        if let delta = Shortcuts.navigationDelta(event.keyCode) {
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
            if actions.indices.contains(index) {
                session.run(actions[index])
            }
        case 40 where flags == .command:
            session.actionMenuOpen = true
        default:
            guard !flags.isEmpty, let action = actions.first(where: { Shortcuts.matches($0.props["shortcut"], key: event.charactersIgnoringModifiers, flags: flags) }) else { return false }
            session.run(action)
        }
        return true
    }

    /// While the action menu is open, typing searches it, ↵ runs or opens a submenu, ← and Esc step back.
    private func handleActionMenuKey(_ event: NSEvent, _ flags: NSEvent.ModifierFlags, _ session: ExtensionSession) -> Bool {
        if let delta = Shortcuts.navigationDelta(event.keyCode) {
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
        case 51: if !session.actionQuery.isEmpty {
                session.actionQuery.removeLast()
            }
        default:
            // Plain typing (Shift allowed) filters; anything with ⌘, ⌃ or ⌥ falls through to shortcuts.
            guard flags.subtracting(.shift).isEmpty, let characters = event.characters,
                  !characters.isEmpty, characters.unicodeScalars.allSatisfy({ !CharacterSet.controlCharacters.contains($0) })
            else {
                return false
            }
            session.actionQuery += characters
        }
        return true
    }
}
