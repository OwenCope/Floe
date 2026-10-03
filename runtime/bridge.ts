//
//  bridge.ts
//  Project: Floe
//
//  Copyright (Floe) © 2026 René Jiménez
//  Licensed under the GNU AGPLv3

// NDJSON bridge between the Bun extension host and the Swift app.
// stdout carries protocol messages only; console output is redirected to stderr by host.ts.

export type Manifest = {
  name: string;
  title?: string;
  author?: string;
  owner?: string;
  preferences?: Preference[];
  commands?: { name: string; title?: string; mode?: string; preferences?: Preference[] }[];
};
type Preference = { name: string; default?: unknown };

export const ctx = {
  extDir: "",
  commandName: "",
  commandMode: "view",
  supportPath: "",
  manifest: { name: "" } as Manifest,
};

type Sink = (line: string) => void;
const stdoutSink: Sink = (line) => {
  process.stdout.write(line);
};
let sink = stdoutSink;
// Tests replace the sink to capture messages; passing nothing restores stdout.
export function setSink(replacement: Sink = stdoutSink) {
  sink = replacement;
}

export function send(message: Record<string, unknown>) {
  sink(JSON.stringify(message) + "\n");
}

let popHandler: () => void = () => send({ type: "exit" });
export function setPopHandler(handler: () => void) {
  popHandler = handler;
}
export function handlePop() {
  popHandler();
}

let popToRootHandler: () => void = () => {};
export function setPopToRootHandler(handler: () => void) {
  popToRootHandler = handler;
}
export function handlePopToRoot() {
  popToRootHandler();
}
