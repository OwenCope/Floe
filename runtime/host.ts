//
//  host.ts
//  Project: Floe
//
//  Copyright (Floe) © 2026 René Jiménez
//  Licensed under the GNU GPLv3

// Extension host. Usage: bun host.ts <extensionDir> <commandName> [argumentsJSON]
// Loads one Raycast command, renders it with the custom reconciler, and talks NDJSON with the Swift app.
import fs from "node:fs";
import os from "node:os";
import path from "node:path";
import React from "react";
import { ctx, handlePop, handlePopToRoot, send, type Manifest } from "./bridge";
import { dispatchEvent, render, toError } from "./renderer";
import { NavigationRoot } from "./api/index";

const log = (...parts: unknown[]) =>
  process.stderr.write(parts.map((part) => (typeof part === "string" ? part : Bun.inspect(part))).join(" ") + "\n");
console.log = console.info = console.warn = console.error = console.debug = log;

const [extDir, commandName, argumentsJSON] = process.argv.slice(2);
if (!extDir || !commandName) {
  log("usage: bun host.ts <extensionDir> <commandName> [argumentsJSON]");
  process.exit(2);
}

const manifest: Manifest = JSON.parse(fs.readFileSync(path.join(extDir, "package.json"), "utf8"));
const command = manifest.commands?.find((candidate) => candidate.name === commandName);
if (!command) {
  log(`command "${commandName}" not found in ${manifest.name}`);
  process.exit(2);
}

ctx.extDir = path.resolve(extDir);
ctx.commandName = commandName;
ctx.commandMode = command.mode ?? "view";
ctx.manifest = manifest;
ctx.supportPath = path.join(os.homedir(), "Library/Application Support/Floe/Data", manifest.name);
fs.mkdirSync(ctx.supportPath, { recursive: true });

// Bundle the command so that @raycast/api points at our shim and React at the host's copy,
// whatever the extension's node_modules holds. Both stay external so there is one instance of each.
const shimPath = path.join(import.meta.dir, "api/index.ts");
async function bundle(entry: string): Promise<string> {
  const outdir = path.join(ctx.supportPath, "build");
  const output = path.join(outdir, `${commandName}.js`);
  const stamp = path.join(outdir, `${commandName}.fingerprint`);
  const current = fingerprint(entry);
  if (fs.existsSync(output) && readText(stamp) === current) return output;

  const started = performance.now();
  const result = await build(entry, outdir);
  if (!result.success) throw new Error(result.logs.map(String).join("\n"));
  fs.writeFileSync(stamp, current);
  log(`bundled ${manifest.name}/${commandName} in ${Math.round(performance.now() - started)} ms`);
  return output;
}

function readText(file: string): string | undefined {
  try {
    return fs.readFileSync(file, "utf8");
  } catch {
    return undefined;
  }
}

// Newest modification time under a source tree, skipping dependencies and build output.
function newestChange(target: string): number {
  const stat = fs.statSync(target, { throwIfNoEntry: false });
  if (!stat) return 0;
  if (!stat.isDirectory()) return stat.mtimeMs;
  let newest = stat.mtimeMs;
  for (const entry of fs.readdirSync(target, { withFileTypes: true })) {
    if (entry.name === "node_modules" || entry.name.startsWith(".")) continue;
    newest = Math.max(newest, newestChange(path.join(target, entry.name)));
  }
  return newest;
}

// A cached bundle is reused while the sources, manifest, dependencies, runtime location and Bun are unchanged.
// The shim and React paths are baked into the bundle, so a moved app invalidates it too.
function fingerprint(entry: string): string {
  const sources = path.join(ctx.extDir, "src");
  return JSON.stringify({
    entry,
    sources: newestChange(entry.startsWith(sources + path.sep) ? sources : entry),
    manifest: newestChange(path.join(ctx.extDir, "package.json")),
    dependencies: newestChange(path.join(ctx.extDir, "node_modules", ".package-lock.json")) || newestChange(path.join(ctx.extDir, "bun.lock")),
    shim: shimPath,
    shimChanged: newestChange(path.join(import.meta.dir, "api")),
    react: require.resolve("react"),
    bun: Bun.version,
  });
}

