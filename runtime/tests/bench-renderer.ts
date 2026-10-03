//
//  bench-renderer.ts
//  Project: Floe
//
//  Copyright (Floe) © 2026 René Jiménez
//  Licensed under the GNU GPLv3

// Standalone benchmark: renders one parent with N keyed children through the production renderer and
// times until the matching complete tree arrives at the bridge sink. The elapsed time includes React
// scheduling, the renderer's 4 ms flush and JSON serialization; it does not isolate append time and
// says nothing about Swift UI performance.

import React from "react";
import { setSink } from "../bridge";
import { render } from "../renderer";

const count = Number(process.argv[2]);
if (!Number.isInteger(count) || count <= 0) {
  console.error("usage: bun runtime/tests/bench-renderer.ts <positive sibling count>");
  process.exit(1);
}

type Node = { type: string; props: Record<string, unknown>; children: Node[] };
const names = Array.from({ length: count }, (_, index) => `item-${index}`);

const timeout = setTimeout(() => {
  console.error("no complete render arrived");
  process.exit(1);
}, 30_000);

setSink((line) => {
  const message = JSON.parse(line);
  if (message.type !== "render") return;
  const list = message.tree?.children?.find((child: Node) => child.type === "bench-list");
  const rows = list?.children.filter((child: Node) => child.type === "bench-row") ?? [];
  const received = rows.map((row: Node) => row.props.name);
  if (rows.length !== count || received[0] !== names[0] || received[count - 1] !== names[count - 1]) {
    console.error(`unexpected render: rows=${rows.length} first=${received[0]} last=${received[count - 1]}`);
    process.exit(1);
  }
  clearTimeout(timeout);
  setSink();
  console.log(`siblings=${count} bun=${Bun.version} elapsed=${(performance.now() - started).toFixed(3)}ms`);
  process.exit(0);
});

const h = React.createElement;
const started = performance.now();
render(h("bench-list", null, names.map((name) => h("bench-row", { key: name, name }))));
