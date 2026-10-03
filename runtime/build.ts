//
//  build.ts
//  Project: Floe
//
//  Copyright (Floe) © 2026 René Jiménez
//  Licensed under the GNU AGPLv3

// Finds a command's entry file and bundles it for the host. Reads the extension and command from ctx,
// which host.ts fills in before calling.
import fs from "node:fs";
import path from "node:path";
import { ctx } from "./bridge";

// Bundle the command so that @raycast/api points at our shim and React at the host's copy,
// whatever the extension's node_modules holds. Both stay external so there is one instance of each.
export const shimPath = path.join(import.meta.dir, "api/index.ts");
export async function bundle(entry: string): Promise<string> {
  const outdir = path.join(ctx.supportPath, "build");
  const output = path.join(outdir, `${ctx.commandName}.js`);
  const stamp = path.join(outdir, `${ctx.commandName}.fingerprint`);
  const current = fingerprint(entry);
  if (fs.existsSync(output) && readText(stamp) === current) return output;

  const started = performance.now();
  const result = await build(entry, outdir);
  if (!result.success) throw new Error(result.logs.map(String).join("\n"));
  fs.writeFileSync(stamp, current);
  // host.ts points console at stderr, so this never lands on the protocol stream.
  console.error(`bundled ${ctx.manifest.name}/${ctx.commandName} in ${Math.round(performance.now() - started)} ms`);
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
export function newestChange(target: string): number {
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
export function fingerprint(entry: string): string {
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
    naming: `${ctx.commandName}.js`,
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

export function findEntry(): string {
  const candidates = [
    ...[".tsx", ".ts", ".jsx", ".js"].flatMap((extension) => [
      path.join(ctx.extDir, "src", ctx.commandName + extension),
      path.join(ctx.extDir, "src", ctx.commandName, "index" + extension),
    ]),
    // Extensions installed by Raycast ship one prebuilt CommonJS bundle per command, no src/.
    path.join(ctx.extDir, ctx.commandName + ".js"),
  ];
  const entry = candidates.find((candidate) => fs.existsSync(candidate));
  if (!entry) throw new Error(`no entry file for command "${ctx.commandName}"`);
  return entry;
}
