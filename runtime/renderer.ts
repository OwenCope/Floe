//
//  renderer.ts
//  Project: Floe
//
//  Copyright (Floe) © 2026 René Jiménez
//  Licensed under the GNU GPLv3

// Custom React renderer: keeps a plain object tree and ships it to Swift as JSON after each commit.
import React from "react";
import Reconciler from "react-reconciler";
import { ConcurrentRoot, DefaultEventPriority } from "react-reconciler/constants";
import { send } from "./bridge";

type Instance = {
  id: number;
  type: string;
  props: Record<string, unknown>;
  children: (Instance | TextInstance)[];
};
type TextInstance = { id: number; text: string };
type Child = Instance | TextInstance;

let nextId = 1;
const instances = new Map<number, Instance>();
const container: Instance = { id: 0, type: "root", props: {}, children: [] };

function remove(parent: Instance, child: Child) {
  const index = parent.children.indexOf(child);
  if (index >= 0) parent.children.splice(index, 1);
}
function append(parent: Instance, child: Child) {
  remove(parent, child);
  parent.children.push(child);
}
function insertBefore(parent: Instance, child: Child, before: Child) {
  remove(parent, child);
  const index = parent.children.indexOf(before);
  if (index < 0) parent.children.push(child);
  else parent.children.splice(index, 0, child);
}
function forget(child: Child) {
  if ("text" in child) return;
  instances.delete(child.id);
  child.children.forEach(forget);
}

// Props can hold anything an extension passes: functions, elements, class instances, cycles.
function plain(value: unknown, seen: Set<object>, depth = 0): unknown {
  if (value === null || typeof value !== "object") return typeof value === "function" || typeof value === "symbol" ? undefined : value;
  if (value instanceof Date) return value.toISOString();
  if (React.isValidElement(value) || seen.has(value) || depth > 8) return undefined;
  seen.add(value);
  const result = Array.isArray(value)
    ? value.map((item) => plain(item, seen, depth + 1) ?? null)
    : Object.fromEntries(Object.entries(value).map(([key, item]) => [key, plain(item, seen, depth + 1)]));
  seen.delete(value);
  return result;
}

function serialize(node: Child): unknown {
  if ("text" in node) return { id: node.id, type: "#text", text: node.text };
  const props: Record<string, unknown> = {};
  const handlers: string[] = [];
  for (const [key, value] of Object.entries(node.props)) {
    if (key === "children" || key === "ref" || value === undefined) continue;
    if (typeof value === "function") handlers.push(key);
    else props[key] = plain(value, new Set());
  }
  return { id: node.id, type: node.type, props, handlers, children: node.children.map(serialize) };
}

// Navigation keeps lower screens mounted so Back can restore them, but Swift only shows the last one:
// the envelope keeps every non-screen root child in place while hidden screen subtrees are skipped
// before serialization ever walks them. The live tree is not touched.
function serializeRoot(root: Instance) {
  const visible = root.children.findLast((child) => child.type === "_screen");
  return {
    id: root.id,
    type: root.type,
    props: {},
    handlers: [],
    children: root.children.flatMap((child) => (child !== visible && child.type === "_screen" ? [] : [serialize(child)])),
  };
}

let flushScheduled = false;
function scheduleFlush() {
  if (flushScheduled) return;
  flushScheduled = true;
  setTimeout(() => {
    flushScheduled = false;
    send({ type: "render", tree: serializeRoot(container) });
  }, 4);
}

let updatePriority = 0;

