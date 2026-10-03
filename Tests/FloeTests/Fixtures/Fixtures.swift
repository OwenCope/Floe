//
//  Fixtures.swift
//  Project: Floe
//
//  Copyright (Floe) © 2026 René Jiménez
//  Licensed under the GNU GPLv3

import Foundation
import os
@testable import Floe

/// Builds tree nodes the way the host serializes them, so tests read like the tree they describe.
enum Fixture {
    /// Tests run in parallel, so the id counter is locked.
    private static let nextID = OSAllocatedUnfairLock(initialState: 1000)

    static func node(_ type: String, id: Int? = nil, props: [String: Any] = [:], handlers: [String] = [],
                     children: [[String: Any]] = []) -> [String: Any] {
        let generated = nextID.withLock { state in
            state += 1
            return state
        }
        return ["id": id ?? generated, "type": type, "props": props, "handlers": handlers, "children": children]
    }

    static func slot(_ name: String, _ child: [String: Any]) -> [String: Any] {
        node("_slot", props: ["name": name], children: [child])
    }

    static func action(_ title: String, id: Int? = nil, shortcut: [String: Any]? = nil) -> [String: Any] {
        var props: [String: Any] = ["title": title]
        if let shortcut { props["shortcut"] = shortcut }
        return node("Action", id: id, props: props, handlers: ["onAction"])
    }

    static func item(_ title: String, id: Int? = nil, subtitle: String? = nil, keywords: [String]? = nil,
                     actions: [[String: Any]] = []) -> [String: Any] {
        var props: [String: Any] = ["title": title]
        if let subtitle { props["subtitle"] = subtitle }
        if let keywords { props["keywords"] = keywords }
        let children = actions.isEmpty ? [] : [slot("actions", node("ActionPanel", children: actions))]
        return node("List.Item", id: id, props: props, children: children)
    }

    /// A root with one screen holding `view`, as the navigation root renders it.
    static func root(_ view: [String: Any]) -> Node {
        Node(json: node("root", id: 0, children: [node("_screen", children: [view])]))!
    }

    static func tree(_ json: [String: Any]) -> Node {
        Node(json: json)!
    }

    static func field(_ name: String, type: String = "textfield", required: Bool = false, defaultValue: Any? = nil,
                      options: [(String, String)] = []) -> FieldSpec {
        var json: [String: Any] = ["name": name, "type": type, "required": required]
        if let defaultValue { json["default"] = defaultValue }
        if !options.isEmpty { json["data"] = options.map { ["title": $0.0, "value": $0.1] } }
        return FieldSpec(json: json)!
    }

    static func command(_ name: String, extension extensionName: String = "sample", title: String? = nil,
                        extensionPreferences: [FieldSpec] = [], commandPreferences: [FieldSpec] = []) -> ExtensionCommand {
        ExtensionCommand(
            extensionDir: URL(fileURLWithPath: "/tmp/\(extensionName)"), extensionName: extensionName,
            extensionTitle: extensionName.capitalized, source: .local, name: name, title: title ?? name.capitalized,
            mode: "view", icon: nil, arguments: [], extensionPreferences: extensionPreferences, commandPreferences: commandPreferences
        )
    }

    static func app(_ name: String) -> RootItem {
        .app(AppEntry(name: name, url: URL(fileURLWithPath: "/Applications/\(name).app")))
    }
}
