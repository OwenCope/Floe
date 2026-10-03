//
//  build.test.ts
//  Project: Floe
//
//  Copyright (Floe) © 2026 René Jiménez
//  Licensed under the GNU AGPLv3

import { afterAll, afterEach, beforeEach, describe, expect, spyOn, test, type Mock } from "bun:test";
import fs from "node:fs";
import path from "node:path";
import React from "react";
import { ctx } from "../bridge";
import { bundle, findEntry, fingerprint, newestChange, shimPath } from "../build";
import { find, installRuntime, makeTempDir, showScreen } from "./support";

installRuntime("build-tests");
const tempDirs: string[] = [];

function write(file: string, content = "") {
  fs.mkdirSync(path.dirname(file), { recursive: true });
  fs.writeFileSync(file, content);
}

// Modification times are set by hand: two writes in the same millisecond would otherwise look unchanged.
function setModified(file: string, seconds: number) {
  fs.utimesSync(file, seconds, seconds);
}

function makeExtension(files: Record<string, string>, command = "main"): string {
  const extDir = makeTempDir("extension");
  tempDirs.push(extDir);
  write(path.join(extDir, "package.json"), JSON.stringify({ name: "sample", commands: [{ name: command }] }));
  for (const [name, content] of Object.entries(files)) write(path.join(extDir, name), content);
  ctx.extDir = extDir;
  ctx.commandName = command;
  ctx.manifest = { name: "sample" };
  // Each extension has its own support folder in the app too. Bun also remembers a folder's listing
  // once it has imported from it, so a second bundle in the same folder would not be found.
  ctx.supportPath = makeTempDir("support");
  tempDirs.push(ctx.supportPath);
  return extDir;
}

// bundle() logs each real build, which is how the tests tell a build from a cache hit.
let consoleError: Mock<typeof console.error>;
beforeEach(() => {
  consoleError = spyOn(console, "error").mockImplementation(() => {});
});
afterEach(() => {
  consoleError.mockRestore();
});
afterAll(() => {
  for (const dir of tempDirs) fs.rmSync(dir, { recursive: true, force: true });
});

describe("findEntry", () => {
  test("finds a command file in src/", () => {
    const extDir = makeExtension({ "src/main.tsx": "" });
    expect(findEntry()).toBe(path.join(extDir, "src/main.tsx"));
  });

  test("finds a command folder with an index file", () => {
    const extDir = makeExtension({ "src/main/index.ts": "" });
    expect(findEntry()).toBe(path.join(extDir, "src/main/index.ts"));
  });

  test("prefers TypeScript sources over JavaScript and over a prebuilt bundle", () => {
    const extDir = makeExtension({ "src/main.js": "", "src/main.ts": "", "main.js": "" });
    expect(findEntry()).toBe(path.join(extDir, "src/main.ts"));
  });

  test("falls back to the prebuilt bundle Raycast installs beside the manifest", () => {
    const extDir = makeExtension({ "main.js": "", "other.js": "" });
    expect(findEntry()).toBe(path.join(extDir, "main.js"));
  });

  test("throws when the command has no entry file", () => {
    makeExtension({ "src/other.tsx": "" });
    expect(() => findEntry()).toThrow('no entry file for command "main"');
  });
});

describe("newestChange", () => {
  test("is zero for a missing path and the file's own time for a file", () => {
    const extDir = makeExtension({ "src/main.ts": "" });
    setModified(path.join(extDir, "src/main.ts"), 1_700_000_000);
    expect(newestChange(path.join(extDir, "missing"))).toBe(0);
    expect(newestChange(path.join(extDir, "src/main.ts"))).toBe(1_700_000_000_000);
  });

  test("walks nested folders but skips node_modules and dot entries", () => {
    const extDir = makeExtension({
      "src/main.ts": "",
      "src/deep/er/helper.ts": "",
      "src/node_modules/dep/index.js": "",
      "src/.cache/output.js": "",
    });
    const sources = path.join(extDir, "src");
    const base = newestChange(sources);
    setModified(path.join(sources, "node_modules/dep/index.js"), base / 1000 + 500);
    setModified(path.join(sources, ".cache/output.js"), base / 1000 + 500);
    expect(newestChange(sources)).toBe(base);

    setModified(path.join(sources, "deep/er/helper.ts"), Math.floor(base / 1000) + 100);
    expect(newestChange(sources)).toBe((Math.floor(base / 1000) + 100) * 1000);
  });
});

