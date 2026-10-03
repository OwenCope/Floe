//
//  Session.swift
//  Project: Floe
//
//  Copyright (Floe) © 2026 René Jiménez
//  Licensed under the GNU GPLv3

import Foundation

/// Why a command can't show its view: it threw, it crashed, or it stopped answering.
struct SessionFailure: Equatable {
    enum Kind { case error, crashed, unresponsive }
    let kind: Kind
    let message: String
    let details: String
}

struct ToastState: Equatable {
    let id: Int
    let style: String
    let title: String
    let message: String?
}

/// One running extension command: a Bun process speaking NDJSON over stdin/stdout.
final class ExtensionSession: ObservableObject {
    let command: ExtensionCommand
    let arguments: [String: Any]
    @Published private(set) var root: Node?
    /// Form field values by field id. Dates are kept as ISO 8601 strings.
    @Published var formValues: [String: Any] = [:]
    @Published var toast: ToastState?
    @Published private(set) var failure: SessionFailure?
    @Published var selection = 0
    @Published var actionMenuOpen = false {
        didSet {
            actionQuery = ""
            actionPath = []
            actionSelection = 0
        }
    }
    @Published var actionSelection = 0
    /// Typed while the action menu is open; filters every action, submenus included.
    @Published var actionQuery = "" { didSet { actionSelection = 0 } }
    /// Open submenus, outermost first.
    @Published private(set) var actionPath: [Node] = []
    /// Recomputed only when the tree or the search text changes, not on every redraw.
    @Published private(set) var rows: [Row] = []
    @Published var searchText = "" {
        didSet {
            guard searchText != oldValue else { return }
            selection = 0
            recomputeRows()
            if !suppressSearchEvent, let view, view.handlers.contains("onSearchTextChange") {
                event(view, "onSearchTextChange", [searchText])
            }
        }
    }

    /// Messages the session does not handle itself: close, exit, popToRoot, hud, open, copy, paste.
    var onMessage: ([String: Any]) -> Void = { _ in
        // Set by the model.
    }

    private let process = Process()
    private let input = Pipe()
    private let output = Pipe()
    private let errors = Pipe()
    private var buffer = Data()
    /// The tail of the host's stderr, shown on the error screen.
    private(set) var log = ""
    private var isStopping = false
    private var watchdog: Timer?
    private var pingSentAt: Date?
    private var suppressSearchEvent = false

    init(command: ExtensionCommand, arguments: [String: Any] = [:]) {
        self.command = command
        self.arguments = arguments
    }

