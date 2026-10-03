//
//  index.ts
//  Project: Floe
//
//  Copyright (Floe) © 2026 René Jiménez
//  Licensed under the GNU GPLv3

// Stand-in for @raycast/api. Components render to plain host elements that renderer.ts serializes;
// everything else either runs locally in Bun or is forwarded to the Swift app over the bridge.
import fs from "fs";
import path from "path";
import React, { createContext, useContext, useEffect, useMemo, useRef, useState } from "react";
import { ctx, send, setPopHandler, setPopToRootHandler } from "../bridge";

const h = React.createElement;
type Props = Record<string, any>;

// Element-valued props (actions, detail, metadata…) travel as named child slots.
function slot(name: string, element: unknown) {
  return element ? h("_slot", { name, key: `_slot_${name}` }, element as React.ReactNode) : null;
}
function host(type: string, slots: string[] = []) {
  const component = (props: Props) => {
    const { children, ...rest } = props;
    const slotted = slots.map((name) => {
      const element = rest[name];
      delete rest[name];
      return slot(name, element);
    });
    return h(type, rest, ...slotted, children);
  };
  component.displayName = type;
  return component as any;
}

// Navigation

type Navigation = { push: (element: React.ReactNode, onPop?: () => void) => void; pop: () => void };
const NavigationContext = createContext<Navigation>({ push() {}, pop() {} });
export const useNavigation = () => useContext(NavigationContext);

export function NavigationRoot({ children }: { children: React.ReactNode }) {
  const [stack, setStack] = useState<{ element: React.ReactNode; onPop?: () => void }[]>([]);
  const stackRef = useRef(stack);
  stackRef.current = stack;

  const navigation = useMemo<Navigation>(
    () => ({
      push: (element, onPop) => setStack((current) => [...current, { element, onPop }]),
      pop: () => {
        stackRef.current.at(-1)?.onPop?.();
        setStack((current) => current.slice(0, -1));
      },
    }),
    [],
  );

  useEffect(() => {
    setPopHandler(() => (stackRef.current.length ? navigation.pop() : send({ type: "exit" })));
    setPopToRootHandler(() => setStack([]));
  }, [navigation]);

  // Lower screens stay mounted so their state survives a push; Swift shows the last one.
  const screens = [children, ...stack.map((entry) => entry.element)];
  return h(
    NavigationContext.Provider,
    { value: navigation },
    screens.map((element, index) => h("_screen", { key: index }, element)),
  );
}

// Views

const metadata = (prefix: string) =>
  Object.assign(host(`${prefix}.Metadata`), {
    Label: host("Metadata.Label"),
    Link: host("Metadata.Link"),
    Separator: host("Metadata.Separator"),
    TagList: Object.assign(host("Metadata.TagList"), { Item: host("Metadata.TagList.Item") }),
  });

// Raycast calls a search bar dropdown's onChange once on mount with the initial value; extensions rely on it.
function firstDropdownValue(children: React.ReactNode): string | undefined {
  for (const child of React.Children.toArray(children)) {
    if (!React.isValidElement(child)) continue;
    const props = child.props as Props;
    if (props.value !== undefined && props.title !== undefined) return props.value;
    const nested = firstDropdownValue(props.children);
    if (nested !== undefined) return nested;
  }
  return undefined;
}
const dropdownStore = () => path.join(ctx.supportPath, "dropdown-values.json");
const dropdown = (prefix: string) => {
  const Host = host(`${prefix}.Dropdown`);
  const Dropdown = (props: Props) => {
    const storeKey = `${ctx.commandName}:${props.id ?? "default"}`;
    const [value, setValue] = useState<string | undefined>(
      () =>
        props.value ??
        (props.storeValue ? readJSON(dropdownStore())[storeKey] : undefined) ??
        props.defaultValue ??
        firstDropdownValue(props.children),
    );
    useEffect(() => {
      if (value !== undefined) props.onChange?.(value);
    }, []);
    const onChange = (next: string) => {
      setValue(next);
      if (props.storeValue) fs.writeFileSync(dropdownStore(), JSON.stringify({ ...readJSON(dropdownStore()), [storeKey]: next }));
      props.onChange?.(next);
    };
    return h(Host, { ...props, value: props.value ?? value, onChange });
  };
  return Object.assign(Dropdown, { Item: host("Dropdown.Item"), Section: host("Dropdown.Section") });
};

