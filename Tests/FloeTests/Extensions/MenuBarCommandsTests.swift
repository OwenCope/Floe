//
//  MenuBarCommandsTests.swift
//  Project: Floe
//
//  Copyright (Floe) © 2026 René Jiménez
//  Licensed under the GNU AGPLv3

import AppKit
@testable import Floe
import Testing

/// A status item that never reaches the menu bar.
@MainActor private final class FakeStatusItem: MenuBarStatusItem {
    let button = FakeStatusButton()
    var menu: NSMenu?
    var statusButton: (any MenuBarStatusButton)? {
        button
    }
}

/// Stands in for the menu bar and the extension hosts, and remembers what was asked of it.
@MainActor private final class FakeMenuBar {
    var items: [FakeStatusItem] = []
    var removed: [FakeStatusItem] = []
    var started: [ExtensionSession] = []

    var host: MenuBarHost {
        var host = MenuBarHost()
        host.addItem = { [unowned self] in
            let item = FakeStatusItem()
            items.append(item)
            return item
        }
        host.removeItem = { [unowned self] item in
            if let item = item as? FakeStatusItem {
                items.removeAll { $0 === item }
                removed.append(item)
            }
        }
        // No host process: a test renders by applying the message itself.
        host.start = { [unowned self] in started.append($0) }
        host.resolver = { _ in MenuBarFixture.resolver }
        host.icons = IconThumbnailCache { _ in MenuBarFixture.bitmap() }
        return host
    }
}

@MainActor
struct MenuBarCommandsTests {
    private let status = ExtensionCommand(
        extensionDir: URL(fileURLWithPath: "/tmp/floe-menu-bar-commands"), extensionName: "floe-menu-bar-commands",
        extensionTitle: "Tests", source: .local, name: "status", title: "Status",
        mode: "menu-bar", interval: 60, icon: nil, arguments: [], extensionPreferences: [], commandPreferences: []
    )
    private let bar = FakeMenuBar()
    private let settings: AppSettings
    private let model: LauncherModel
    private let commands: MenuBarCommands