async function build(entry: string, outdir: string) {
  try {
    return await buildUnchecked(entry, outdir);
  } catch (error) {
    // Bun throws an AggregateError whose useful text is in the individual build messages.
    const messages = (error as AggregateError).errors?.map(String).join("\n");
    throw new Error(messages || String(error));
  }
}

function buildUnchecked(entry: string, outdir: string) {
  return Bun.build({
    entrypoints: [entry],
    outdir,
    target: "bun",
    format: "esm",
    naming: `${commandName}.js`,
    plugins: [
      {
        name: "raycast-shim",
        setup(build) {
          build.onResolve({ filter: /^@raycast\/api$/ }, () => ({ path: shimPath, external: true }));
          build.onResolve({ filter: /^react(\/jsx-runtime|\/jsx-dev-runtime)?$/ }, (args) => ({
            path: require.resolve(args.path),
            external: true,
          }));
        },
      },
    ],
  });
}

function findEntry(): string {
  const candidates = [
    ...[".tsx", ".ts", ".jsx", ".js"].flatMap((extension) => [
      path.join(ctx.extDir, "src", commandName + extension),
      path.join(ctx.extDir, "src", commandName, "index" + extension),
    ]),
    // Extensions installed by Raycast ship one prebuilt CommonJS bundle per command, no src/.
    path.join(ctx.extDir, commandName + ".js"),
  ];
  const entry = candidates.find((candidate) => fs.existsSync(candidate));
  if (!entry) throw new Error(`no entry file for command "${commandName}"`);
  return entry;
}

function fail(error: unknown, fatal = true) {
  const err = toError(error);
  log(err.stack ?? err.message);
  send({ type: "error", message: err.message, stack: err.stack, fatal });
}
process.on("uncaughtException", (error) => fail(error));
// A rejected promise is usually one failed request, not a dead command.
process.on("unhandledRejection", (error) => fail(error, false));

let buffered = "";
process.stdin.on("data", (chunk: Buffer) => {
  buffered += chunk.toString("utf8");
  let newline: number;
  while ((newline = buffered.indexOf("\n")) >= 0) {
    const line = buffered.slice(0, newline);
    buffered = buffered.slice(newline + 1);
    if (!line.trim()) continue;
    const message = JSON.parse(line);
    if (message.type === "event") dispatchEvent(message.id, message.prop, message.args ?? []);
    else if (message.type === "pop") handlePop();
    else if (message.type === "popToRoot") handlePopToRoot();
    // The app's watchdog: a host stuck in synchronous code cannot answer.
    else if (message.type === "ping") send({ type: "pong" });
  }
});
process.stdin.on("end", () => process.exit(0));

const launchProps = {
  launchType: "userInitiated",
  arguments: argumentsJSON ? JSON.parse(argumentsJSON) : {},
  fallbackText: undefined,
};

try {
  const module = await import(await bundle(findEntry()));
  // A CommonJS bundle (what Raycast installs) arrives as { default: module.exports }, whose own default is the command.
  const exported = module.default;
  const Command = typeof exported === "object" && exported !== null && "default" in exported ? exported.default : exported;
  if (typeof Command !== "function") throw new Error("command has no default export");
  if (ctx.commandMode === "view") {
    render(React.createElement(NavigationRoot, null, React.createElement(Command, launchProps)));
  } else {
    await Command(launchProps);
    // Give trailing HUD/toast messages a moment to flush before the process goes away.
    setTimeout(() => {
      send({ type: "exit" });
      process.exit(0);
    }, 50);
  }
} catch (error) {
  fail(error);
}