export const List = Object.assign(host("List", ["actions", "searchBarAccessory"]), {
  Item: Object.assign(host("List.Item", ["actions", "detail"]), {
    Detail: Object.assign(host("List.Item.Detail", ["metadata"]), { Metadata: metadata("List.Item.Detail") }),
  }),
  Section: host("List.Section"),
  EmptyView: host("EmptyView", ["actions"]),
  Dropdown: dropdown("List"),
});

export const Grid = Object.assign(host("Grid", ["actions", "searchBarAccessory"]), {
  Item: host("Grid.Item", ["actions"]),
  Section: host("Grid.Section"),
  EmptyView: host("EmptyView", ["actions"]),
  Dropdown: dropdown("Grid"),
  Inset: { Small: "small", Medium: "medium", Large: "large" },
  ItemSize: { Small: "small", Medium: "medium", Large: "large" },
  Fit: { Contain: "contain", Fill: "fill" },
});

export const Detail = Object.assign(host("Detail", ["actions", "metadata"]), { Metadata: metadata("Detail") });

export const Form = Object.assign(host("Form", ["actions", "searchBarAccessory"]), {
  TextField: host("Form.TextField"),
  PasswordField: host("Form.PasswordField"),
  TextArea: host("Form.TextArea"),
  Checkbox: host("Form.Checkbox"),
  DatePicker: Object.assign(host("Form.DatePicker"), { Type: { Date: "date", DateTime: "dateTime" } }),
  Dropdown: Object.assign(host("Form.Dropdown"), { Item: host("Dropdown.Item"), Section: host("Dropdown.Section") }),
  TagPicker: Object.assign(host("Form.TagPicker"), { Item: host("Form.TagPicker.Item") }),
  FilePicker: host("Form.FilePicker"),
  Description: host("Form.Description"),
  Separator: host("Form.Separator"),
  LinkAccessory: host("Form.LinkAccessory"),
});

export const MenuBarExtra = Object.assign(host("MenuBarExtra"), {
  Item: host("MenuBarExtra.Item"),
  Section: host("MenuBarExtra.Section"),
  Separator: host("MenuBarExtra.Separator"),
  Submenu: host("MenuBarExtra.Submenu"),
});

// Actions

const BaseAction = host("Action");
function action(defaultTitle: string, defaultIcon: string, run: (props: Props, navigation: Navigation) => unknown) {
  return (props: Props) => {
    const navigation = useNavigation();
    return h("Action", {
      title: props.title ?? defaultTitle,
      icon: props.icon ?? `icon:${defaultIcon}`,
      shortcut: props.shortcut,
      style: props.style,
      onAction: () => run(props, navigation),
    });
  };
}

export const Action = Object.assign(BaseAction, {
  Style: { Regular: "regular", Destructive: "destructive" },
  OpenInBrowser: action("Open in Browser", "Globe", async (props) => {
    await open(props.url);
    props.onOpen?.(props.url);
    await closeMainWindow();
  }),
  Open: action("Open", "Finder", async (props) => {
    await open(props.target, props.application);
    props.onOpen?.(props.target);
    await closeMainWindow();
  }),
  CopyToClipboard: action("Copy to Clipboard", "Clipboard", async (props) => {
    await Clipboard.copy(props.content);
    props.onCopy?.(props.content);
    await showHUD("Copied to Clipboard");
  }),
  Paste: action("Paste", "Clipboard", async (props) => {
    await Clipboard.paste(props.content);
    props.onPaste?.(props.content);
  }),
  Push: action("Open", "ArrowRight", (props, navigation) => {
    navigation.push(props.target, props.onPop);
    props.onPush?.();
  }),
  ShowInFinder: action("Show in Finder", "Finder", async (props) => {
    await showInFinder(props.path);
    props.onShow?.(props.path);
    await closeMainWindow();
  }),
  Trash: action("Move to Trash", "Trash", async (props) => {
    await trash(props.paths);
    props.onTrash?.(props.paths);
  }),
  SubmitForm: (props: Props) =>
    h("Action", { title: props.title ?? "Submit", icon: props.icon, shortcut: props.shortcut, isSubmit: true, onSubmit: props.onSubmit }),
  OpenWith: action("Open With", "Finder", (props) => open(props.path)),
  ToggleQuickLook: action("Quick Look", "Eye", () => unsupported("Quick Look")),
  CreateSnippet: action("Create Snippet", "Document", () => unsupported("Snippets")),
  CreateQuicklink: action("Create Quicklink", "Link", () => unsupported("Quicklinks")),
  PickDate: Object.assign(action("Pick Date", "Calendar", () => unsupported("Date picker")), {
    Type: { Date: "date", DateTime: "dateTime" },
  }),
});

