//
//  NodeTests.swift
//  Project: Floe
//
//  Copyright (Floe) © 2026 René Jiménez
//  Licensed under the GNU GPLv3

import Testing
@testable import Floe

struct NodeTests {
    @Test func parsesTypePropsHandlersAndChildren() throws {
        let node = try #require(Node(json: Fixture.node("List", id: 7, props: ["isLoading": true], handlers: ["onSearchTextChange"],
                                                        children: [Fixture.item("One", id: 8)])))
        #expect(node.id == 7)
        #expect(node.type == "List")
        #expect(node.bool("isLoading"))
        #expect(node.handlers == ["onSearchTextChange"])
        #expect(node.children.map(\.id) == [8])
    }

    @Test(arguments: [nil, "text", 3, ["id": 1]] as [Any?])
    func rejectsAnythingWithoutAType(json: Any?) {
        #expect(Node(json: json) == nil)
    }

    @Test func missingFieldsGetDefaults() throws {
        let node = try #require(Node(json: ["type": "Detail"]))
        #expect(node.id == -1)
        #expect(node.props.isEmpty)
        #expect(node.handlers.isEmpty)
        #expect(node.children.isEmpty)
        #expect(node.bool("isLoading") == false)
    }

    @Test func childrenThatAreNotNodesAreDropped() throws {
        let node = try #require(Node(json: ["type": "List", "children": [["type": "List.Item"], "stray text", ["id": 2]]]))
        #expect(node.children.map(\.type) == ["List.Item"])
    }

    @Test func stringReadsPlainTextOrAValueObject() {
        let node = Fixture.tree(Fixture.node("List.Item", props: ["title": "Plain", "subtitle": ["value": "Wrapped", "tooltip": "Hint"], "count": 3]))
        #expect(node.string("title") == "Plain")
        #expect(node.string("subtitle") == "Wrapped")
        #expect(node.string("count") == nil)
        #expect(node.string("missing") == nil)
    }

    @Test func slotReturnsTheNamedElementAndContentLeavesSlotsOut() {
        let node = Fixture.tree(Fixture.node("List.Item", children: [
            Fixture.slot("actions", Fixture.node("ActionPanel", id: 20)),
            Fixture.slot("detail", Fixture.node("List.Item.Detail", id: 21)),
            Fixture.node("Extra", id: 22),
        ]))
        #expect(node.slot("actions")?.id == 20)
        #expect(node.slot("detail")?.id == 21)
        #expect(node.slot("metadata") == nil)
        #expect(node.content.map(\.id) == [22])
    }

    @Test func descendantsFindsNestedNodesInOrderIncludingItself() {
        let panel = Fixture.tree(Fixture.node("ActionPanel", children: [
            Fixture.action("First", id: 1),
            Fixture.node("ActionPanel.Section", children: [Fixture.action("Second", id: 2)]),
            Fixture.node("ActionPanel.Submenu", children: [Fixture.action("Third", id: 3)]),
        ]))
        #expect(panel.descendants(ofType: "Action").map(\.id) == [1, 2, 3])
        #expect(panel.descendants(ofType: "ActionPanel").count == 1)
        #expect(panel.descendants(ofType: "Missing").isEmpty)
    }
}
