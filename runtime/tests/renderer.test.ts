//
//  renderer.test.ts
//  Project: Floe
//
//  Copyright (Floe) © 2026 René Jiménez
//  Licensed under the GNU AGPLv3

import { afterEach, beforeEach, describe, expect, spyOn, test, type Mock } from "bun:test";
import React, { useState } from "react";
import { dispatchEvent, reportError, toError } from "../renderer";
import { find, findAll, fire, installRuntime, renderCount, resetStage, sent, settle, show, text, type TreeNode } from "./support";

const h = React.createElement;
installRuntime("renderer-tests");

// reportError logs every error it forwards; keep that out of the test output.
let consoleError: Mock<typeof console.error>;
beforeEach(() => {
  consoleError = spyOn(console, "error").mockImplementation(() => {});
});
afterEach(() => {
  consoleError.mockRestore();
});

describe("serialization", () => {
  test("sends the tree under a root node with ids, types and text", async () => {
    const tree = await show(h("panel", { title: "Planets" }, h("row", null, "Mercury"), "loose text"));
    expect(tree).toMatchObject({ id: 0, type: "root", props: {}, handlers: [] });
    const panel = find(tree, "panel");
    expect(panel.props).toEqual({ title: "Planets" });
    expect(panel.children.map((child) => child.type)).toEqual(["row", "#text"]);
    expect(text(find(tree, "row"))).toBe("Mercury");
    expect(panel.children[1].text).toBe("loose text");
    expect(new Set(findAll(tree, "row").concat(panel).map((node) => node.id)).size).toBe(2);
  });

  test("lists function props as handlers and leaves them out of the props", async () => {
    const tree = await show(h("button", { title: "Go", onAction: () => {}, onHover: () => {}, ref: () => {} }));
    const button = find(tree, "button");
    expect(button.handlers).toEqual(["onAction", "onHover"]);
    expect(button.props).toEqual({ title: "Go" });
  });

  test("turns dates into ISO strings, at any depth", async () => {
    const when = new Date("2026-03-04T05:06:07.000Z");
    const tree = await show(h("row", { when, nested: { dates: [when] } }));
    expect(find(tree, "row").props).toEqual({ when: when.toISOString(), nested: { dates: [when.toISOString()] } });
  });

  test("drops what JSON cannot carry: functions, symbols, elements and undefined", async () => {
    const tree = await show(
      h("row", {
        missing: undefined,
        element: h("icon"),
        accessory: { label: "kept", run: () => {}, tag: Symbol("tag"), element: h("icon") },
        list: [1, () => {}, h("icon"), "two"],
      }),
    );
    expect(find(tree, "row").props).toEqual({ accessory: { label: "kept" }, list: [1, null, null, "two"] });
  });

  test("breaks cycles but keeps a value that is merely shared", async () => {
    const shared = { name: "shared" };
    const cyclic: Record<string, unknown> = { name: "loop", first: shared, second: shared };
    cyclic.self = cyclic;
    const tree = await show(h("row", { cyclic }));
    expect(find(tree, "row").props.cyclic).toEqual({ name: "loop", first: shared, second: shared });
  });

  test("stops descending into very deep values", async () => {
    let deep: Record<string, unknown> = { leaf: true };
    for (let level = 0; level < 12; level++) deep = { child: deep };
    const tree = await show(h("row", { deep }));
    const serialized = JSON.stringify(find(tree, "row").props.deep);
    expect(serialized).not.toContain("leaf");
    expect(serialized.match(/child/g)?.length).toBe(8);
  });
});

function Counter() {
  const [count, setCount] = useState(0);
  return h("counter", { count, onIncrement: () => setCount((current) => current + 1) }, `count ${count}`);
}

function Roster() {
  const [names, setNames] = useState(["a", "b", "c"]);
  return h(
    "roster",
    { onChange: (next: string[]) => setNames(next) },
    names.map((name) => h("member", { key: name, name, onPing: () => {} })),
  );
}

