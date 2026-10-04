//
//  MenuBarCommands.swift
//  Project: Floe
//
//  Copyright (Floe) © 2026 René Jiménez
//  Licensed under the GNU AGPLv3

import AppKit
import Combine

/// The part of a status item a menu-bar command uses; tests stand in for it.
@MainActor protocol MenuBarStatusItem: AnyObject {
    var statusButton: (any MenuBarStatusButton)? { get }
    var menu: NSMenu? { get set }
}

extension NSStatusItem: MenuBarStatusItem {
    var statusButton: (any MenuBarStatusButton)? {
        button
    }
}

/// What menu-bar commands need from the system: the menu bar, extension hosts and icon files.
@MainActor struct MenuBarHost {
    var addItem: () -> any MenuBarStatusItem = { NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength) }
    var removeItem: (any MenuBarStatusItem) -> Void = { item in
        if let item = item as? NSStatusItem {
            NSStatusBar.system.removeStatusItem(item)
        }
    }

    var start: (ExtensionSession) -> Void = { $0.start() }
    var resolver: (_ assetsPath: String) -> MenuBarIconResolver = { MenuBarIconResolver.system(assetsPath: $0) }
    var icons = IconThumbnailCache.shared
}

/// One menu-bar command's status item and its running session.
@MainActor final class MenuBarCommands {
    private let model: LauncherModel
    private let host: MenuBarHost
    private let images: MenuBarIconImages
    private var entries: [String: Entry] = [:]

    private final class Entry {
        let item: any MenuBarStatusItem
        let presenter: MenuBarPresenter
        var command: ExtensionCommand
        var session: ExtensionSession?
        var cancellables = Set<AnyCancellable>()
        init(item: any MenuBarStatusItem, presenter: MenuBarPresenter, command: ExtensionCommand) {
            self.item = item
            self.presenter = presenter
            self.command = command
        }
    }

    init(model: LauncherModel, host: MenuBarHost? = nil) {
        let host = host ?? MenuBarHost()
        self.model = model
        self.host = host
        self.images = MenuBarIconImages(cache: host.icons)
    }

    func presenter(for id: String) -> MenuBarPresenter? {
        entries[id]?.presenter
    }

    func session(for id: String) -> ExtensionSession? {
        entries[id]?.session
    }

    /// Keeps one status item plus one running session per enabled menu-bar command.
    func sync(_ commands: [ExtensionCommand]) {
        let wanted = commands.filter { $0.mode == "menu-bar" }
        let ids = Set(wanted.map(\.id))
        for id in entries.keys where !ids.contains(id) {
            remove(id)
        }
        for command in wanted {
            if let entry = entries[command.id] {
                entry.command = command
                entry.presenter.commandTitle = command.title
            } else {
                start(command)
            }
        }
    }

    /// Stops and restarts one command's session, for interval refreshes. The status item stays and
    /// shows the last render until the new session has one, so the menu bar does not blink each time.
    func refresh(_ command: ExtensionCommand) {
        guard let entry = entries[command.id] else { return }
        entry.command = command
        entry.presenter.commandTitle = command.title
        run(entry)
    }

    func stopAll() {
        for id in entries.keys {
            remove(id)
        }
    }

    private func start(_ command: ExtensionCommand) {
        let item = host.addItem()
        let resolver = host.resolver
        let presenter = MenuBarPresenter(button: item.statusButton, commandTitle: command.title, images: images) { [weak self] in
            resolver(self?.entries[command.id]?.command.assetsPath ?? command.assetsPath)
        }
        let entry = Entry(item: item, presenter: presenter, command: command)
        entry.presenter.onAction = { [weak entry] nodeID in
            guard let session = entry?.session, let node = session.root?.descendant(id: nodeID) else { return }
            session.event(node, "onAction", [["type": "left-click"]])
        }
        entry.presenter.onRetry = { [weak self, weak entry] in
            guard let self, let entry else { return }
            // Asked for by hand, so the menu says it is loading instead of showing what failed.
            entry.presenter.show(root: nil)
            run(entry)
        }
        entry.presenter.onRemove = { [weak self, weak entry] in
            guard let self, let entry else { return }
            model.toggleMenuBarCommand(entry.command)
        }
        item.menu = entry.presenter.menu
        entries[command.id] = entry
        run(entry)
    }

    /// Gives the entry a fresh session, ending the one it had.
    private func run(_ entry: Entry) {
        entry.cancellables.removeAll()
        entry.session?.forceStop()
        let session = ExtensionSession(command: entry.command, launchType: "background")
        session.onMessage = { [weak self] message in
            self?.model.handleBackgroundMessage(message)
        }
        let presenter = entry.presenter
        presenter.show(failure: nil)
        // Published in willSet, so the value handed over is the new one while the property is still the old.
        // The first value is the empty state every session starts in, which is not a render.
        session.$root.dropFirst().sink { [weak presenter] in presenter?.show(root: $0) }.store(in: &entry.cancellables)
        session.$failure.dropFirst().sink { [weak presenter] in presenter?.show(failure: $0) }.store(in: &entry.cancellables)
        entry.session = session
        host.start(session)
    }

    private func remove(_ id: String) {
        guard let entry = entries.removeValue(forKey: id) else { return }
        entry.cancellables.removeAll()
        entry.session?.forceStop()
        entry.session = nil
        entry.item.menu = nil
        host.removeItem(entry.item)
    }
}
