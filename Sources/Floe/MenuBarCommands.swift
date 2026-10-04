//
//  MenuBarCommands.swift
//  Project: Floe
//
//  Copyright (Floe) © 2026 René Jiménez
//  Licensed under the GNU AGPLv3

import AppKit
import Combine
import SwiftUI

/// One menu-bar command's status item and its running session.
@MainActor final class MenuBarCommands {
    private let model: LauncherModel
    private var entries: [String: Entry] = [:]

    private final class Entry {
        let item: NSStatusItem
        var command: ExtensionCommand
        var session: ExtensionSession
        var cancellables = Set<AnyCancellable>()
        let dispatch = MenuDispatch()
        init(item: NSStatusItem, command: ExtensionCommand, session: ExtensionSession) {
            self.item = item
            self.command = command
            self.session = session
        }
    }

    private final class MenuDispatch: NSObject {
        var onAction: ((Int) -> Void)?
        var onRetry: (() -> Void)?
        @objc func fire(_ sender: NSMenuItem) {
            onAction?(sender.tag)
        }

        @objc func retry(_: NSMenuItem) {
            onRetry?()
        }
    }

    init(model: LauncherModel) {
        self.model = model
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
                rebuild(command.id)
            } else {
                start(command)
            }
        }
    }

    /// Stops and restarts one command's session, for interval refreshes.
    func refresh(_ command: ExtensionCommand) {
        guard entries[command.id] != nil else { return }
        remove(command.id)
        start(command)
    }

    func stopAll() {
        for id in entries.keys {
            remove(id)
        }
    }

    private func start(_ command: ExtensionCommand) {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.button?.title = command.title
        let session = ExtensionSession(command: command, launchType: "background")
        let entry = Entry(item: item, command: command, session: session)
        entry.dispatch.onAction = { [weak self, weak session] nodeID in
            guard let session, let node = Self.find(id: nodeID, in: session.root) else { return }
            session.event(node, "onAction", [["type": "left-click"]])
            self?.rebuild(command.id)
        }
        entry.dispatch.onRetry = { [weak self] in self?.refresh(command) }
        session.onMessage = { [weak self] message in
            self?.model.handleBackgroundMessage(message)
        }
        session.$root.sink { [weak self] _ in self?.rebuild(command.id) }.store(in: &entry.cancellables)
        session.$failure.sink { [weak self] _ in self?.rebuild(command.id) }.store(in: &entry.cancellables)
        entries[command.id] = entry
        session.start()
        rebuild(command.id)
    }

    private func remove(_ id: String) {
        guard let entry = entries.removeValue(forKey: id) else { return }
        entry.cancellables.removeAll()
        entry.session.forceStop()
        NSStatusBar.system.removeStatusItem(entry.item)
    }

    private func rebuild(_ id: String) {
        guard let entry = entries[id] else { return }
        let session = entry.session
        let extra = session.root?.descendants(ofType: "MenuBarExtra").first
        if let tooltip = extra?.string("tooltip") {
            entry.item.button?.toolTip = tooltip
        }
        let title = extra?.string("title")
        entry.item.button?.title = title ?? ""
        if let icon = extra?.props["icon"], let image = statusImage(icon, assetsPath: entry.command.assetsPath) {
            image.size = NSSize(width: 16, height: 16)
            entry.item.button?.image = image
        } else {
            entry.item.button?.image = nil
        }
        if entry.item.button?.title.isEmpty == true, entry.item.button?.image == nil {
            entry.item.button?.title = entry.command.title
        }
        let menu = NSMenu()
        if let failure = session.failure {
            let message = NSMenuItem(title: failure.message, action: nil, keyEquivalent: "")
            message.isEnabled = false
            menu.addItem(message)
            let retry = NSMenuItem(title: "Try Again", action: #selector(MenuDispatch.retry(_:)), keyEquivalent: "")
            retry.target = entry.dispatch
            menu.addItem(retry)
        } else if let extra {
            let children = extra.content
            if extra.bool("isLoading"), children.isEmpty {
                let loading = NSMenuItem(title: "Loading…", action: nil, keyEquivalent: "")
                loading.isEnabled = false
                menu.addItem(loading)
            } else {
                addNodes(children, to: menu, entry: entry)
                if menu.numberOfItems == 0 {
                    let empty = NSMenuItem(title: entry.command.title, action: nil, keyEquivalent: "")
                    empty.isEnabled = false
                    menu.addItem(empty)
                }
            }
        } else {
            let loading = NSMenuItem(title: "Loading…", action: nil, keyEquivalent: "")
            loading.isEnabled = false
            menu.addItem(loading)
        }
        entry.item.menu = menu
    }

    private func addNodes(_ nodes: [Node], to menu: NSMenu, entry: Entry) {
        for child in nodes {
            switch child.type {
            case "MenuBarExtra.Item":
                menu.addItem(makeItem(child, entry: entry))
            case "MenuBarExtra.Separator":
                menu.addItem(.separator())
            case "MenuBarExtra.Section":
                if menu.numberOfItems > 0 {
                    menu.addItem(.separator())
                }
                menu.addItem(NSMenuItem.sectionHeader(title: child.string("title") ?? ""))
                addNodes(child.content, to: menu, entry: entry)
            case "MenuBarExtra.Submenu":
                let sub = NSMenuItem(title: child.string("title") ?? "", action: nil, keyEquivalent: "")
                let submenu = NSMenu()
                addNodes(child.content, to: submenu, entry: entry)
                sub.submenu = submenu
                if let icon = child.props["icon"] {
                    sub.image = statusImage(icon, assetsPath: entry.command.assetsPath)
                }
                menu.addItem(sub)
            default:
                break
            }
        }
    }

    private func makeItem(_ node: Node, entry: Entry) -> NSMenuItem {
        let item = NSMenuItem(title: node.string("title") ?? "", action: nil, keyEquivalent: "")
        if let subtitle = node.string("subtitle") {
            item.subtitle = subtitle
        }
        if let tooltip = node.string("tooltip") {
            item.toolTip = tooltip
        }
        if let icon = node.props["icon"] {
            item.image = statusImage(icon, assetsPath: entry.command.assetsPath)
        }
        if node.handlers.contains("onAction") {
            item.target = entry.dispatch
            item.action = #selector(MenuDispatch.fire(_:))
            item.tag = node.id
        } else {
            item.isEnabled = false
        }
        return item
    }

    /// Maps an icon value the way IconView does: SF Symbols stay templates, asset files load
    /// directly, anything fancier renders through IconView at 16pt.
    private func statusImage(_ value: Any?, assetsPath: String) -> NSImage? {
        if let dict = value as? [String: Any] {
            if let path = dict["fileIcon"] as? String {
                return NSWorkspace.shared.icon(forFile: path)
            }
            if let source = dict["source"] as? [String: Any] {
                let dark = NSApp.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
                return statusImage(dark ? source["dark"] ?? source["light"] : source["light"] ?? source["dark"], assetsPath: assetsPath)
            }
            return statusImage(dict["source"] ?? dict["value"], assetsPath: assetsPath)
        }
        guard let string = value as? String, !string.isEmpty else { return nil }
        if string.hasPrefix("icon:") {
            let name = String(string.dropFirst(5))
            let dotted = name.replacing(#/([a-z0-9])([A-Z])/#) { "\($0.1).\($0.2)" }.lowercased()
            for candidate in [dotted, name.lowercased()] {
                if let image = NSImage(systemSymbolName: candidate, accessibilityDescription: nil) {
                    image.isTemplate = true
                    return image
                }
            }
        }
        if let path = assetPath(string, assetsPath: assetsPath), let image = NSImage(contentsOfFile: path) {
            return image
        }
        let renderer = ImageRenderer(content: IconView(value: value, assetsPath: assetsPath, size: 16))
        renderer.scale = 2
        guard let cg = renderer.cgImage else { return nil }
        let image = NSImage(cgImage: cg, size: NSSize(width: 16, height: 16))
        image.isTemplate = string.hasPrefix("icon:")
        return image
    }

    private static func find(id: Int, in node: Node?) -> Node? {
        guard let node else { return nil }
        if node.id == id {
            return node
        }
        for child in node.children {
            if let found = find(id: id, in: child) {
                return found
            }
        }
        return nil
    }

    private func assetPath(_ name: String, assetsPath: String) -> String? {
        let path = name.hasPrefix("/") ? name : "\(assetsPath)/\(name)"
        if NSApp.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua {
            let url = URL(fileURLWithPath: path)
            let dark = url.deletingPathExtension().path + "@dark." + url.pathExtension
            if FileManager.default.fileExists(atPath: dark) {
                return dark
            }
        }
        return FileManager.default.fileExists(atPath: path) ? path : nil
    }
}