describe("updates", () => {
  test("renders again with new props and text after a state change", async () => {
    const first = find(await show(h(Counter)), "counter");
    expect(first.props.count).toBe(0);
    const second = find(await fire(first, "onIncrement"), "counter");
    expect(second.id).toBe(first.id);
    expect(second.props.count).toBe(1);
    expect(text(second)).toBe("count 1");
  });

  test("coalesces commits that land together into one render message", async () => {
    const counter = find(await show(h(Counter)), "counter");
    const before = renderCount();
    dispatchEvent(counter.id, "onIncrement", []);
    dispatchEvent(counter.id, "onIncrement", []);
    expect(find(await settle(), "counter").props.count).toBe(2);
    expect(renderCount() - before).toBe(1);
  });

  test("removes, reorders and inserts children while keeping their ids", async () => {
    const tree = await show(h(Roster));
    const ids = Object.fromEntries(findAll(tree, "member").map((member) => [member.props.name, member.id]));

    const reordered = findAll(await fire(find(tree, "roster"), "onChange", ["c", "a", "d"]), "member");
    expect(reordered.map((member) => member.props.name)).toEqual(["c", "a", "d"]);
    expect(reordered[0].id).toBe(ids.c);
    expect(reordered[1].id).toBe(ids.a);

    const fronted = findAll(await fire(find(tree, "roster"), "onChange", ["z", "c", "a", "d"]), "member");
    expect(fronted.map((member) => member.props.name)).toEqual(["z", "c", "a", "d"]);
    expect(fronted[1].id).toBe(ids.c);

    const emptied = await fire(find(tree, "roster"), "onChange", []);
    expect(findAll(emptied, "member")).toEqual([]);
  });

  test("ignores events for a node that has been removed", async () => {
    const pings: string[] = [];
    function Removable() {
      const [present, setPresent] = useState(true);
      return h("holder", { onRemove: () => setPresent(false) }, present ? h("member", { onPing: () => pings.push("ping") }) : null);
    }
    const tree = await show(h(Removable));
    const member = find(tree, "member");
    await fire(member, "onPing");
    await fire(find(tree, "holder"), "onRemove");
    await fire(member, "onPing");
    expect(pings).toEqual(["ping"]);
  });
});

describe("initial children", () => {
  test("builds a fresh parent with 10,000 keyed children in order", async () => {
    const names = Array.from({ length: 10_000 }, (_, index) => `item-${index}`);
    const list = h("list", null, names.map((name) => h("row", { key: name, name })));

    // A first commit at this size can outlast settle's quiet window, so keep asking until it lands.
    let rows: TreeNode[] = [];
    for (let attempt = 0; attempt < 20 && rows.length !== names.length; attempt++) {
      try {
        rows = findAll(await show(list), "row");
      } catch {
        rows = [];
      }
    }
    expect(rows).toHaveLength(names.length);
    expect(rows.map((row) => row.props.name)).toEqual(names);
    expect(new Set(rows.map((row) => row.id)).size).toBe(names.length);
  });

  test("assembles nested host and text children in one initial pass", async () => {
    const tree = await show(h("panel", null, h("row", null, "first", h("tag", null, "inner"), "last"), "loose"));
    const row = find(tree, "row");
    expect(row.children.map((child) => child.type)).toEqual(["#text", "tag", "#text"]);
    expect(text(row)).toBe("firstinnerlast");
    expect(find(tree, "panel").children.map((child) => child.type)).toEqual(["row", "#text"]);
  });

  test("keeps a keyed child's id and handler when its host parent moves it to the end", async () => {
    const pings: string[] = [];
    function Rotation() {
      const [names, setNames] = useState(["a", "b", "c"]);
      return h(
        "group",
        { onRotate: () => setNames(([first, ...rest]) => [...rest, first]) },
        names.map((name) => h("member", { key: name, name, onPing: () => pings.push(name) })),
      );
    }
    const tree = await show(h(Rotation));
    const ids = Object.fromEntries(findAll(tree, "member").map((member) => [member.props.name, member.id]));

    const rotated = findAll(await fire(find(tree, "group"), "onRotate"), "member");
    expect(rotated.map((member) => member.props.name)).toEqual(["b", "c", "a"]);
    expect(rotated.map((member) => member.id)).toEqual([ids.b, ids.c, ids.a]);
    expect(rotated).toHaveLength(3);

    await fire(rotated[2], "onPing");
    expect(pings).toEqual(["a"]);
  });

  test("keeps ids when a fragment's children move at the container level", async () => {
    function TopLevel() {
      const [names, setNames] = useState(["a", "b", "c"]);
      return h(
        React.Fragment,
        null,
        h("lever", { onRotate: () => setNames(([first, ...rest]) => [...rest, first]) }),
        names.map((name) => h("entry", { key: name, name })),
      );
    }
    const tree = await show(h(TopLevel));
    const ids = Object.fromEntries(findAll(tree, "entry").map((entry) => [entry.props.name, entry.id]));

    const rotated = findAll(await fire(find(tree, "lever"), "onRotate"), "entry");
    expect(rotated.map((entry) => entry.props.name)).toEqual(["b", "c", "a"]);
    expect(rotated.map((entry) => entry.id)).toEqual([ids.b, ids.c, ids.a]);
  });
});

