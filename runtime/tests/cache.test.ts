//
//  cache.test.ts
//  Project: Floe
//
//  Copyright (Floe) © 2026 René Jiménez
//  Licensed under the GNU AGPLv3

import { describe, expect, spyOn, test } from "bun:test";
import fs from "node:fs";
import path from "node:path";
import { Cache } from "../cache";
import { installRuntime } from "./support";

const support = installRuntime("cache-tests");

const bytes = (text: string) => Buffer.byteLength(text, "utf8");

function entriesOf(namespace: string): [string, string][] {
    const parsed = JSON.parse(fs.readFileSync(path.join(support.supportPath, `cache-${namespace}.json`), "utf8"));
    return parsed.entries ?? Object.entries(parsed);
}

function writeRaw(namespace: string, content: string) {
    fs.writeFileSync(path.join(support.supportPath, `cache-${namespace}.json`), content);
}

describe("lru", () => {
    test("get promotes, has does not", () => {
        const capacity = bytes("one") + bytes("two") + bytes("three") + bytes("four");
        const cache = new Cache({ namespace: "promote", capacity });
        cache.set("one", "two");
        cache.set("three", "four");
        expect(cache.has("one"), "has alone leaves one the oldest").toBe(true);

        cache.get("one");
        cache.set("five", "six");
        expect(cache.has("one"), "the promoted entry survives").toBe(true);
        expect(cache.has("three"), "the untouched entry is the one evicted").toBe(false);
    });

    test("an overwrite releases its old cost, a shrink frees room", () => {
        const capacity = bytes("a") + 1 + bytes("b") + 1;
        const cache = new Cache({ namespace: "overwrite", capacity });
        cache.set("a", "v");
        cache.set("b", "v");
        cache.set("b", "");
        expect(cache.has("a"), "shrinking b freed room without evicting").toBe(true);

        cache.set("c", "v");
        expect(cache.has("b")).toBe(true);
        expect(cache.has("a"), "a is the oldest once more").toBe(false);
    });

    test("the least recent survivors are deterministic", () => {
        const cache = new Cache({ namespace: "order", capacity: bytes("a") + bytes("b") + bytes("c") + 3 * bytes("v") });
        for (const key of ["a", "b", "c"]) cache.set(key, "v");
        cache.set("d", "v");
        expect(["a", "b", "c", "d"].filter((key) => cache.has(key))).toEqual(["b", "c", "d"]);
    });

    test("zero capacity stores nothing and skips the file", () => {
        const cache = new Cache({ namespace: "empty", capacity: 0 });
        cache.set("k", "v");
        expect(cache.isEmpty).toBe(true);
        expect(cache.get("k")).toBeUndefined();
        expect(fs.existsSync(path.join(support.supportPath, "cache-empty.json"))).toBe(false);
    });

    test.each([-1, 1.5, Number.NaN, Number.POSITIVE_INFINITY, Number.MAX_SAFE_INTEGER + 1])(
        "a capacity of %p is rejected before touching the disk",
        (capacity) => {
            expect(() => new Cache({ namespace: "invalid", capacity })).toThrow(RangeError);
            expect(fs.existsSync(path.join(support.supportPath, "cache-invalid.json"))).toBe(false);
        },
    );

    test("an oversized replacement removes only its own stale value", () => {
        const capacity = bytes("k") + bytes("big") + bytes("other") + 1;
        const cache = new Cache({ namespace: "oversize", capacity });
        cache.set("k", "big");
        cache.set("other", "!");
        cache.set("k", "way too big for this cache");
        expect(cache.has("k")).toBe(false);
        expect(cache.has("other"), "no unrelated entry was evicted to make room").toBe(true);
    });
});

