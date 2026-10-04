//
//  ItemActions.swift
//  Project: Floe
//
//  Copyright (Floe) © 2026 René Jiménez
//  Licensed under the GNU AGPLv3

import Algorithms
import AppKit
import SwiftUI

/// One row of an Actions menu. In a list of them, nil is a separator.
struct ItemAction {
    let title: String
    let symbol: String
    /// Drawn instead of the symbol, for a row that stands for an app.
    var icon: NSImage?
    /// A row with children opens a submenu and does nothing itself.
    var children: [ItemAction] = []
    var run: () -> Void = { /* a submenu's title */ }
}

/// What an action needs from the launcher around it.
struct ActionHost {
    let showHUD: (String) -> Void
    /// Hides the panel and returns it to the root, as opening a result does.
    let dismiss: () -> Void
}

enum ActionsMenu {
    static func menu(_ actions: [ItemAction?]) -> NSMenu {
        let menu = NSMenu()
        for action in actions {
            guard let action else {
                menu.addItem(.separator())
                continue
            }
            let item = ClosureMenuItem(title: action.title, handler: action.run)
            item.image = action.icon ?? NSImage(systemSymbolName: action.symbol, accessibilityDescription: nil)
            if !action.children.isEmpty {
                item.submenu = Self.menu(action.children)
            }
            menu.addItem(item)
        }
        return menu
    }
}

/// An empty AppKit view behind an Actions button, for NSMenu.popUp to position against. While it
/// is on screen, the model's `showActions` pops this view's menu.
struct ActionsAnchor: NSViewRepresentable {
    let model: LauncherModel
    let actions: (LauncherModel) -> [ItemAction?]

    func makeNSView(context _: Context) -> NSView {
        let view = NSView()
        register(view)
        return view
    }

    func updateNSView(_ nsView: NSView, context _: Context) {
        register(nsView)
    }

    private func register(_ view: NSView) {
        model.showActions = { [weak view, weak model, actions] in
            guard let view, let model else { return }
            let list = actions(model)
            guard !list.isEmpty else { return }
            // The panel would read the menu's tracking as losing focus and close under it.
            _ = ModalGuard.run {
                ActionsMenu.menu(list).popUp(positioning: nil, at: NSPoint(x: 0, y: view.bounds.maxY + 4), in: view)
            }
        }
    }
}

enum Confirm {
    /// Asks before something that cannot be taken back, and answers whether to go on.
    /// The panel is gone by then, so Floe comes forward for the question.
    static func destructive(_ question: String, detail: String, button: String) -> Bool {
        let alert = NSAlert()
        alert.messageText = question
        alert.informativeText = detail
        alert.addButton(withTitle: button).hasDestructiveAction = true
        alert.addButton(withTitle: "Cancel")
        NSApp.activate()
        return alert.runModal() == .alertFirstButtonReturn
    }
}

extension NSPasteboard {
    /// Replaces what is on the pasteboard with one string.
    func copy(_ text: String) {
        clearContents()
        setString(text, forType: .string)
    }
}

// MARK: - Files

/// What Floe can do with a file on disk, an application's bundle included.
enum FileActions {
    static func actions(for url: URL, host: ActionHost) -> [ItemAction?] {
        var actions: [ItemAction?] = []
        if let openWith = openWith(url, host: host) {
            actions.append(openWith)
        }
        actions += [
            ItemAction(title: "Show in Finder", symbol: "folder") {
                NSWorkspace.shared.activateFileViewerSelecting([url])
                host.dismiss()
            },
            nil,
        ]
        actions += copies(of: url, host: host)
        if canTrash(url) {
            actions += [nil, trashAction(url, host: host)]
        }
        return actions
    }

    static func trashAction(_ url: URL, host: ActionHost) -> ItemAction {
        ItemAction(title: "Move to Trash…", symbol: "trash") { trash(url, host: host) }
    }

    static func copies(of url: URL, host: ActionHost) -> [ItemAction] {
        let name = FileManager.default.displayName(atPath: url.path)
        return [
            ItemAction(title: "Copy Path", symbol: "doc.on.doc") {
                NSPasteboard.general.copy(url.path)
                host.showHUD("Copied Path")
            },
            ItemAction(title: "Copy Name", symbol: "textformat") {
                NSPasteboard.general.copy(name)
                host.showHUD("Copied \(name)")
            },
            ItemAction(title: "Copy File", symbol: "doc.on.clipboard") {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.writeObjects([url as NSURL])
                host.showHUD("Copied \(name)")
            },
        ]
    }