    func start() {
        guard let bun = Paths.bun else {
            toast = ToastState(id: 0, style: "failure", title: "Bun isn't installed", message: "brew install bun")
            return
        }
        process.executableURL = URL(fileURLWithPath: bun)
        let argumentsJSON = (try? JSONSerialization.data(withJSONObject: arguments)).flatMap { String(data: $0, encoding: .utf8) } ?? "{}"
        process.arguments = [Paths.host.path, command.extensionDir.path, command.name, argumentsJSON]
        // Preferences go through the environment so the host has them before the command's first line runs.
        var environment = ProcessInfo.processInfo.environment
        if let data = try? JSONSerialization.data(withJSONObject: PreferenceStore.resolvedValues(for: command)) {
            environment["FLOE_PREFERENCES"] = String(data: data, encoding: .utf8)
        }
        process.environment = environment
        process.standardInput = input
        process.standardOutput = output
        process.standardError = errors
        output.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            guard !data.isEmpty else { return }
            DispatchQueue.main.async { self?.receive(data) }
        }
        errors.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            guard !data.isEmpty else { return }
            FileHandle.standardError.write(data)
            DispatchQueue.main.async { self?.appendLog(data) }
        }
        process.terminationHandler = { [weak self] process in
            let status = process.terminationStatus
            let reason = process.terminationReason
            DispatchQueue.main.async { self?.processEnded(status: status, reason: reason) }
        }
        do {
            try process.run()
            startWatchdog()
        } catch {
            failure = SessionFailure(kind: .error, message: "The extension couldn't start.", details: error.localizedDescription)
        }
    }

    private func appendLog(_ data: Data) {
        log += String(decoding: data, as: UTF8.self)
        if log.count > 20_000 { log = String(log.suffix(16_000)) }
    }

    /// Exit status 0 is a normal finish; anything else, or a signal, is a crash unless we asked it to stop.
    private func processEnded(status: Int32, reason: Process.TerminationReason) {
        watchdog?.invalidate()
        guard !isStopping else { return }
        if status == 0, reason == .exit {
            onMessage(["type": "exit"])
        } else if failure == nil {
            let how = reason == .uncaughtSignal ? "was killed by signal \(status)" : "exited with status \(status)"
            failure = SessionFailure(kind: .crashed, message: "The extension stopped unexpectedly. It \(how).", details: log)
            onMessage(["type": "crashed"])
        }
    }

    /// Pings every few seconds; a host that hasn't answered in 8 seconds is reported as not responding.
    private func startWatchdog() {
        watchdog = Timer.scheduledTimer(withTimeInterval: 3, repeats: true) { [weak self] _ in
            guard let self, process.isRunning else { return }
            if let sent = pingSentAt {
                if Date().timeIntervalSince(sent) > 8, failure == nil {
                    failure = SessionFailure(kind: .unresponsive, message: "The extension isn't responding.", details: log)
                }
                return
            }
            pingSentAt = Date()
            send(["type": "ping"])
        }
    }

    /// Stops the process, optionally after a grace period so trailing messages still arrive.
    func stop(after delay: TimeInterval = 0) {
        isStopping = true
        watchdog?.invalidate()
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [self] in
            output.fileHandleForReading.readabilityHandler = nil
            errors.fileHandleForReading.readabilityHandler = nil
            if process.isRunning { process.terminate() }
            // A host stuck in synchronous code ignores SIGTERM.
            DispatchQueue.main.asyncAfter(deadline: .now() + 1) { [self] in
                if process.isRunning { kill(process.processIdentifier, SIGKILL) }
            }
        }
    }

    /// Kills the process now, for app quit and the self-test, where nothing waits for a grace period.
    func forceStop() {
        isStopping = true
        watchdog?.invalidate()
        if process.isRunning { kill(process.processIdentifier, SIGKILL) }
    }

    func send(_ message: [String: Any]) {
        guard process.isRunning, var data = try? JSONSerialization.data(withJSONObject: message) else { return }
        data.append(0x0A)
        try? input.fileHandleForWriting.write(contentsOf: data)
    }

    func event(_ node: Node, _ prop: String, _ args: [Any] = []) {
        send(["type": "event", "id": node.id, "prop": prop, "args": args])
    }

    private func receive(_ data: Data) {
        buffer.append(data)
        while let newline = buffer.firstIndex(of: 0x0A) {
            let line = buffer.subdata(in: buffer.startIndex..<newline)
            buffer.removeSubrange(buffer.startIndex...newline)
            if let message = try? JSONSerialization.jsonObject(with: line) as? [String: Any] { handle(message) }
        }
    }

    private func handle(_ message: [String: Any]) {
        switch message["type"] as? String {
        case "render":
            let previousScreen = screen?.id
            root = Node(json: message["tree"])
            recomputeRows()
            // Keep the open submenu only while it still exists.
            if let open = actionPath.last, actionPanel?.descendants(ofType: "ActionPanel.Submenu").contains(where: { $0.id == open.id }) != true {
                actionPath = []
            }
            if screen?.id != previousScreen {
                formValues = [:]
                suppressSearchEvent = true
                searchText = ""
                suppressSearchEvent = false
                selection = 0
                actionMenuOpen = false
            }
        case "toast":
            let id = message["id"] as? Int ?? 0
            if message["hidden"] as? Bool == true {
                if toast?.id == id { toast = nil }
            } else {
                let state = ToastState(id: id, style: message["style"] as? String ?? "success",
                                       title: message["title"] as? String ?? "", message: message["message"] as? String)
                toast = state
                guard state.style != "animated" else { return }
                DispatchQueue.main.asyncAfter(deadline: .now() + 3) { [weak self] in
                    if self?.toast == state { self?.toast = nil }
                }
            }
        case "error":
            let text = message["message"] as? String ?? "Unknown error"
            if message["fatal"] as? Bool == true {
                let details = [message["stack"] as? String, log.isEmpty ? nil : log].compactMap { $0 }.joined(separator: "\n\n")
                failure = SessionFailure(kind: .error, message: text, details: details)
            } else {
                toast = ToastState(id: -1, style: "failure", title: "Extension error", message: text)
            }
        case "pong":
            pingSentAt = nil
            if failure?.kind == .unresponsive { failure = nil }
        case "clearSearchBar":
            searchText = ""
        default:
            onMessage(message)
        }
    }

    // MARK: Derived view state

    var screen: Node? { root?.children.last { $0.type == "_screen" } }
    var view: Node? { screen?.content.first }
    var isList: Bool { view?.type == "List" || view?.type == "Grid" }

    private func recomputeRows() {
        rows = computeRows()
    }

    private func computeRows() -> [Row] {
        guard let view, isList else { return [] }
        var rows: [Row] = []
        for child in view.content {
            if child.type.hasSuffix(".Section") {
                rows += child.content.filter { $0.type.hasSuffix(".Item") }.map { Row(node: $0, sectionTitle: child.string("title")) }
            } else if child.type.hasSuffix(".Item") {
                rows.append(Row(node: child, sectionTitle: nil))
            }
        }
        let filtersLocally: Bool
        if let filtering = view.props["filtering"] as? Bool { filtersLocally = filtering }
        else if view.props["filtering"] != nil { filtersLocally = true }
        else { filtersLocally = !view.handlers.contains("onSearchTextChange") }
        let tokens = searchText.lowercased().split(separator: " ")
        guard filtersLocally, !tokens.isEmpty else { return rows }
        return rows.filter { row in
            let keywords = (row.node.props["keywords"] as? [String] ?? []).joined(separator: " ")
            let haystack = "\(row.node.string("title") ?? "") \(row.node.string("subtitle") ?? "") \(keywords)".lowercased()
            return tokens.allSatisfy { haystack.contains($0) }
        }
    }

    var selectedRow: Row? {
        let rows = rows
        return rows.isEmpty ? nil : rows[min(selection, rows.count - 1)]
    }

    /// The action panel for what's selected: the row's, else the empty view's, else the view's own.
    var actionPanel: Node? {
        guard let view else { return nil }
        return isList
            ? selectedRow?.node.slot("actions") ?? view.content.first { $0.type == "EmptyView" }?.slot("actions") ?? view.slot("actions")
            : view.slot("actions")
    }

    /// Every action, flattened; ↵ runs the first and ⌘↵ the second, as in Raycast.
    var actions: [Node] {
        actionPanel?.descendants(ofType: "Action") ?? []
    }

    struct MenuEntry: Identifiable {
        let node: Node
        let section: String?
        var isSubmenu: Bool { node.type == "ActionPanel.Submenu" }
        var id: Int { node.id }
    }

    /// What the action menu lists: the open submenu or the whole panel, with section titles; a search
    /// looks through everything, submenus included.
    var menuEntries: [MenuEntry] {
        guard let container = actionPath.last ?? actionPanel else { return [] }
        if !actionQuery.isEmpty {
            let query = actionQuery.lowercased()
            return container.descendants(ofType: "Action")
                .filter { ($0.string("title") ?? "").lowercased().contains(query) }
                .map { MenuEntry(node: $0, section: nil) }
        }
        var entries: [MenuEntry] = []
        func collect(_ node: Node, section: String?) {
            for child in node.content {
                switch child.type {
                case "ActionPanel.Section": collect(child, section: child.string("title") ?? "")
                case "Action", "ActionPanel.Submenu": entries.append(MenuEntry(node: child, section: section))
                default: collect(child, section: section)
                }
            }
        }
        collect(container, section: nil)
        return entries
    }

    func openSubmenu(_ submenu: Node) {
        if submenu.handlers.contains("onOpen") { event(submenu, "onOpen") }
        actionPath.append(submenu)
        actionQuery = ""
        actionSelection = 0
    }

    /// Esc and ← step out of a submenu before closing the menu.
    func closeSubmenuOrMenu() {
        if !actionQuery.isEmpty {
            actionQuery = ""
        } else if actionPath.isEmpty {
            actionMenuOpen = false
        } else {
            actionPath.removeLast()
            actionSelection = 0
        }
    }

    func activateMenuEntry(at index: Int) {
        let entries = menuEntries
        guard entries.indices.contains(index) else { return }
        if entries[index].isSubmenu { openSubmenu(entries[index].node) } else { run(entries[index].node) }
    }

    func run(_ action: Node) {
        actionMenuOpen = false
        if action.bool("isSubmit") {
            if action.handlers.contains("onSubmit") { event(action, "onSubmit", [submittedFormValues]) }
        } else if action.handlers.contains("onAction") {
            event(action, "onAction")
        }
    }

    // MARK: Forms

    var formFields: [Node] {
        guard let view, view.type == "Form" else { return [] }
        return view.content.filter { $0.props["id"] is String }
    }

    /// The field's current value: the extension's controlled `value`, else what was typed, else its default.
    func formValue(_ field: Node) -> Any? {
        guard let id = field.props["id"] as? String else { return nil }
        if let value = field.props["value"] ?? formValues[id] ?? field.props["defaultValue"] { return value }
        // Like Raycast, a dropdown with nothing chosen shows (and submits) its first item.
        if field.type == "Form.Dropdown" { return field.descendants(ofType: "Dropdown.Item").first?.props["value"] }
        return nil
    }

    func setFormValue(_ field: Node, _ value: Any) {
        guard let id = field.props["id"] as? String else { return }
        formValues[id] = value
        if field.handlers.contains("onChange") { event(field, "onChange", [Self.wireValue(value, field: field)]) }
    }

    /// Values keyed by field id, as Raycast hands them to onSubmit.
    private var submittedFormValues: [String: Any] {
        var values: [String: Any] = [:]
        for field in formFields {
            guard let id = field.props["id"] as? String else { continue }
            let value = formValue(field) ?? Self.emptyValue(for: field.type)
            values[id] = Self.wireValue(value, field: field)
        }
        return values
    }

    static func emptyValue(for type: String) -> Any {
        switch type {
        case "Form.Checkbox": false
        case "Form.TagPicker", "Form.FilePicker": [String]()
        case "Form.DatePicker": NSNull()
        default: ""
        }
    }

    /// Dates cross the bridge tagged so the host can turn them back into Date objects.
    private static func wireValue(_ value: Any, field: Node) -> Any {
        if field.type == "Form.DatePicker", let iso = value as? String { return ["$date": iso] }
        return value
    }

    /// Moves within the action menu when it's open, else the list; large steps stop at the ends.
    func moveSelection(by delta: Int) {
        if actionMenuOpen {
            actionSelection = Self.clamp(actionSelection + delta, menuEntries.count)
        } else {
            selection = Self.clamp(min(selection, rows.count - 1) + delta, rows.count)
        }
    }

    private static func clamp(_ index: Int, _ count: Int) -> Int {
        max(0, min(index, count - 1))
    }
}