export const ActionPanel = Object.assign(host("ActionPanel"), {
  Section: host("ActionPanel.Section"),
  Submenu: host("ActionPanel.Submenu"),
});

// Feedback

function unsupported(feature: string) {
  return showToast({ style: Toast.Style.Failure, title: `${feature} isn't supported yet` });
}

let nextToastId = 1;
export class Toast {
  static Style = { Success: "success", Failure: "failure", Animated: "animated" } as const;
  private id = nextToastId++;
  private options: Props;
  constructor(options: Props) {
    this.options = { ...options };
  }
  private sync(hidden = false) {
    const { style, title, message } = this.options;
    send({ type: "toast", id: this.id, style: style ?? "success", title: title ?? "", message, hidden });
  }
  get title() { return this.options.title; }
  set title(value: string) { this.options.title = value; this.sync(); }
  get message() { return this.options.message; }
  set message(value: string | undefined) { this.options.message = value; this.sync(); }
  get style() { return this.options.style; }
  set style(value: string) { this.options.style = value; this.sync(); }
  get primaryAction() { return this.options.primaryAction; }
  set primaryAction(value: unknown) { this.options.primaryAction = value; }
  get secondaryAction() { return this.options.secondaryAction; }
  set secondaryAction(value: unknown) { this.options.secondaryAction = value; }
  async show() { this.sync(); }
  async hide() { this.sync(true); }
}

export async function showToast(optionsOrStyle: Props | string, title?: string, message?: string) {
  const options = typeof optionsOrStyle === "string" ? { style: optionsOrStyle, title, message } : optionsOrStyle;
  const toast = new Toast(options);
  await toast.show();
  return toast;
}

export async function showHUD(title: string, _options?: Props) {
  send({ type: "hud", title });
}

