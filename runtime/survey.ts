//
//  survey.ts
//  Project: Floe
//
//  Copyright (Floe) © 2026 René Jiménez
//  Licensed under the GNU GPLv3

// Compatibility survey: bun survey.ts <dir of extensions> [seconds per command]
// Runs up to two view commands per extension headlessly; no-view commands are skipped since they act on the system.
import fs from "fs";
import path from "path";

const [root, secondsArg] = process.argv.slice(2);
const seconds = Number(secondsArg ?? 10);
type Result = { ext: string; command: string; status: string; detail: string };

const find = (node: any, test: (n: any) => boolean, out: any[] = []) => {
  if (test(node)) out.push(node);
  (node.children ?? []).forEach((child: any) => find(child, test, out));
  return out;
};
const required = (prefs: any[] = []) => prefs.filter((p) => p.required && p.default === undefined).map((p) => p.name);

async function run(ext: string, command: string): Promise<Result> {
  const proc = Bun.spawn(["bun", path.join(import.meta.dir, "host.ts"), path.join(root, ext), command], {
    stdin: "pipe", stdout: "pipe", stderr: "pipe",
  });
  let view = "", items = 0, loading = false, error = "", hasContent = false, buffer = "", probed = false;
  const timer = setTimeout(() => proc.kill(), seconds * 1000);
  const stderr = new Response(proc.stderr).text();
  for await (const chunk of proc.stdout) {
    buffer += new TextDecoder().decode(chunk);
    let newline: number;
    while ((newline = buffer.indexOf("\n")) >= 0) {
      const line = buffer.slice(0, newline);
      buffer = buffer.slice(newline + 1);
      let message: any;
      try { message = JSON.parse(line); } catch { continue; }
      if (message.type === "error") error ||= message.message;
      if (message.type === "toast" && message.style === "failure") error ||= `toast: ${message.title} ${message.message ?? ""}`;
      if (message.type !== "render") continue;
      const top = message.tree.children.at(-1);
      const node = top?.children.find((child: any) => child.type !== "_slot");
      if (!node) continue;
      view = node.type;
      loading = !!node.props.isLoading;
      items = find(node, (n) => /^(List|Grid)\.Item$/.test(n.type)).length;
      hasContent = items > 0 || !!node.props.markdown || find(node, (n) => n.type === "EmptyView" || n.type.startsWith("Form.")).length > 0;
      if (hasContent && !loading) proc.kill();
      // A search command is legitimately empty until someone types, so type something once.
      else if (!probed && !loading && items === 0 && node.handlers?.includes("onSearchTextChange")) {
        probed = true;
        proc.stdin.write(JSON.stringify({ type: "event", id: node.id, prop: "onSearchTextChange", args: ["swift"] }) + "\n");
        proc.stdin.flush();
      }
    }
  }
  clearTimeout(timer);
  const firstError = error || (await stderr).split("\n").find((l) => /error|cannot find|not found|undefined is not/i.test(l) && !/Deprecation/.test(l)) || "";
  let status: string;
  if (view && hasContent) status = view === "Form" ? "form" : "ok";
  else if (error) status = "error";
  else if (view) status = "empty";
  else status = firstError ? "error" : "nothing";
  return { ext, command, status, detail: `${view || "-"} items=${items}${loading ? " loading" : ""}${probed ? " (after typing)" : ""} ${status === "ok" || status === "form" ? "" : firstError.trim().slice(0, 140)}` };
}

const jobs: (() => Promise<Result>)[] = [];
const skipped: Result[] = [];
let noView = 0;
for (const ext of fs.readdirSync(root).sort()) {
  const file = path.join(root, ext, "package.json");
  if (!fs.existsSync(file)) continue;
  const manifest = JSON.parse(fs.readFileSync(file, "utf8"));
  const commands = manifest.commands ?? [];
  noView += commands.filter((c: any) => c.mode !== "view").length;
  const extRequired = required(manifest.preferences);
  const views = commands.filter((c: any) => (c.mode ?? "view") === "view").slice(0, 2);
  for (const command of views) {
    const needs = [...extRequired, ...required(command.preferences)];
    if (needs.length) skipped.push({ ext, command: command.name, status: "needs-prefs", detail: needs.join(", ") });
    else jobs.push(() => run(ext, command.name));
  }
}

const results: Result[] = [...skipped];
let next = 0;
await Promise.all(Array.from({ length: 4 }, async () => {
  while (next < jobs.length) results.push(await jobs[next++]());
}));
results.sort((a, b) => a.status.localeCompare(b.status) || a.ext.localeCompare(b.ext));
for (const r of results) console.log(`${r.status.padEnd(11)} ${(r.ext + "/" + r.command).padEnd(46)} ${r.detail}`);
const counts: Record<string, number> = {};
for (const r of results) counts[r.status] = (counts[r.status] ?? 0) + 1;
console.log("\nTOTAL", results.length, JSON.stringify(counts), `(no-view commands not run: ${noView})`);
