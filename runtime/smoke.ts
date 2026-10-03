//
//  smoke.ts
//  Project: Floe
//
//  Copyright (Floe) © 2026 René Jiménez
//  Licensed under the GNU GPLv3

// Drives host.ts headlessly: bun smoke.ts <extDir> <command>. Prints a summary of each render.
const [extDir, command] = process.argv.slice(2);
const proc = Bun.spawn(["bun", import.meta.dir + "/host.ts", extDir, command], { stdin: "pipe", stdout: "pipe", stderr: "inherit" });
const find = (node: any, type: string, out: any[] = []) => { if (node.type === type) out.push(node); (node.children ?? []).forEach((c: any) => find(c, type, out)); return out; };
const sendMsg = (m: any) => { proc.stdin.write(JSON.stringify(m) + "\n"); proc.stdin.flush(); };
let step = 0, buf = "";
const timer = setTimeout(() => { console.log("TIMEOUT"); proc.kill(); process.exit(1); }, Number(process.env.SMOKE_TIMEOUT ?? 15000));
for await (const chunk of proc.stdout) {
  buf += new TextDecoder().decode(chunk);
  let i; while ((i = buf.indexOf("\n")) >= 0) {
    const msg = JSON.parse(buf.slice(0, i)); buf = buf.slice(i + 1);
    if (msg.type !== "render") { console.log("MSG", JSON.stringify(msg).slice(0, 300)); if (msg.type === "exit") { clearTimeout(timer); proc.kill(); process.exit(0); } continue; }
    const screens = msg.tree.children; const top = screens.at(-1); const view = top.children.find((c: any) => c.type !== "_slot");
    const items = [...find(top, "List.Item"), ...find(top, "Grid.Item")];
    console.log(`RENDER screens=${screens.length} view=${view?.type} loading=${view?.props.isLoading ?? false} items=${items.length} first=${JSON.stringify(items[0]?.props.title)?.slice(0, 80)} icon=${JSON.stringify(items[0]?.props.icon)?.slice(0, 60)} md=${JSON.stringify(view?.props.markdown)?.slice(0, 50)}`);
    if (process.env.SMOKE_PASSIVE) { if (items.length) { console.log("ACTIONS", find(items[0], "Action").map((a: any) => a.props.title).join(" | ")); clearTimeout(timer); proc.kill(); process.exit(0); } continue; }
    const actions = find(items[0] ?? top, "Action");
    if (step === 0 && items.length) { step = 1; console.log("ACTIONS", actions.map((a: any) => a.props.title).join(" | ")); sendMsg({ type: "event", id: actions[1].id, prop: "onAction", args: [] }); }
    else if (step === 1) { step = 2; sendMsg({ type: "event", id: actions[0].id, prop: "onAction", args: [] }); }
    else if (step === 2 && screens.length === 2) { step = 3; sendMsg({ type: "pop" }); }
    else if (step === 3 && screens.length === 1) { step = 4; sendMsg({ type: "pop" }); }
  }
}