    init() throws {
        settings = try AppSettings(defaults: #require(UserDefaults(suiteName: "floe-menu-bar-commands-\(UUID().uuidString)")))
        model = LauncherModel(settings: settings, snapshot: CatalogSnapshot(apps: [], commands: [Fixture.command("planets"), status]))
        commands = MenuBarCommands(model: model, host: bar.host)
    }

    private func render(_ root: Node?) throws {
        try #require(commands.session(for: status.id)).apply(.render(tree: root))
    }

    private func click(_ item: NSMenuItem) {
        if let action = item.action {
            _ = item.target?.perform(action, with: item)
        }
    }

    private func open(_ menu: NSMenu) {
        menu.delegate?.menuNeedsUpdate?(menu)
        menu.delegate?.menuWillOpen?(menu)
    }

    @Test func onlyMenuBarCommandsGetAStatusItem() {
        commands.sync([Fixture.command("planets"), status])
        #expect(bar.items.count == 1)
        #expect(bar.started.map(\.command.id) == [status.id])
        #expect(bar.started.first?.launchType == "background")
        #expect(bar.items.first?.button.title == "Status")
        #expect(bar.items.first?.menu === commands.presenter(for: status.id)?.menu)

        commands.sync([Fixture.command("planets"), status])
        #expect(bar.items.count == 1, "a rescan keeps the item and its session")
        #expect(bar.started.count == 1)
    }

    @Test func aRenderReachesTheButtonAtOnceAndBuildsNoMenu() throws {
        commands.sync([status])
        let item = try #require(bar.items.first)
        let presenter = try #require(commands.presenter(for: status.id))
        for tick in 0 ..< 50 {
            try render(MenuBarFixture.largeRoot(title: "12:00:\(tick)"))
            #expect(item.button.title == "12:00:\(tick)", "the render just published, not the one before it")
        }
        #expect(presenter.menuBuilds == 0)
        #expect(item.button.imageSets == 1)

        try open(#require(item.menu))
        #expect(presenter.menuBuilds == 1)
        #expect(item.menu?.numberOfItems == 24)
    }

    @Test func aRowSendsItsActionToTheSession() throws {
        commands.sync([status])
        var sent: [[String: Any]] = []
        try #require(commands.session(for: status.id)).transport = { sent.append($0) }
        try render(MenuBarFixture.root(title: "1", [MenuBarFixture.item("Stop", id: 42)]))
        let menu = try #require(bar.items.first?.menu)
        open(menu)

        let row = try #require(menu.item(at: 0))
        click(row)
        #expect(sent.count == 1)
        #expect(sent.first?["type"] as? String == "event")
        #expect(sent.first?["id"] as? Int == 42)
        #expect(sent.first?["prop"] as? String == "onAction")
        #expect((sent.first?["args"] as? [[String: String]]) == [["type": "left-click"]])
    }

    @Test func theRemoveEntryTakesTheCommandOutOfTheSetting() throws {
        settings.menuBarCommands = [status.id]
        commands.sync(model.enabledCommands)
        let menu = try #require(bar.items.first?.menu)
        open(menu)

        let remove = try #require(menu.items.last)
        #expect(remove.title == "Remove from Menu Bar")
        click(remove)
        #expect(settings.menuBarCommands.isEmpty)
    }

    @Test func aRemovedCommandGivesUpItsItemItsSessionAndItsMenu() throws {
        commands.sync([status])
        try render(MenuBarFixture.largeRoot(title: "1"))
        let item = try #require(bar.items.first)
        try open(#require(item.menu))
        weak let session = commands.session(for: status.id)
        weak let presenter = commands.presenter(for: status.id)
        weak let menu = item.menu
        #expect(session != nil)

        commands.sync([Fixture.command("planets")])
        #expect(bar.items.isEmpty)
        #expect(bar.removed.count == 1)
        #expect(item.menu == nil)
        #expect(bar.started.first?.isStopping == true)
        bar.started.removeAll()
        #expect(commands.session(for: status.id) == nil)
        #expect(session == nil, "nothing keeps the session")
        #expect(presenter == nil)
        #expect(menu == nil, "the built menu goes with it")
    }

    @Test func stoppingEverythingRemovesEveryItem() {
        commands.sync([status])
        commands.stopAll()
        #expect(bar.items.isEmpty)
        #expect(bar.started.first?.isStopping == true)
    }

    @Test func anIntervalRefreshKeepsTheItemAndWhatItShows() throws {
        commands.sync([status])
        try render(MenuBarFixture.root(title: "3 unread", [MenuBarFixture.item("Inbox", id: 10)]))
        let item = try #require(bar.items.first)
        let first = try #require(commands.session(for: status.id))
        let sets = item.button.titleSets

        commands.refresh(status)
        let second = try #require(commands.session(for: status.id))
        #expect(second !== first)
        #expect(first.isStopping)
        #expect(bar.started.count == 2)
        #expect(bar.items.count == 1)
        #expect(bar.removed.isEmpty, "the status item is not taken out and put back")
        #expect(item.button.title == "3 unread")
        #expect(item.button.titleSets == sets, "nothing blinks while the new session starts")

        try render(MenuBarFixture.root(title: "4 unread", [MenuBarFixture.item("Inbox", id: 10)]))
        #expect(item.button.title == "4 unread")
    }

    @Test func tryAgainStartsOverFromLoading() throws {
        commands.sync([status])
        try render(MenuBarFixture.root(title: "3 unread", [MenuBarFixture.item("Inbox", id: 10)]))
        let session = try #require(commands.session(for: status.id))
        session.failure = SessionFailure(kind: .crashed, message: "It stopped.", details: "")
        let menu = try #require(bar.items.first?.menu)
        open(menu)
        #expect(menu.items.map(\.title).prefix(2) == ["It stopped.", "Try Again"])

        let retry = try #require(menu.item(at: 1))
        click(retry)
        #expect(bar.started.count == 2)
        #expect(menu.item(at: 0)?.title == "Loading…")
        #expect(bar.items.first?.button.title == "Status")
    }
}
