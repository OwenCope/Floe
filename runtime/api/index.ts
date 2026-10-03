//
//  index.ts
//  Project: Floe
//
//  Copyright (Floe) © 2026 René Jiménez
//  Licensed under the GNU AGPLv3

// Stand-in for @raycast/api. Components render to plain host elements that renderer.ts serializes;
// everything else either runs locally in Bun or is forwarded to the Swift app over the bridge.
import fs from "node:fs";
import path from "node:path";
import React, { createContext, useContext, useEffect, useMemo, useRef, useState } from "react";
import { ctx, request, send, setPopHandler, setPopToRootHandler } from "../bridge";

const h = React.createElement;
// The API is promise-based throughout; most calls here finish synchronously.
const done: Promise<void> = Promise.resolve();
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
  static readonly Style = { Success: "success", Failure: "failure", Animated: "animated" } as const;
  private readonly id = nextToastId++;
  private readonly options: Props;
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
  show(): Promise<void> { this.sync(); return done; }
  hide(): Promise<void> { this.sync(true); return done; }
}

export async function showToast(optionsOrStyle: Props | string, title?: string, message?: string) {
  const options = typeof optionsOrStyle === "string" ? { style: optionsOrStyle, title, message } : optionsOrStyle;
  const toast = new Toast(options);
  await toast.show();
  return toast;
}

export function showHUD(title: string, _options?: Props): Promise<void> {
  send({ type: "hud", title });
  return done;
}

