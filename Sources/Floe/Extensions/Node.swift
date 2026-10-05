//
//  Node.swift
//  Project: Floe
//
//  Copyright (Floe) © 2026 René Jiménez
//  Licensed under the GNU AGPLv3

import Foundation

/// One element of the tree the Bun host serializes after each React commit.
nonisolated struct Node: Identifiable {
    let id: Int
    let type: String
    let props: [String: Any]
    let handlers: Set<String>
    let children: [Node]

    init?(json: Any?) {
        guard let dict = json as? [String: Any], let type = dict["type"] as? String else { return nil }
        self.id = dict["id"] as? Int ?? -1
        self.type = type
        self.props = dict["props"] as? [String: Any] ?? [:]
        self.handlers = Set(dict["handlers"] as? [String] ?? [])
        self.children = (dict["children"] as? [Any] ?? []).compactMap(Node.init(json:))
    }

    /// Element-valued props such as `actions` or `detail` arrive as named `_slot` children.
    func slot(_ name: String) -> Node? {
        children.first { $0.type == "_slot" && $0.props["name"] as? String == name }?.children.first
    }

    var content: [Node] {
        children.filter { $0.type != "_slot" }
    }

    /// Raycast accepts either a plain string or `{ value, tooltip }` for most text props.
    func string(_ key: String) -> String? {
        if let string = props[key] as? String {
            return string
        }
        return (props[key] as? [String: Any])?["value"] as? String
    }

    func bool(_ key: String) -> Bool {
        props[key] as? Bool ?? false
    }

    func descendants(ofType type: String) -> [Node] {
        (self.type == type ? [self] : []) + children.flatMap { $0.descendants(ofType: type) }
    }
}

nonisolated struct Row: Identifiable {
    let node: Node
    let sectionTitle: String?
    var id: Int {
        node.id
    }
}