describe("visible screen projection", () => {
  test("a root without screens serializes as before", async () => {
    const tree = await show(h("panel", { title: "Planets" }, h("row", null, "Mercury")));
    expect(tree).toMatchObject({ id: 0, type: "root", props: {}, handlers: [] });
    expect(tree.children.map((child) => child.type)).toEqual(["panel"]);
    expect(text(find(tree, "row"))).toBe("Mercury");
  });

  test("an empty root serializes with no children", async () => {
    const tree = await show(null);
    expect(tree.children).toEqual([]);
  });

  test("only the last of several screen siblings is transmitted", async () => {
    const tree = await show(
      h(
        React.Fragment,
        null,
        h("_screen", { key: 0 }, h("row", { title: "lower" })),
        h("_screen", { key: 1 }, h("row", { title: "upper" })),
      ),
    );
    const screens = tree.children;
    expect(screens).toHaveLength(1);
    expect(screens[0].type).toBe("_screen");
    expect(find(screens[0], "row").props.title).toBe("upper");
    expect(findAll(tree, "row").map((row) => row.props.title)).toEqual(["upper"], "the hidden screen is not serialized");
  });

  test("non-screen root siblings keep their places around the visible screen", async () => {
    const tree = await show(
      h(
        React.Fragment,
        null,
        h("panel", { title: "before" }),
        h("_screen", { key: 0 }, h("row", { title: "lower" })),
        h("_screen", { key: 1 }, h("row", { title: "upper" })),
        h("panel", { title: "after" }),
      ),
    );
    expect(tree.children.map((child) => [child.type, child.props.title])).toEqual([
      ["panel", "before"],
      ["_screen", undefined],
      ["panel", "after"],
    ]);
    expect(find(tree.children[1], "row").props.title).toBe("upper");
  });

  test("hidden screens are not traversed for serialization", async () => {
    let reads = 0;
    let visibleReads = 0;
    const counted = { get mark() { reads += 1; return true; } };
    const visibleCounted = { get mark() { visibleReads += 1; return true; } };
    function Screens() {
      const [pushed, setPushed] = useState(false);
      return h(
        React.Fragment,
        null,
        h("_screen", { key: 0 }, h("row", { counted, title: `lower ${pushed}` })),
        pushed ? h("_screen", { key: 1 }, h("row", { visibleCounted, title: "upper" })) : null,
        h("lever", { onPush: () => setPushed(true) }),
      );
    }
    const tree = await show(h(Screens));
    expect(reads).toBe(1, "the visible screen is serialized");

    const pushed = await fire(find(tree, "lever"), "onPush");
    expect(find(pushed, "row").props.title).toBe("upper");
    expect(visibleReads).toBe(1, "the visible screen is still serialized");
    expect(reads).toBe(1, "pushing a screen stops visiting the hidden prop");
  });
});