    /// The apps that can open the file, the one that opens it by default first; nil when there are none.
    private static func openWith(_ url: URL, host: ActionHost) -> ItemAction? {
        let workspace = NSWorkspace.shared
        let preferred = workspace.urlForApplication(toOpen: url)
        let apps = orderedApps(workspace.urlsForApplications(toOpen: url), preferred: preferred)
        guard !apps.isEmpty else { return nil }
        let rows = apps.prefix(12).map { app in
            let icon = workspace.icon(forFile: app.path)
            icon.size = NSSize(width: 16, height: 16)
            let name = FileManager.default.displayName(atPath: app.path).replacingOccurrences(of: ".app", with: "")
            return ItemAction(title: app == preferred ? "\(name) (default)" : name, symbol: "app", icon: icon) {
                workspace.open([url], withApplicationAt: app, configuration: NSWorkspace.OpenConfiguration())
                host.dismiss()
            }
        }
        return ItemAction(title: "Open With", symbol: "arrow.up.forward.app", children: Array(rows))
    }

    /// The default app first, then the rest by name, one row per app.
    static func orderedApps(_ apps: [URL], preferred: URL?) -> [URL] {
        let rest = apps.uniqued(on: \.standardizedFileURL.path)
            .filter { $0.standardizedFileURL != preferred?.standardizedFileURL }
            .sorted { $0.lastPathComponent.localizedCaseInsensitiveCompare($1.lastPathComponent) == .orderedAscending }
        return (preferred.map { [$0] } ?? []) + rest
    }

    /// Nothing under /System can be moved, so the row is left out there instead of failing.
    static func canTrash(_ url: URL) -> Bool {
        !url.standardizedFileURL.path.hasPrefix("/System/") && FileManager.default.isDeletableFile(atPath: url.path)
    }

    /// The panel goes away before the question, like a system command that asks first.
    private static func trash(_ url: URL, host: ActionHost) {
        let name = FileManager.default.displayName(atPath: url.path)
        host.dismiss()
        let detail = "You can put it back from the Trash until you empty it."
        guard Confirm.destructive("Move “\(name)” to the Trash?", detail: detail, button: "Move to Trash") else { return }
        do {
            try FileManager.default.trashItem(at: url, resultingItemURL: nil)
            host.showHUD("Moved to Trash")
        } catch {
            host.showHUD("Couldn't move \(name) to the Trash")
        }
    }
}

// MARK: - Applications

/// What Floe can do with an application besides opening it.
enum AppActions {
    static func running(_ app: AppEntry) -> NSRunningApplication? {
        let target = app.url.standardizedFileURL
        return NSWorkspace.shared.runningApplications.first { $0.bundleURL?.standardizedFileURL == target }
    }

    static func actions(for app: AppEntry, host: ActionHost) -> [ItemAction?] {
        var actions: [ItemAction?] = []
        if let running = running(app) {
            actions += processActions(app, running, host: host) + [nil]
        }
        actions += [
            ItemAction(title: "Show in Finder", symbol: "folder") {
                NSWorkspace.shared.activateFileViewerSelecting([app.url])
                host.dismiss()
            },
            nil,
        ]
        actions += FileActions.copies(of: app.url, host: host).filter { $0.title != "Copy File" }
        if let identifier = Bundle(url: app.url)?.bundleIdentifier {
            actions.append(ItemAction(title: "Copy Bundle Identifier", symbol: "number") {
                NSPasteboard.general.copy(identifier)
                host.showHUD("Copied \(identifier)")
            })
        }
        // A running app is quit first: the Trash refuses a bundle that is in use.
        if running(app) == nil, FileActions.canTrash(app.url) {
            actions += [nil, FileActions.trashAction(app.url, host: host)]
        }
        return actions
    }

    private static func processActions(_ app: AppEntry, _ running: NSRunningApplication, host: ActionHost) -> [ItemAction] {
        var actions: [ItemAction] = []
        if !running.isHidden {
            actions.append(ItemAction(title: "Hide", symbol: "eye.slash") {
                running.hide()
                host.dismiss()
            })
        }
        actions.append(ItemAction(title: "Quit", symbol: "xmark.circle") {
            running.terminate()
            host.showHUD("Quitting \(app.name)")
        })
        actions.append(ItemAction(title: "Force Quit…", symbol: "xmark.octagon") { forceQuit(app, running, host: host) })
        return actions
    }

    private static func forceQuit(_ app: AppEntry, _ running: NSRunningApplication, host: ActionHost) {
        host.dismiss()
        let detail = "You will lose any changes you haven't saved."
        guard Confirm.destructive("Force “\(app.name)” to quit?", detail: detail, button: "Force Quit") else { return }
        running.forceTerminate()
        host.showHUD("Forced \(app.name) to quit")
    }
}
