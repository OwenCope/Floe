//
//  smoke.ts
//  Project: Floe
//
//  Copyright (Floe) © 2026 René Jiménez
//  Licensed under the GNU AGPLv3

// Drives host.ts headlessly: bun smoke.ts <extDir> <command>. Prints a summary of each render, then
// runs the second action, the first action, and pops back out. SMOKE_PASSIVE=1 stops at the first list.
import { findNodes, hostMessages, isItem, sendToHost, startHost, topView, type TreeNode } from "./testing";

const [extDir, command] = process.argv.slice(2);
const proc = startHost(extDir, command, "inherit");
const passive = Boolean(process.env.SMOKE_PASSIVE);

function finish(code: number): never {
  clearTimeout(timer);
  proc.kill();
  process.exit(code);
}

const timer = setTimeout(() => {
  console.log("TIMEOUT");
  finish(1);
}, Number(process.env.SMOKE_TIMEOUT ?? 15000));

const short = (value: unknown, length: number) => JSON.stringify(value)?.slice(0, length);
const titles = (actions: TreeNode[]) => actions.map((action) => action.props.title).join(" | ");
const runAction = (action: TreeNode) => sendToHost(proc, { type: "event", id: action.id, prop: "onAction", args: [] });

let step = 0;
for await (const message of hostMessages(proc.stdout)) {
  if (message.type !== "render" || !message.tree) {
    console.log("MSG", JSON.stringify(message).slice(0, 300));
    if (message.type === "exit") finish(0);
    continue;
  }
  const { screens, top, view } = topView(message.tree);
  if (!top) continue;
  const items = findNodes(top, isItem);
  console.log(
    `RENDER screens=${screens.length} view=${view?.type} loading=${view?.props.isLoading ?? false} items=${items.length} ` +
      `first=${short(items[0]?.props.title, 80)} icon=${short(items[0]?.props.icon, 60)} md=${short(view?.props.markdown, 50)}`,
  );
  const actions = findNodes(items[0] ?? top, (node) => node.type === "Action");
  if (passive) {
    if (items.length > 0) {
      console.log("ACTIONS", titles(actions));
      finish(0);
    }
    continue;
  }
  if (step === 0 && items.length > 0) {
    step = 1;
    console.log("ACTIONS", titles(actions));
    runAction(actions[1]);
  } else if (step === 1) {
    step = 2;
    runAction(actions[0]);
  } else if (step === 2 && screens.length === 2) {
    step = 3;
    sendToHost(proc, { type: "pop" });
  } else if (step === 3 && screens.length === 1) {
    step = 4;
    sendToHost(proc, { type: "pop" });
  }
}