describe("fingerprint", () => {
  test("is stable while nothing changes and records what the bundle depends on", () => {
    const extDir = makeExtension({ "src/main.ts": "" });
    const entry = path.join(extDir, "src/main.ts");
    expect(fingerprint(entry)).toBe(fingerprint(entry));
    expect(JSON.parse(fingerprint(entry))).toMatchObject({ entry, shim: shimPath, bun: Bun.version, dependencies: 0 });
  });

  test("changes when any file under src/ changes, not only the entry", () => {
    const extDir = makeExtension({ "src/main.ts": "", "src/lib/helper.ts": "" });
    const entry = path.join(extDir, "src/main.ts");
    const before = fingerprint(entry);
    setModified(path.join(extDir, "src/lib/helper.ts"), Date.now() / 1000 + 60);
    expect(fingerprint(entry)).not.toBe(before);
  });

  test("changes when the manifest or the lockfile changes", () => {
    const extDir = makeExtension({ "src/main.ts": "" });
    const entry = path.join(extDir, "src/main.ts");
    const original = fingerprint(entry);

    setModified(path.join(extDir, "package.json"), Date.now() / 1000 + 60);
    const afterManifest = fingerprint(entry);
    expect(afterManifest).not.toBe(original);

    write(path.join(extDir, "bun.lock"));
    const afterBunLock = fingerprint(entry);
    expect(afterBunLock).not.toBe(afterManifest);

    write(path.join(extDir, "node_modules/.package-lock.json"));
    setModified(path.join(extDir, "node_modules/.package-lock.json"), Date.now() / 1000 + 120);
    expect(fingerprint(entry)).not.toBe(afterBunLock);
  });

  test("tracks only the bundle itself for a prebuilt command", () => {
    const extDir = makeExtension({ "main.js": "", "src/unrelated.ts": "" });
    const entry = path.join(extDir, "main.js");
    const before = fingerprint(entry);
    setModified(path.join(extDir, "src/unrelated.ts"), Date.now() / 1000 + 60);
    expect(fingerprint(entry)).toBe(before);
    setModified(entry, Date.now() / 1000 + 60);
    expect(fingerprint(entry)).not.toBe(before);
  });
});

const commandSource = `
import { List } from "@raycast/api";
import { label } from "./label";
export default function Command() {
  return <List><List.Item title={label} /></List>;
}
`;

describe("bundle", () => {
  test("bundles a command so that @raycast/api is the shim and React is the host's copy", async () => {
    const extDir = makeExtension({ "src/hello.tsx": commandSource, "src/label.ts": 'export const label = "from the bundle";' }, "hello");
    const output = await bundle(findEntry());

    expect(output).toBe(path.join(ctx.supportPath, "build", "hello.js"));
    const code = fs.readFileSync(output, "utf8");
    expect(code).toContain(JSON.stringify(shimPath));
    expect(code).toContain("from the bundle");
    expect(code).toContain(path.dirname(require.resolve("react")));
    expect(code).not.toContain(path.join(extDir, "node_modules"));

    const Command = (await import(output)).default;
    const tree = await showScreen(React.createElement(Command));
    expect(find(tree, "List.Item").props.title).toBe("from the bundle");
  });

  test("reuses the cached bundle until a source file changes", async () => {
    const extDir = makeExtension({ "src/cached.ts": "export default () => 1;" }, "cached");
    const entry = findEntry();
    const builds = () => consoleError.mock.calls.filter(([line]) => String(line).startsWith("bundled sample/cached")).length;

    const output = await bundle(entry);
    expect(builds()).toBe(1);
    // A marker in the output shows whether the next call rewrote it.
    fs.appendFileSync(output, "\n// marker");
    expect(await bundle(entry)).toBe(output);
    expect(builds()).toBe(1);
    expect(fs.readFileSync(output, "utf8")).toContain("// marker");

    write(path.join(extDir, "src/cached.ts"), "export default () => 2;");
    setModified(path.join(extDir, "src/cached.ts"), Date.now() / 1000 + 60);
    await bundle(entry);
    expect(builds()).toBe(2);
    expect(fs.readFileSync(output, "utf8")).not.toContain("// marker");
  });

  test("builds again when the output is missing even though the fingerprint matches", async () => {
    makeExtension({ "src/lost.ts": "export default () => 1;" }, "lost");
    const output = await bundle(findEntry());
    fs.rmSync(output);
    expect(await bundle(findEntry())).toBe(output);
    expect(fs.existsSync(output)).toBe(true);
  });

  test("builds again when the fingerprint file is missing", async () => {
    makeExtension({ "src/unstamped.ts": "export default () => 1;" }, "unstamped");
    const output = await bundle(findEntry());
    fs.rmSync(path.join(path.dirname(output), "unstamped.fingerprint"));
    fs.appendFileSync(output, "\n// marker");
    await bundle(findEntry());
    expect(fs.readFileSync(output, "utf8")).not.toContain("// marker");
  });

  test("bundles a prebuilt CommonJS command from beside the manifest", async () => {
    makeExtension({ "legacy.js": 'module.exports = { default: () => "prebuilt" };' }, "legacy");
    const output = await bundle(findEntry());
    const module = await import(output);
    // host.ts unwraps the same shape: a CommonJS bundle arrives as { default: module.exports }.
    expect(module.default.default()).toBe("prebuilt");
  });

  test("fails with the build messages when the command does not compile", async () => {
    makeExtension({ "src/broken.ts": 'import { nothing } from "./does-not-exist";\nexport default nothing;' }, "broken");
    await expect(bundle(findEntry())).rejects.toThrow(/does-not-exist/);
    expect(fs.existsSync(path.join(ctx.supportPath, "build", "broken.fingerprint"))).toBe(false);
  });
});