describe("bytes", () => {
    test("multibyte keys and values are counted in utf8 bytes", () => {
        const emoji = "👍";
        const cache = new Cache({ namespace: "multibyte", capacity: 2 * bytes(emoji) });
        cache.set(emoji, emoji);
        expect(cache.has(emoji)).toBe(true);

        cache.set("one more byte", "x");
        expect(cache.has(emoji), "the oversized set evicts nothing").toBe(true);
        expect(cache.has("one more byte")).toBe(false);
    });

    test("an exact fit is kept and one byte over is dropped", () => {
        const exact = new Cache({ namespace: "exact", capacity: bytes("k") + bytes("value") });
        exact.set("k", "value");
        expect(exact.has("k")).toBe(true);

        const over = new Cache({ namespace: "exact-over", capacity: bytes("k") + bytes("value") });
        over.set("k", "values");
        expect(over.has("k")).toBe(false);
    });

    test("repeated insertions keep only the expected survivors", () => {
        const cache = new Cache({ namespace: "repeat", capacity: 2 * (bytes("k-9") + 1) });
        for (let index = 0; index < 10; index++) cache.set("k", String(index % 10));
        for (let index = 0; index < 10; index++) cache.set(`k-${index}`, "v");
        expect(cache.has("k"), "the refreshed entry is long gone").toBe(false);
        expect(cache.has("k-8")).toBe(true);
        expect(cache.has("k-9")).toBe(true);
        expect(cache.has("k-7")).toBe(false);
    });
});

describe("subscribers", () => {
    test("evictions and sets announce the final bounded state", () => {
        const cache = new Cache({ namespace: "notify", capacity: bytes("a") + bytes("v") + bytes("b") + bytes("v") });
        const seen: unknown[][] = [];
        cache.subscribe((key, data) => seen.push([key, data]));
        cache.set("a", "v");
        cache.set("b", "v");
        cache.set("c", "v");
        expect(seen).toEqual([
            ["a", "v"],
            ["b", "v"],
            ["a", undefined],
            ["c", "v"],
        ]);
        expect(cache.has("b")).toBe(true);
    });

    test("an oversized set only announces the removal of what it dropped", () => {
        const cache = new Cache({ namespace: "notify-oversize", capacity: bytes("k") + bytes("kept") });
        cache.set("k", "kept");
        const seen: unknown[][] = [];
        cache.subscribe((key, data) => seen.push([key, data]));
        cache.set("k", "much too large");
        expect(seen).toEqual([["k", undefined]]);
    });

    test("a silent clear notifies nobody and stays bounded", () => {
        const cache = new Cache({ namespace: "notify-clear", capacity: bytes("k") + bytes("v") });
        cache.set("k", "v");
        const seen: unknown[][] = [];
        cache.subscribe((key, data) => seen.push([key, data]));
        cache.clear({ notifySubscribers: false });
        expect(seen).toEqual([]);
        expect(cache.isEmpty).toBe(true);
        expect(entriesOf("notify-clear")).toEqual([]);
    });

    test("a reentrant mutation cannot corrupt the notification pass", () => {
        const cache = new Cache({ namespace: "reentrant", capacity: bytes("first") + 1 + bytes("second") + 1 });
        const seen: unknown[][] = [];
        cache.subscribe((key, data) => {
            seen.push([key, data]);
            if (key === "first") cache.set("second", "v");
        });
        cache.set("first", "v");
        expect(seen).toEqual([
            ["first", "v"],
            ["second", "v"],
        ]);
        expect(cache.has("second")).toBe(true);
    });
});

