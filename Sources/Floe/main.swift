//
//  main.swift
//  Project: Floe
//
//  Copyright (Floe) © 2026 René Jiménez
//  Licensed under the GNU GPLv3

import AppKit
import Combine
import CryptoKit
import SwiftUI

final class LauncherPanel: NSPanel {
    override var canBecomeKey: Bool { true }
}

final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    private let model = LauncherModel()
    private var panel: LauncherPanel!
    private var hud: NSPanel?
    private let hotkeys = HotkeyRegistry()
    private let settings = AppSettings.shared
    private lazy var settingsWindow = SettingsWindowController(model: model)
    private var cancellables = Set<AnyCancellable>()
    private var statusItem: NSStatusItem?
    private var showItem: NSMenuItem?
    private var appWatcher: AppFolderWatcher?

    func applicationDidFinishLaunching(_: Notification) {
        NSApp.setActivationPolicy(.accessory)

        panel = LauncherPanel(contentRect: NSRect(x: 0, y: 0, width: 750, height: 474),
                              styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.level = .floating
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.delegate = self
        panel.contentView = NSHostingView(rootView: LauncherView(model: model))

        model.hidePanel = { [weak self] in self?.hide() }
        model.showPanel = { [weak self] in self?.show() }
        model.showHUD = { [weak self] in self?.showHUD($0) }
        model.openSettings = { [weak self] in self?.settingsWindow.show(extensionName: $0) }

        NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self, self.panel.isKeyWindow else { return event }
            return self.model.handleKey(event) ? nil : event
        }

        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        item.button?.image = NSImage(systemSymbolName: "command.square", accessibilityDescription: "Floe")
        let menu = NSMenu()
        showItem = menu.addItem(withTitle: "Show Floe", action: #selector(show), keyEquivalent: "")
        showItem?.target = self
        menu.addItem(withTitle: "About Floe", action: #selector(openAbout), keyEquivalent: "").target = self
        menu.addItem(withTitle: "Settings…", action: #selector(openSettings), keyEquivalent: ",").target = self
        menu.addItem(.separator())
        menu.addItem(withTitle: "Quit", action: #selector(NSApplication.terminate), keyEquivalent: "q")
        item.menu = menu
        statusItem = item

        appWatcher = AppFolderWatcher { [weak self] in self?.model.reloadApps() }
        settings.$toggleHotkey.combineLatest(settings.$commandHotkeys, model.$allCommands, model.$apps)
            .sink { [weak self] _, _, _, _ in DispatchQueue.main.async { self?.registerHotkeys() } }
            .store(in: &cancellables)
        // Thaw's inspector panel is 600 × 400; the launcher needs room for extension detail panes.
        model.$isSearchingMenuBar.removeDuplicates()
            .sink { [weak self] inspector in self?.resizePanel(to: inspector ? NSSize(width: 600, height: 400) : NSSize(width: 750, height: 474)) }
            .store(in: &cancellables)
        settings.$isRecordingHotkey
            .sink { [weak self] in self?.hotkeys.isSuspended = $0 }
            .store(in: &cancellables)
        settings.$includeRaycastExtensions.dropFirst()
            .sink { [weak self] _ in DispatchQueue.main.async { self?.model.reloadCommands() } }
            .store(in: &cancellables)

        show()
        model.autorun()
    }

    /// The launcher hotkey plus one per command that has a hotkey assigned.
    private func registerHotkeys() {
        hotkeys.unregisterAll()
        if let toggleHotkey = settings.toggleHotkey {
            _ = hotkeys.register(toggleHotkey) { [weak self] in self?.toggle() }
        }
        showItem?.title = settings.toggleHotkey.map { "Show Floe (\($0.displayValue))" } ?? "Show Floe"
        for command in model.allCommands {
            guard let keyCombination = settings.commandHotkeys[command.id] else { continue }
            _ = hotkeys.register(keyCombination) { [weak self] in
                guard let self, !settings.disabledExtensions.contains(command.extensionName) else { return }
                UsageStore.shared.recordUse(of: RootItem.command(command).id)
                model.run(command)
            }
        }
        if let keyCombination = settings.commandHotkeys[RootItem.menuBarSearchKey] {
            _ = hotkeys.register(keyCombination) { [weak self] in self?.model.openMenuBarSearch() }
        }
        for app in model.apps {
            guard let key = RootItem.app(app).settingsKey, let keyCombination = settings.commandHotkeys[key] else { continue }
            _ = hotkeys.register(keyCombination) { [weak self] in self?.model.toggleApp(app) }
        }
    }

    @objc private func openAbout() {
        hide()
        settingsWindow.show(page: .about)
    }

    @objc private func openSettings() {
        hide()
        settingsWindow.show()
    }

    func applicationWillTerminate(_: Notification) {
        model.session?.forceStop()
    }

    /// Keeps the panel's top edge and horizontal center where they are.
    private func resizePanel(to size: NSSize) {
        let frame = panel.frame
        guard frame.size != size else { return }
        panel.setFrame(NSRect(x: frame.midX - size.width / 2, y: frame.maxY - size.height, width: size.width, height: size.height),
                       display: true)
    }

    private func toggle() {
        panel.isVisible ? hide() : show()
    }

    @objc private func show() {
        guard !panel.isVisible || !panel.isKeyWindow else { return }
        let screen = NSScreen.screens.first { $0.frame.contains(NSEvent.mouseLocation) } ?? NSScreen.main
        if let frame = screen?.visibleFrame {
            panel.setFrameOrigin(NSPoint(x: frame.midX - panel.frame.width / 2,
                                         y: frame.minY + frame.height * 0.62 - panel.frame.height / 2))
        }
        model.panelWillShow()
        panel.makeKeyAndOrderFront(nil)
        model.focusToken += 1
    }

    private func hide() {
        guard panel.isVisible else { return }
        panel.orderOut(nil)
        model.panelDidHide()
    }

    func windowDidResignKey(_: Notification) {
        // Checked a turn later, once focus has settled; an open file panel keeps the launcher up.
        DispatchQueue.main.async { [self] in
            if ProcessInfo.processInfo.environment["FLOE_DEBUG"] != nil {
                let front = NSWorkspace.shared.frontmostApplication?.localizedName ?? "?"
                FileHandle.standardError.write("resignKey: key=\(String(describing: NSApp.keyWindow)) frontmost=\(front)\n".data(using: .utf8)!)
            }
            if !ModalGuard.isActive, !panel.isKeyWindow { hide() }
        }
    }

    private func showHUD(_ text: String) {
        hud?.orderOut(nil)
        let view = NSHostingView(rootView: HUDView(text: text))
        let size = view.fittingSize
        let hud = NSPanel(contentRect: NSRect(origin: .zero, size: size), styleMask: [.borderless, .nonactivatingPanel],
                          backing: .buffered, defer: false)
        hud.level = .statusBar
        hud.isOpaque = false
        hud.backgroundColor = .clear
        hud.ignoresMouseEvents = true
        hud.contentView = view
        if let frame = NSScreen.main?.visibleFrame {
            hud.setFrameOrigin(NSPoint(x: frame.midX - size.width / 2, y: frame.minY + 80))
        }
        hud.orderFrontRegardless()
        self.hud = hud
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.6) { [weak self, weak hud] in
            hud?.orderOut(nil)
            if self?.hud === hud { self?.hud = nil }
        }
    }
}

/// `Floe --selftest <extension> <command>` runs a command without UI and reports the first list it renders.
func runSelfTest(extensionName: String, commandName: String) -> Never {
    guard let command = ExtensionCommand.scan().first(where: { $0.extensionName == extensionName && $0.name == commandName }) else {
        print("SELFTEST FAIL: no command \(extensionName)/\(commandName)")
        exit(1)
    }
    let missing = PreferenceStore.missingRequired(for: command).map(\.name)
    if !missing.isEmpty { print("SELFTEST missing required preferences: \(missing)") }
    let session = ExtensionSession(command: command)
    session.onMessage = { print("SELFTEST message:", $0["type"] ?? "?") }
    let observer = session.objectWillChange.sink { _ in
        DispatchQueue.main.async {
            if let failure = session.failure {
                print("SELFTEST FAILURE: kind=\(failure.kind) message=\(failure.message.debugDescription) logLines=\(failure.details.split(separator: "\n").count)")
                session.forceStop()
                exit(0)
            }
            if let toast = session.toast, toast.style == "failure" { print("SELFTEST TOAST: \(toast.title): \(toast.message ?? "")") }
            let rows = session.rows
            let markdown = session.view?.type == "Detail" ? session.view?.string("markdown") : nil
            guard rows.first != nil || markdown != nil else { return }
            let actions = session.actions.compactMap { $0.string("title") }.joined(separator: " | ")
            let summary = markdown.map { "markdown=\($0.prefix(60).debugDescription)" }
                ?? "rows=\(rows.count) first=\"\(rows[0].node.string("title") ?? "")\""
            print("SELFTEST OK: view=\(session.view?.type ?? "?") \(summary) actions=[\(actions)]")
            let describe = { (entries: [ExtensionSession.MenuEntry]) in
                entries.map { "\($0.section.map { "[\($0)] " } ?? "")\($0.node.string("title") ?? "?")\($0.isSubmenu ? " ›" : "")" }.joined(separator: ", ")
            }
            print("SELFTEST MENU: \(describe(session.menuEntries))")
            if let submenu = session.menuEntries.first(where: \.isSubmenu) {
                session.openSubmenu(submenu.node)
                print("SELFTEST SUBMENU: \(describe(session.menuEntries))")
                session.closeSubmenuOrMenu()
            }
            session.actionQuery = "copy"
            print("SELFTEST MENU SEARCH copy: \(describe(session.menuEntries))")
            session.forceStop()
            exit(0)
        }
    }
    session.start()
    DispatchQueue.main.asyncAfter(deadline: .now() + 20) {
        print("SELFTEST FAIL: timed out; view=\(session.view?.type ?? "none") toast=\(session.toast?.title ?? "none")")
        session.forceStop()
        exit(1)
    }
    withExtendedLifetime(observer) { RunLoop.main.run() }
    exit(1)
}

LegacyDefaults.migrate()
Paths.prepareSupportFolders()

let arguments = CommandLine.arguments
// `Floe --search <query>` prints the ranked root results, for checking aliases and ranking.
if let flag = arguments.firstIndex(of: "--search"), arguments.count > flag + 1 {
    let model = LauncherModel()
    model.query = arguments[flag + 1]
    for result in model.results.prefix(8) {
        print("\(result.section.map { "[\($0)] " } ?? "")\(result.item.title) (\(result.item.kind))\(model.alias(for: result.item).map { " (alias \($0))" } ?? "")")
    }
    exit(0)
}
// `Floe --bench-settings` times laying out each settings page off screen, to catch slow page switches.
if arguments.contains("--bench-settings") {
    _ = NSApplication.shared
    let model = LauncherModel()
    let selection = SettingsSelection()
    let window = NSWindow(contentRect: NSRect(x: -4000, y: -4000, width: 820, height: 560), styleMask: [.titled], backing: .buffered, defer: false)
    window.contentView = NSHostingView(rootView: SettingsView(model: model, settings: .shared, selection: selection))
    window.orderFrontRegardless()
    let pages: [(String, SettingsPage)] = [("general", .general), ("applications", .applications), ("about", .about), ("extension", .extensionPage("kill-process"))]
    for (name, page) in pages {
        let start = Date()
        selection.page = page
        // Let SwiftUI process the change, then force layout and drawing.
        RunLoop.main.run(until: Date().addingTimeInterval(0.05))
        window.contentView?.layoutSubtreeIfNeeded()
        window.displayIfNeeded()
        print("BENCH \(name): \(Int(Date().timeIntervalSince(start) * 1000 - 50)) ms")
        // FLOE_BENCH_DUMP=<folder> saves what each page looks like.
        if let directory = ProcessInfo.processInfo.environment["FLOE_BENCH_DUMP"], let view = window.contentView,
           let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) {
            view.cacheDisplay(in: view.bounds, to: rep)
            try? rep.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: directory).appendingPathComponent("\(name).png"))
        }
    }
    exit(0)
}
// `Floe --icon-check` renders each command's icon off screen and prints a fingerprint and how much of it is drawn,
// so mixed-up or invisible icons show up without opening the window. FLOE_ICON_DUMP=<folder> also writes the PNGs.
if arguments.contains("--icon-check") {
    _ = NSApplication.shared
    let samples: [(String, Any, String)] = ExtensionCommand.scan().reduce(into: []) { result, command in
        guard !result.contains(where: { $0.0 == command.extensionName }) else { return }
        result.append((command.extensionName, command.icon ?? "", command.assetsPath))
    } + [("kill-process accessory", ["source": "cpu.svg", "tintColor": "color:PrimaryText"], ExtensionCommand.scan().first { $0.extensionName == "kill-process" }?.assetsPath ?? "")]
    MainActor.assumeIsolated {
        for (name, value, assets) in samples {
            let renderer = ImageRenderer(content: IconView(value: value, assetsPath: assets, size: 32).environment(\.colorScheme, .dark))
            renderer.scale = 1
            guard let image = renderer.cgImage, let data = image.dataProvider?.data as Data? else { print("\(name): no image"); continue }
            // A pixel counts as drawn when any of its four bytes is set, whatever the channel order.
            let pixels = stride(from: 0, to: data.count - 3, by: 4).filter { data[$0] | data[$0 + 1] | data[$0 + 2] | data[$0 + 3] > 8 }.count
            let digest = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined().prefix(8)
            if let directory = ProcessInfo.processInfo.environment["FLOE_ICON_DUMP"] {
                let png = NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:])
                try? png?.write(to: URL(fileURLWithPath: directory).appendingPathComponent("\(name).png"))
            }
            print("\(name.padding(toLength: 24, withPad: " ", startingAt: 0)) sha=\(digest) drawn=\(pixels * 100 / max(1, data.count / 4))%")
        }
    }
    exit(0)
}
// `Floe --menubar [query]` lists the menu bar items Floe can open, ranked as the menu bar search would.
if let flag = arguments.firstIndex(of: "--menubar") {
    let query = arguments.count > flag + 1 ? arguments[flag + 1] : ""
    let extras = MenuBarExtras.scan()
    print("MENUBAR trusted=\(MenuBarExtras.isTrusted) items=\(extras.count)")
    let ranked = query.isEmpty ? extras : extras.filter { Fuzzy.score(query, $0.name) != nil || Fuzzy.score(query, $0.ownerName) != nil }
    let previews = MenuBarPreviews()
    previews.capture(extras)
    RunLoop.main.run(until: Date().addingTimeInterval(3))
    for extra in ranked.prefix(30) {
        print("  \(extra.name) (\(extra.ownerName)) at \(Int(extra.frame.minX)),\(Int(extra.frame.minY)) preview=\(previews.images[extra.id] != nil)")
    }
    exit(0)
}
// `Floe --panel-snapshot <folder>` draws the launcher's root and menu bar views off screen and saves them.
if let flag = arguments.firstIndex(of: "--panel-snapshot"), arguments.count > flag + 1 {
    _ = NSApplication.shared
    let folder = URL(fileURLWithPath: arguments[flag + 1])
    let model = LauncherModel()
    let window = NSWindow(contentRect: NSRect(x: -4000, y: -4000, width: 750, height: 474), styleMask: [.borderless], backing: .buffered, defer: false)
    window.contentView = NSHostingView(rootView: LauncherView(model: model))
    window.orderFrontRegardless()
    func snapshot(_ name: String, wait: TimeInterval = 1) {
        RunLoop.main.run(until: Date().addingTimeInterval(wait))
        guard let view = window.contentView, let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { return }
        view.cacheDisplay(in: view.bounds, to: rep)
        try? rep.representation(using: .png, properties: [:])?.write(to: folder.appendingPathComponent("\(name).png"))
        print("SNAPSHOT \(name)")
    }
    model.query = "co"
    snapshot("root")
    model.openMenuBarSearch()
    window.setContentSize(NSSize(width: 600, height: 400))
    snapshot("menubar", wait: 5)
    exit(0)
}
if let flag = arguments.firstIndex(of: "--selftest"), arguments.count > flag + 2 {
    runSelfTest(extensionName: arguments[flag + 1], commandName: arguments[flag + 2])
}

let delegate = AppDelegate()
NSApplication.shared.delegate = delegate
NSApplication.shared.run()