export const Alert = { ActionStyle: { Default: "default", Cancel: "cancel", Destructive: "destructive" } };
export async function confirmAlert(options: Props) {
  const escape = (text: string) => String(text ?? "").replaceAll("\\", String.raw`\\`).replaceAll('"', String.raw`\"`);
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
export function closeMainWindow(_options?: Props): Promise<void> {
  send({ type: "close" });
  return done;
}
export function popToRoot(_options?: Props): Promise<void> {
  send({ type: "popToRoot" });
  return done;
}
export function clearSearchBar(_options?: Props): Promise<void> {
  send({ type: "clearSearchBar" });
  return done;
}

export function open(target: string, application?: string | { path?: string; name?: string }): Promise<void> {
  const app = typeof application === "string" ? application : (application?.path ?? application?.name);
  send({ type: "open", target, application: app });
  return done;
}
export function showInFinder(target: string): Promise<void> {
  Bun.spawn(["open", "-R", target]);
  return done;
}
export function trash(paths: string | string[]): Promise<void> {
  for (const file of [paths].flat()) {
    const destination = path.join(process.env.HOME ?? "", ".Trash", `${path.basename(file)}`);
    fs.renameSync(file, fs.existsSync(destination) ? `${destination} ${Date.now()}` : destination);
  }
  return done;
}

export const Clipboard = {
  copy(content: string | number | Props, _options?: Props): Promise<void> {
    const text = typeof content === "object" ? (content.text ?? content.file ?? content.html ?? "") : String(content);
    send({ type: "copy", text });
    return done;
  },
  paste(content: string | number | Props): Promise<void> {
    const text = typeof content === "object" ? (content.text ?? content.file ?? "") : String(content);
    send({ type: "paste", text });
    return done;
  },
  readText(_options?: Props): Promise<string | undefined> {
    const text = Bun.spawnSync(["pbpaste"]).stdout.toString();
    return Promise.resolve(text.length ? text : undefined);
  },
  async read(_options?: Props) {
    return { text: (await Clipboard.readText()) ?? "" };
  },
  clear(): Promise<void> {
    send({ type: "copy", text: "" });
    return done;
  },
};

export function getSelectedText(): Promise<string> {
  return Promise.reject(new Error("Reading the selected text isn't supported yet"));
}
export function getSelectedFinderItems(): Promise<{ path: string }[]> {
  return Promise.reject(new Error("Reading the Finder selection isn't supported yet"));
}
type Application = { name: string; path: string; bundleId?: string };
let applications: Application[] | undefined;
export function getApplications(_path?: string): Promise<Application[]> {
  applications ??= Bun.spawnSync(["mdfind", "-attr", "kMDItemCFBundleIdentifier", "kMDItemContentType == 'com.apple.application-bundle'"])
    .stdout.toString()
    .split("\n")
    .filter(Boolean)
    .map((line) => {
      // mdfind prints "<path>   kMDItemCFBundleIdentifier = <id>".
      const marker = line.indexOf("kMDItemCFBundleIdentifier = ");
      const appPath = (marker < 0 ? line : line.slice(0, marker)).trim();
      const bundleId = marker < 0 ? "" : line.slice(marker + "kMDItemCFBundleIdentifier = ".length).trim();
      return { name: path.basename(appPath, ".app"), path: appPath, bundleId: bundleId && bundleId !== "(null)" ? bundleId : undefined };
    });
  return Promise.resolve(applications);
}
const finder: Application = { name: "Finder", path: "/System/Library/CoreServices/Finder.app", bundleId: "com.apple.finder" };
export function getDefaultApplication(_path: string): Promise<Application> {
  return Promise.resolve(finder);
}
export function getFrontmostApplication(): Promise<Application> {
  return Promise.resolve(finder);
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
  getItem<T = string>(key: string): Promise<T | undefined> {
    return Promise.resolve(readJSON(storageFile())[key] as T | undefined);
  },
  setItem(key: string, value: unknown): Promise<void> {
    writeStorage({ ...readJSON(storageFile()), [key]: value });
    return done;
  },
  removeItem(key: string): Promise<void> {
    const data = readJSON(storageFile());
    delete data[key];
    writeStorage(data);
    return done;
  },
  allItems<T = Props>(): Promise<T> {
    return Promise.resolve(readJSON(storageFile()) as T);
  },
  clear(): Promise<void> {
    writeStorage({});
    return done;
  },
};

// The bounded implementation lives in cache.ts; this re-export keeps the API surface stable.
export { Cache } from "../cache";

export function getPreferenceValues<T = Props>(): T {
  // The app resolves defaults, stored values and Keychain secrets and passes the result in.
  if (process.env.FLOE_PREFERENCES) return JSON.parse(process.env.FLOE_PREFERENCES) as T;
  const command = ctx.manifest.commands?.find((candidate) => candidate.name === ctx.commandName);
  const declared = [...(ctx.manifest.preferences ?? []), ...(command?.preferences ?? [])];
  const defaults = Object.fromEntries(declared.filter((pref) => pref.default !== undefined).map((pref) => [pref.name, pref.default]));
  return { ...defaults, ...readJSON(path.join(ctx.supportPath, "preferences.json")) } as T;
}
export function openExtensionPreferences(): Promise<void> {
  send({ type: "openPreferences" });
  return done;
}
export function openCommandPreferences(): Promise<void> {
  send({ type: "openPreferences" });
  return done;
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
  // The app sets FLOE_AI when AI.ask has something to answer it: an installed tool or a filled-in API.
  canAccess: (api: unknown) => api === AI && process.env.FLOE_AI === "1",
};

export function launchCommand(_options: Props): Promise<void> {
  return Promise.reject(new Error("launchCommand isn't supported yet"));
}
// Subtitles set from a command aren't shown anywhere yet, so there is nothing to update.
export function updateCommandMetadata(_metadata: Props): Promise<void> {
  return done;
}
export function captureException(error: unknown) {
  console.error(error);
}

type AskOptions = { model?: string; creativity?: unknown; signal?: AbortSignal };
export const AI = {
  // Creativity is a plain string or number in Raycast, and the tools Floe runs take none.
  Creativity: {},
  // AI.Model.Anthropic_Claude_Sonnet → "Anthropic_Claude_Sonnet"; the app picks the closest model the installed tool has.
  Model: new Proxy({} as Record<string, string>, {
    get: (_target, key) => (typeof key === "string" ? key : undefined),
  }),
  // Answered by the app, with what Settings › General › AI says: an installed tool or an API.
  ask(prompt: string, options: AskOptions = {}) {
    const listeners: ((text: string) => void)[] = [];
    const emit = (text: string) => listeners.forEach((listener) => listener(text));
    let streamed = false;
    const onChunk = (chunk: string) => {
      streamed = true;
      emit(chunk);
    };
    const answer = request<string>("ai.ask", { prompt, model: options.model }, { signal: options.signal, onChunk }).then((text) => {
      // An answer that arrived whole still fires "data", once, with all of it.
      if (!streamed) emit(text);
      return text;
    });
    return Object.assign(answer, {
      on(event: string, listener: (text: string) => void) {
        if (event === "data") listeners.push(listener);
      },
    });
  },
};
// A preference that takes a token or key, which most extensions accept in place of signing in.
function tokenPreference() {
  const command = ctx.manifest.commands?.find((candidate) => candidate.name === ctx.commandName);
  const declared = [...(ctx.manifest.preferences ?? []), ...(command?.preferences ?? [])];
  const secrets = declared.filter((preference) => preference.type === "password");
  const named = (preference: { name: string; title?: string }) => /token|api[ _-]?key|secret/i.test(`${preference.name} ${preference.title ?? ""}`);
  return secrets.find(named) ?? secrets[0] ?? declared.find(named);
}
// Floe has no sign-in of its own, and doesn't borrow Raycast's: say so, and name the way that does work.
function signInUnavailable(provider?: string) {
  const preference = tokenPreference();
  const service = provider ? ` to ${provider}` : "";
  const instead = preference
    ? `Add "${preference.title ?? preference.name}" in this extension's preferences instead.`
    : "This extension has no token preference to use instead.";
  return new Error(`Floe can't sign in${service} yet. ${instead}`);
}

export const OAuth = {
  RedirectMethod: { Web: "web", App: "app", AppURI: "appURI" },
  // Creating a client works, because extensions create one even when a token preference makes it unnecessary.
  // Only starting a sign-in fails.
  PKCEClient: class {
    private readonly providerName?: string;
    constructor(options?: Props) {
      this.providerName = options?.providerName;
    }
    authorizationRequest(_options: Props): Promise<never> {
      return Promise.reject(signInUnavailable(this.providerName));
    }
    authorize(_request: Props): Promise<never> {
      return Promise.reject(signInUnavailable(this.providerName));
    }
    setTokens(_tokens: Props): Promise<never> {
      return Promise.reject(signInUnavailable(this.providerName));
    }
    getTokens(): Promise<undefined> {
      return Promise.resolve(undefined);
    }
    removeTokens(): Promise<void> {
      return done;
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