const reconciler = Reconciler({
  supportsMutation: true,
  supportsPersistence: false,
  supportsHydration: false,
  isPrimaryRenderer: true,
  noTimeout: -1,
  scheduleTimeout: setTimeout,
  cancelTimeout: clearTimeout,
  supportsMicrotasks: true,
  scheduleMicrotask: queueMicrotask,

  createInstance(type: string, props: Record<string, unknown>) {
    const instance: Instance = { id: nextId++, type, props, children: [] };
    instances.set(instance.id, instance);
    return instance;
  },
  createTextInstance: (text: string): TextInstance => ({ id: nextId++, text }),
  // Initial children are freshly created, never moves, so no removal scan is needed before pushing.
  appendInitialChild(parent, child) {
    parent.children.push(child);
  },
  appendChild: append,
  appendChildToContainer: append,
  insertBefore,
  insertInContainerBefore: insertBefore,
  removeChild(parent: Instance, child: Child) {
    remove(parent, child);
    forget(child);
  },
  removeChildFromContainer(parent: Instance, child: Child) {
    remove(parent, child);
    forget(child);
  },
  commitUpdate(instance: Instance, _type: string, _oldProps: unknown, newProps: Record<string, unknown>) {
    instance.props = newProps;
  },
  commitTextUpdate(instance: TextInstance, _oldText: string, newText: string) {
    instance.text = newText;
  },
  clearContainer(root: Instance) {
    root.children.forEach(forget);
    root.children = [];
  },
  finalizeInitialChildren: () => false,
  shouldSetTextContent: () => false,
  getRootHostContext: () => ({}),
  getChildHostContext: (context: unknown) => context,
  getPublicInstance: (instance: unknown) => instance,
  prepareForCommit: () => null,
  resetAfterCommit: scheduleFlush,
  preparePortalMount() {},
  hideInstance() {},
  unhideInstance() {},
  hideTextInstance() {},
  unhideTextInstance() {},
  detachDeletedInstance() {},
  getInstanceFromNode: () => null,
  beforeActiveInstanceBlur() {},
  afterActiveInstanceBlur() {},
  prepareScopeUpdate() {},
  getInstanceFromScope: () => null,
  setCurrentUpdatePriority(priority: number) {
    updatePriority = priority;
  },
  getCurrentUpdatePriority: () => updatePriority,
  resolveUpdatePriority: () => updatePriority || DefaultEventPriority,
  maySuspendCommit: () => false,
  shouldAttemptEagerTransition: () => false,
  requestPostPaintCallback() {},
  NotPendingTransition: null,
  HostTransitionContext: React.createContext(null),
  resetFormInstance() {},
  trackSchedulerEvent() {},
  resolveEventType: () => null,
  resolveEventTimeStamp: () => -1.1,
  preloadInstance: () => true,
  startSuspendingCommit() {},
  suspendInstance() {},
  waitForCommitToBeReady: () => null,
} as never);

// Extensions throw strings and plain objects as well as Errors.
export function toError(error: unknown): Error {
  if (error instanceof Error) return error;
  return new Error(typeof error === "string" ? error : JSON.stringify(error));
}

// Fatal errors replace the view with an error screen; the rest show as a failure toast.
export function reportError(error: unknown, fatal = false) {
  const err = toError(error);
  console.error(err.stack ?? err.message);
  send({ type: "error", message: err.message, stack: err.stack, fatal });
}

export function render(element: React.ReactElement) {
  const root = reconciler.createContainer(
    container,
    ConcurrentRoot,
    null,
    false,
    null,
    "",
    (error: unknown) => reportError(error, true),
    (error: unknown) => reportError(error),
    (error: unknown) => reportError(error),
    null,
  );
  reconciler.updateContainer(element, root, null, null);
}

// The Swift side tags dates as { $date: iso } since JSON has no date type.
function revive(value: unknown): unknown {
  if (Array.isArray(value)) return value.map(revive);
  if (value && typeof value === "object") {
    const record = value as Record<string, unknown>;
    if (typeof record.$date === "string") return new Date(record.$date);
    return Object.fromEntries(Object.entries(record).map(([key, item]) => [key, revive(item)]));
  }
  return value;
}

export function dispatchEvent(id: number, prop: string, args: unknown[]) {
  const handler = instances.get(id)?.props[prop];
  if (typeof handler !== "function") return;
  try {
    const result = handler(...args.map(revive));
    if (result instanceof Promise) result.catch(reportError);
  } catch (error) {
    reportError(error);
  }
}