export const Alert = { ActionStyle: { Default: "default", Cancel: "cancel", Destructive: "destructive" } };
export async function confirmAlert(options: Props) {
  const escape = (text: string) => String(text ?? "").replace(/\\/g, "\\\\").replace(/"/g, '\\"');
  const confirm = options.primaryAction?.title ?? "OK";
  const cancel = options.dismissAction?.title ?? "Cancel";
  const script = `display alert "${escape(options.title)}" message "${escape(options.message)}" buttons {"${escape(cancel)}", "${escape(confirm)}"} default button 2`;
  const result = Bun.spawnSync(["osascript", "-e", script]);
  const confirmed = result.stdout.toString().includes(`button returned:${confirm}`);
  if (confirmed) await options.primaryAction?.onAction?.();
  else await options.dismissAction?.onAction?.();
  return confirmed;
}

// Window and system

export const PopToRootType = { Default: "default", Immediate: "immediate", Suspended: "suspended" };
export async function closeMainWindow(_options?: Props) {
  send({ type: "close" });
}
export async function popToRoot(_options?: Props) {
  send({ type: "popToRoot" });
}
export async function clearSearchBar(_options?: Props) {
  send({ type: "clearSearchBar" });
}

export async function open(target: string, application?: string | { path?: string; name?: string }) {
  const app = typeof application === "string" ? application : (application?.path ?? application?.name);
  send({ type: "open", target, application: app });
}
export async function showInFinder(target: string) {
  Bun.spawn(["open", "-R", target]);
}
export async function trash(paths: string | string[]) {
  for (const file of [paths].flat()) {
    const destination = path.join(process.env.HOME ?? "", ".Trash", `${path.basename(file)}`);
    fs.renameSync(file, fs.existsSync(destination) ? `${destination} ${Date.now()}` : destination);
  }
}

export const Clipboard = {
  async copy(content: string | number | Props, _options?: Props) {
    const text = typeof content === "object" ? (content.text ?? content.file ?? content.html ?? "") : String(content);
    send({ type: "copy", text });
  },
  async paste(content: string | number | Props) {
    const text = typeof content === "object" ? (content.text ?? content.file ?? "") : String(content);
    send({ type: "paste", text });
  },
  async readText(_options?: Props) {
    const text = Bun.spawnSync(["pbpaste"]).stdout.toString();
    return text.length ? text : undefined;
  },
  async read(_options?: Props) {
    return { text: (await Clipboard.readText()) ?? "" };
  },
  async clear() {
    send({ type: "copy", text: "" });
  },
};

export async function getSelectedText(): Promise<string> {
  throw new Error("Reading the selected text isn't supported yet");
}
export async function getSelectedFinderItems(): Promise<{ path: string }[]> {
  throw new Error("Reading the Finder selection isn't supported yet");
}
type Application = { name: string; path: string; bundleId?: string };
let applications: Application[] | undefined;
export async function getApplications(_path?: string): Promise<Application[]> {
  applications ??= Bun.spawnSync(["mdfind", "-attr", "kMDItemCFBundleIdentifier", "kMDItemContentType == 'com.apple.application-bundle'"])
    .stdout.toString()
    .split("\n")
    .filter(Boolean)
    .map((line) => {
      const [appPath, attribute = ""] = line.split(/\s{3,}kMDItemCFBundleIdentifier = /);
      const bundleId = attribute.trim();
      return { name: path.basename(appPath, ".app"), path: appPath, bundleId: bundleId && bundleId !== "(null)" ? bundleId : undefined };
    });
  return applications;
}
export async function getDefaultApplication(_path: string) {
  return { name: "Finder", path: "/System/Library/CoreServices/Finder.app", bundleId: "com.apple.finder" };
}
export async function getFrontmostApplication() {
  return { name: "Finder", path: "/System/Library/CoreServices/Finder.app", bundleId: "com.apple.finder" };
}

// Storage

function readJSON(file: string): Record<string, any> {
  try {
    return JSON.parse(fs.readFileSync(file, "utf8"));
  } catch {
    return {};
  }
}
const storageFile = () => path.join(ctx.supportPath, "local-storage.json");
const writeStorage = (data: Props) => fs.writeFileSync(storageFile(), JSON.stringify(data));

export const LocalStorage = {
  async getItem<T = string>(key: string) { return readJSON(storageFile())[key] as T | undefined; },
  async setItem(key: string, value: unknown) { writeStorage({ ...readJSON(storageFile()), [key]: value }); },
  async removeItem(key: string) {
    const data = readJSON(storageFile());
    delete data[key];
    writeStorage(data);
  },
  async allItems<T = Props>() { return readJSON(storageFile()) as T; },
  async clear() { writeStorage({}); },
};

type CacheSubscriber = (key: string | undefined, data: string | undefined) => void;
// Methods are arrow properties because @raycast/utils passes them around unbound (cache.subscribe → useSyncExternalStore).
export class Cache {
  private file: string;
  private data: Record<string, string>;
  private subscribers = new Set<CacheSubscriber>();
  constructor(options?: { namespace?: string; capacity?: number }) {
    this.file = path.join(ctx.supportPath, `cache-${options?.namespace ?? "default"}.json`);
    this.data = readJSON(this.file);
  }
  private persist = (key: string | undefined, value: string | undefined) => {
    fs.writeFileSync(this.file, JSON.stringify(this.data));
    this.subscribers.forEach((subscriber) => subscriber(key, value));
  };
  get isEmpty() { return Object.keys(this.data).length === 0; }
  get = (key: string) => this.data[key];
  has = (key: string) => key in this.data;
  set = (key: string, value: string) => { this.data[key] = value; this.persist(key, value); };
  remove = (key: string) => {
    const existed = key in this.data;
    delete this.data[key];
    this.persist(key, undefined);
    return existed;
  };
  clear = (_options?: { notifySubscribers?: boolean }) => { this.data = {}; this.persist(undefined, undefined); };
  subscribe = (subscriber: CacheSubscriber) => {
    this.subscribers.add(subscriber);
    return () => void this.subscribers.delete(subscriber);
  };
}

export function getPreferenceValues<T = Props>(): T {
  // The app resolves defaults, stored values and Keychain secrets and passes the result in.
  if (process.env.FLOE_PREFERENCES) return JSON.parse(process.env.FLOE_PREFERENCES) as T;
  const command = ctx.manifest.commands?.find((candidate) => candidate.name === ctx.commandName);
  const declared = [...(ctx.manifest.preferences ?? []), ...(command?.preferences ?? [])];
  const defaults = Object.fromEntries(declared.filter((pref) => pref.default !== undefined).map((pref) => [pref.name, pref.default]));
  return { ...defaults, ...readJSON(path.join(ctx.supportPath, "preferences.json")) } as T;
}
export async function openExtensionPreferences() {
  send({ type: "openPreferences" });
}
export async function openCommandPreferences() {
  send({ type: "openPreferences" });
}

// Environment

export const LaunchType = { UserInitiated: "userInitiated", Background: "background" };
export const environment = {
  get extensionName() { return ctx.manifest.name; },
  get commandName() { return ctx.commandName; },
  get commandMode() { return ctx.commandMode; },
  get assetsPath() { return path.join(ctx.extDir, "assets"); },
  get supportPath() { return ctx.supportPath; },
  get ownerOrAuthorName() { return ctx.manifest.owner ?? ctx.manifest.author ?? ""; },
  raycastVersion: "1.100.0",
  isDevelopment: true,
  appearance: "dark",
  theme: "dark",
  textSize: "medium",
  launchType: "userInitiated",
  canAccess: (_api: unknown) => false,
};

export async function launchCommand(_options: Props) {
  throw new Error("launchCommand isn't supported yet");
}
export async function updateCommandMetadata(_metadata: Props) {}
export function captureException(error: unknown) {
  console.error(error);
}

export const AI = {
  Creativity: {},
  Model: {},
  ask() {
    throw new Error("AI isn't supported yet");
  },
};
export const OAuth = {
  RedirectMethod: { Web: "web", App: "app", AppURI: "appURI" },
  PKCEClient: class {
    constructor() {
      throw new Error("OAuth isn't supported yet");
    }
  },
};

// Constants

// Icon.Foo → "icon:Foo", Color.Red → "color:Red"; the Swift side maps names to SF Symbols and system colors.
const named = (prefix: string) =>
  new Proxy({} as Record<string, string>, {
    get: (_target, key) => (typeof key === "string" ? `${prefix}:${key}` : undefined),
  });
export const Icon = named("icon");
export const Color = named("color");
export const Image = { Mask: { Circle: "circle", RoundedRectangle: "roundedRectangle" } };

const shortcut = (modifiers: string[], key: string) => ({ modifiers, key });
export const Keyboard = {
  Shortcut: {
    Common: {
      Copy: shortcut(["cmd", "shift"], "c"),
      CopyDeeplink: shortcut(["cmd", "shift"], "c"),
      CopyName: shortcut(["cmd", "shift"], "."),
      CopyPath: shortcut(["cmd", "shift"], ","),
      Duplicate: shortcut(["cmd"], "d"),
      Edit: shortcut(["cmd"], "e"),
      MoveDown: shortcut(["cmd", "shift"], "arrowDown"),
      MoveUp: shortcut(["cmd", "shift"], "arrowUp"),
      New: shortcut(["cmd"], "n"),
      Open: shortcut(["cmd"], "o"),
      OpenWith: shortcut(["cmd", "shift"], "o"),
      Pin: shortcut(["cmd", "shift"], "p"),
      Refresh: shortcut(["cmd"], "r"),
      Remove: shortcut(["ctrl"], "x"),
      RemoveAll: shortcut(["ctrl", "shift"], "x"),
      ToggleQuickLook: shortcut(["cmd"], "y"),
    },
  },
};

// Deprecated names that older store extensions still import

export const ActionPanelItem = Action;
export const ActionPanelSection = ActionPanel.Section;
export const ActionPanelSubmenu = ActionPanel.Submenu;
export const CopyToClipboardAction = Action.CopyToClipboard;
export const OpenInBrowserAction = Action.OpenInBrowser;
export const OpenAction = Action.Open;
export const OpenWithAction = Action.OpenWith;
export const PasteAction = Action.Paste;
export const PushAction = Action.Push;
export const ShowInFinderAction = Action.ShowInFinder;
export const SubmitFormAction = Action.SubmitForm;
export const TrashAction = Action.Trash;
export const ListItem = List.Item;
export const ListSection = List.Section;
export const FormTextField = Form.TextField;
export const FormTextArea = Form.TextArea;
export const FormCheckbox = Form.Checkbox;
export const FormDatePicker = Form.DatePicker;
export const FormDropdown = Form.Dropdown;
export const FormDropdownItem = Form.Dropdown.Item;
export const FormDropdownSection = Form.Dropdown.Section;
export const FormSeparator = Form.Separator;
export const FormTagPicker = Form.TagPicker;
export const FormTagPickerItem = Form.TagPicker.Item;
export const ImageMask = Image.Mask;
export const AlertActionStyle = Alert.ActionStyle;
export const ToastStyle = Toast.Style;
export const copyTextToClipboard = (text: string) => Clipboard.copy(text);
export const pasteText = (text: string) => Clipboard.paste(text);
export const clearClipboard = () => Clipboard.clear();
export const getLocalStorageItem = LocalStorage.getItem;
export const setLocalStorageItem = LocalStorage.setItem;
export const removeLocalStorageItem = LocalStorage.removeItem;
export const allLocalStorageItems = LocalStorage.allItems;
export const clearLocalStorage = LocalStorage.clear;
export const preferences = new Proxy({} as Record<string, { value: unknown }>, {
  get: (_target, key) => ({ value: getPreferenceValues<Props>()[key as string] }),
});