describe("persistence", () => {
    test("legacy dictionaries load with deterministic recency and are trimmed to the budget", () => {
        writeRaw("legacy", JSON.stringify({ alpha: "1", beta: "2", gamma: "3" }));
        const capacity = bytes("alpha") + 1 + bytes("beta") + 1;
        const cache = new Cache({ namespace: "legacy", capacity });
        expect(cache.has("alpha"), "the earliest entries fill the budget").toBe(true);
        expect(cache.has("beta")).toBe(true);
        expect(cache.has("gamma")).toBe(false);

        expect(cache.get("beta"), "the last retained entry is newest").toBe("2");
        cache.set("zeta", "4");
        expect(cache.has("beta"), "the reopened recency orders the next eviction").toBe(true);
        expect(cache.has("alpha")).toBe(false);
    });

    test("recency written by a mutation survives reopening", () => {
        const capacity = bytes("old") + 1 + bytes("new") + 2;
        const first = new Cache({ namespace: "recency", capacity });
        first.set("old", "1");
        first.set("new", "22");
        // A get alone does not rewrite the file; a mutation persists the promoted order.
        first.set("old", "1");
        const second = new Cache({ namespace: "recency", capacity });
        second.set("t3", "333");
        expect(second.has("old"), "old was rewritten newest before the reopen").toBe(true);
        expect(second.has("new"), "the unmoved entry is the one evicted").toBe(false);
        expect(second.has("t3")).toBe(true);
    });

    test("ordered numeric-looking keys keep their insertion order", () => {
        const cache = new Cache({ namespace: "numeric", capacity: 3 * (bytes("2") + 1) });
        cache.set("2", "a");
        cache.set("1", "b");
        cache.set("3", "c");
        cache.set("4", "d");
        expect(cache.has("2"), "the first-set numeric key is the oldest").toBe(false);
        expect(cache.has("1")).toBe(true);
        expect(cache.has("3")).toBe(true);
    });

    test("malformed records and corrupt files are disposable misses", () => {
        writeRaw("broken", "not json at all");
        expect(new Cache({ namespace: "broken" }).isEmpty).toBe(true);

        writeRaw("malformed", JSON.stringify({ keep: "me", drop: 42, gone: null, list: [] }));
        const cache = new Cache({ namespace: "malformed" });
        expect(cache.has("keep")).toBe(true);
        expect(cache.has("drop")).toBe(false);
        expect(cache.has("gone")).toBe(false);
        expect(cache.has("list")).toBe(false);
    });

    test("a valid snapshot reopens under a smaller capacity", () => {
        const first = new Cache({ namespace: "shrink", capacity: 3 * (bytes("one") + bytes("v")) });
        for (const key of ["one", "two", "six"]) first.set(key, "v");

        const second = new Cache({ namespace: "shrink", capacity: 2 * (bytes("one") + bytes("v")) });
        expect(second.has("one")).toBe(true);
        expect(second.has("two")).toBe(true);
        expect(second.has("six"), "restore keeps the earliest entries under a smaller budget").toBe(false);
    });

    test("an escaping-heavy valid snapshot still fits its restore ceiling", () => {
        const slashy = "\\".repeat(64);
        const capacity = 4 * (bytes("k") + bytes(slashy));
        const first = new Cache({ namespace: "escaping", capacity });
        for (const key of ["a", "b", "c", "d"]) first.set(key, slashy);

        const file = path.join(support.supportPath, "cache-escaping.json");
        const accounted = entriesOf("escaping").reduce((total, [key, value]) => total + bytes(key) + bytes(value), 0);
        expect(fs.statSync(file).size).toBeLessThan(16 * capacity + 64 * 1024);
        expect(accounted).toBeLessThanOrEqual(capacity);

        const second = new Cache({ namespace: "escaping", capacity });
        expect(second.has("d")).toBe(true);
    });
});

describe("restore safety", () => {
    test("an over-ceiling file is rejected before it is read", () => {
        writeRaw("huge", JSON.stringify({ big: "x".repeat(4 * 1024 * 1024) }));
        const originalRead = fs.readFileSync;
        const reads: string[] = [];
        const spy = spyOn(fs, "readFileSync").mockImplementation(((file: unknown, ...rest: unknown[]) => {
            reads.push(String(file));
            return (originalRead as (...arguments_: unknown[]) => unknown)(file, ...rest);
        }) as typeof fs.readFileSync);
        try {
            const cache = new Cache({ namespace: "huge", capacity: 1024 });
            expect(cache.isEmpty).toBe(true);
            expect(reads.join()).not.toContain("cache-huge.json");
        } finally {
            spy.mockRestore();
        }
    });

    test("clear leaves an empty bounded snapshot behind", () => {
        const cache = new Cache({ namespace: "cleared", capacity: bytes("k") + bytes("v") });
        cache.set("k", "v");
        cache.clear();
        expect(entriesOf("cleared")).toEqual([]);
    });
});
