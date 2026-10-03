//
//  cache.ts
//  Project: Floe
//
//  Copyright (Floe) © 2026 René Jiménez
//  Licensed under the GNU AGPLv3

// The extension Cache: an LRU byte budget over string values, persisted per namespace. Capacity is
// per instance, so several caches or namespaces can consume several budgets at once.

import fs from "node:fs";
import path from "node:path";
import { ctx } from "./bridge";

type CacheSubscriber = (key: string | undefined, data: string | undefined) => void;

// Upstream Raycast documents "10 MB" without units; Floe's choice is 10 MiB.
const defaultCapacity = 10 * 1024 * 1024;

// A persisted snapshot is JSON, so escaping can inflate it well past its accounted bytes; 16× plus a
// fixed pad absorbs that without admitting arbitrary files. A safety ceiling, not an RSS guarantee.
const restoreOverheadFactor = 16;
const restorePadding = 64 * 1024;

type Snapshot = { version: 1; entries: [string, string][] };

function recordsOf(parsed: unknown): [string, string][] {
    if (parsed !== null && typeof parsed === "object" && Array.isArray((parsed as Snapshot).entries)) {
        return ((parsed as Snapshot).entries as unknown[]).filter(
            (record): record is [string, string] =>
                Array.isArray(record) && record.length === 2 && typeof record[0] === "string" && typeof record[1] === "string",
        );
    }
    if (parsed === null || typeof parsed !== "object" || Array.isArray(parsed)) return [];
    return Object.entries(parsed).filter(([, value]) => typeof value === "string");
}

export class Cache {
    private readonly file: string;
    private readonly capacity: number;
    /// Oldest to newest; iteration order is the eviction and persistence order.
    private readonly entries = new Map<string, string>();
    private used = 0;
    private readonly subscribers = new Set<CacheSubscriber>();

    constructor(options?: { namespace?: string; capacity?: number }) {
        const requested = options?.capacity ?? defaultCapacity;
        if (!Number.isInteger(requested) || requested < 0 || requested > Number.MAX_SAFE_INTEGER) {
            throw new RangeError(`cache capacity must be a nonnegative integer, got ${String(options?.capacity)}`);
        }
        this.capacity = requested;
        this.file = path.join(ctx.supportPath, `cache-${options?.namespace ?? "default"}.json`);
        this.restore();
    }

    get isEmpty() {
        return this.entries.size === 0;
    }

    readonly get = (key: string) => {
        const value = this.entries.get(key);
        if (value === undefined) return undefined;
        this.entries.delete(key);
        this.entries.set(key, value);
        return value;
    };

    readonly has = (key: string) => this.entries.has(key);

    readonly set = (key: string, value: string) => {
        const keyBytes = Buffer.byteLength(key, "utf8");
        const cost = keyBytes + Buffer.byteLength(value, "utf8");
        if (cost > this.capacity) {
            // Nothing fits, so no unrelated entry is evicted to make room; a stale value for this key
            // goes, and observers hear a removal rather than a value that was never kept.
            const stale = this.entries.get(key);
            if (stale !== undefined) {
                this.used -= keyBytes + Buffer.byteLength(stale, "utf8");
                this.entries.delete(key);
                this.persist([[key, undefined]]);
            }
            return;
        }
        const stale = this.entries.get(key);
        if (stale !== undefined) {
            this.used -= keyBytes + Buffer.byteLength(stale, "utf8");
            this.entries.delete(key);
        }
        const evicted: [string, undefined][] = [];
        while (this.used + cost > this.capacity) {
            const oldestKey = this.entries.keys().next().value;
            if (oldestKey === undefined) break;
            const oldestValue = this.entries.get(oldestKey)!;
            this.used -= Buffer.byteLength(oldestKey, "utf8") + Buffer.byteLength(oldestValue, "utf8");
            this.entries.delete(oldestKey);
            evicted.push([oldestKey, undefined]);
        }
        this.entries.set(key, value);
        this.used += cost;
        this.persist([...evicted, [key, value]]);
    };

    readonly remove = (key: string) => {
        const stale = this.entries.get(key);
        if (stale === undefined) return false;
        this.used -= Buffer.byteLength(key, "utf8") + Buffer.byteLength(stale, "utf8");
        this.entries.delete(key);
        this.persist([[key, undefined]]);
        return true;
    };

    readonly clear = (options?: { notifySubscribers?: boolean }) => {
        this.entries.clear();
        this.used = 0;
        this.persist(options?.notifySubscribers === false ? [] : [[undefined, undefined]]);
    };

    readonly subscribe = (subscriber: CacheSubscriber) => {
        this.subscribers.add(subscriber);
        return () => {
            this.subscribers.delete(subscriber);
        };
    };

    /// The snapshot on disk is replaced only after the in-memory state is final, atomically, so a
    /// crash mid-write keeps the previous complete snapshot. Subscriber callbacks run after that,
    /// over a frozen copy, so a callback that unsubscribes or mutates cannot corrupt the notification
    /// pass — and observers only ever see the bounded final state.
    private readonly persist = (notifications: [string | undefined, string | undefined][]) => {
        const temporary = `${this.file}.tmp`;
        const snapshot: Snapshot = { version: 1, entries: [...this.entries] };
        fs.writeFileSync(temporary, JSON.stringify(snapshot));
        fs.renameSync(temporary, this.file);
        const frozen = [...this.subscribers];
        for (const [key, value] of notifications) {
            frozen.forEach((subscriber) => subscriber(key, value));
        }
    };

    /// Legacy files were plain string dictionaries; their enumeration order becomes the initial
    /// recency. Records that do not fit the budget are dropped before they are retained.
    private restore() {
        if (this.capacity === 0) return;
        let content: string;
        try {
            if (fs.statSync(this.file).size > this.restoreCeiling()) return;
            content = fs.readFileSync(this.file, "utf8");
        } catch {
            return;
        }
        let parsed: unknown;
        try {
            parsed = JSON.parse(content);
        } catch {
            return;
        }
        for (const [key, value] of recordsOf(parsed)) {
            const cost = Buffer.byteLength(key, "utf8") + Buffer.byteLength(value, "utf8");
            if (this.entries.has(key) || this.used + cost > this.capacity) continue;
            this.entries.set(key, value);
            this.used += cost;
        }
    }

    private restoreCeiling() {
        if (this.capacity > Number.MAX_SAFE_INTEGER / restoreOverheadFactor) return Number.MAX_SAFE_INTEGER;
        return this.capacity * restoreOverheadFactor + restorePadding;
    }
}