describe("dispatchEvent", () => {
  test("passes the arguments to the handler", async () => {
    const calls: unknown[][] = [];
    const tree = await show(h("field", { onChange: (...args: unknown[]) => calls.push(args) }));
    dispatchEvent(find(tree, "field").id, "onChange", ["text", 2, { deep: [true] }]);
    expect(calls).toEqual([["text", 2, { deep: [true] }]]);
  });

  test("revives tagged dates wherever they appear", async () => {
    const calls: any[] = [];
    const tree = await show(h("form", { onSubmit: (values: unknown, extra: unknown) => calls.push([values, extra]) }));
    const iso = "2026-10-02T12:00:00.000Z";
    dispatchEvent(find(tree, "form").id, "onSubmit", [{ due: { $date: iso }, name: "x", list: [{ $date: iso }, null] }, { $date: iso }]);
    const [values, extra] = calls[0];
    expect(values.due).toEqual(new Date(iso));
    expect(values.name).toBe("x");
    expect(values.list).toEqual([new Date(iso), null]);
    expect(extra).toBeInstanceOf(Date);
  });

  test("does nothing for an unknown node or a prop that is not a function", async () => {
    const tree = await show(h("field", { title: "Name" }));
    dispatchEvent(find(tree, "field").id, "title", []);
    dispatchEvent(find(tree, "field").id, "onMissing", []);
    dispatchEvent(987654321, "onChange", []);
    expect(sent()).toEqual([]);
  });

  test("reports a handler that throws as a non-fatal error", async () => {
    const tree = await show(
      h("field", {
        onChange: () => {
          throw new Error("handler broke");
        },
      }),
    );
    dispatchEvent(find(tree, "field").id, "onChange", []);
    expect(sent("error")).toEqual([expect.objectContaining({ message: "handler broke", fatal: false })]);
    expect(sent("error")[0].stack).toContain("handler broke");
  });

  test("reports a rejected promise from an async handler as a non-fatal error", async () => {
    const tree = await show(h("field", { onChange: () => Promise.reject(new Error("request failed")) }));
    await fire(find(tree, "field"), "onChange");
    expect(sent("error")).toEqual([expect.objectContaining({ message: "request failed", fatal: false })]);
  });
});

describe("errors", () => {
  test("toError keeps Errors and wraps strings and plain objects", () => {
    const original = new TypeError("typed");
    expect(toError(original)).toBe(original);
    expect(toError("just text").message).toBe("just text");
    expect(toError({ code: 42 }).message).toBe('{"code":42}');
  });

  test("reportError sends the message and logs the stack", () => {
    reportError("soft failure");
    reportError(new Error("hard failure"), true);
    expect(sent("error").map(({ message, fatal }) => ({ message, fatal }))).toEqual([
      { message: "soft failure", fatal: false },
      { message: "hard failure", fatal: true },
    ]);
    expect(String(consoleError.mock.calls[1][0])).toContain("hard failure");
  });

  test("an error caught by an error boundary is not fatal", async () => {
    class Boundary extends React.Component<{ children: React.ReactNode }, { failed: boolean }> {
      state = { failed: false };
      static getDerivedStateFromError() {
        return { failed: true };
      }
      render() {
        return this.state.failed ? h("fallback") : this.props.children;
      }
    }
    function Broken(): React.ReactNode {
      throw new Error("render broke inside a boundary");
    }
    const tree = await show(h(Boundary, null, h(Broken)));
    expect(findAll(tree, "fallback")).toHaveLength(1);
    expect(sent("error")).toEqual([expect.objectContaining({ message: "render broke inside a boundary", fatal: false })]);
  });

  test("an error nothing catches is fatal and empties the view", async () => {
    function Broken(): React.ReactNode {
      throw new Error("render broke");
    }
    const tree = await show(h(Broken));
    resetStage();
    expect(sent("error")).toEqual([expect.objectContaining({ message: "render broke", fatal: true })]);
    expect(tree.children).toEqual([]);

    const recovered = await show(h("row", { title: "back" }));
    expect(findAll(recovered, "row")).toHaveLength(1);
  });
});
