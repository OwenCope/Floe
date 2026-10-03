//
//  system.test.ts
//  Project: Floe
//
//  Copyright (Floe) © 2026 René Jiménez
//  Licensed under the GNU AGPLv3

import { afterEach, beforeEach, describe, expect, mock, spyOn, test } from "bun:test";
import fs from "node:fs";
import path from "node:path";
import * as api from "../api/index";
import { ctx } from "../bridge";
import { installRuntime, sent } from "./support";

const runtime = installRuntime("system-tests");

// Stands in for the macOS tools the shim shells out to, so no dialog, clipboard read or Spotlight query happens.
function stubSpawnSync(stdout: string) {
  const spy = spyOn(Bun, "spawnSync").mockImplementation((() => ({ stdout: Buffer.from(stdout) })) as never);
  return { commands: () => spy.mock.calls.map(([command]) => command as unknown as string[]) };
}

let savedPreferences: string | undefined;
beforeEach(() => {
  savedPreferences = process.env.FLOE_PREFERENCES;
  delete process.env.FLOE_PREFERENCES;
});
afterEach(() => {
  mock.restore();
  if (savedPreferences !== undefined) process.env.FLOE_PREFERENCES = savedPreferences;
});

describe("toasts and HUD", () => {
  test("showToast sends the toast and returns a handle that updates it", async () => {
    const toast = await api.showToast({ style: api.Toast.Style.Animated, title: "Loading", message: "one moment" });
    toast.title = "Done";
    toast.message = undefined;
    toast.style = api.Toast.Style.Success;
    await toast.hide();

    const [shown, retitled, cleared, restyled, hidden] = sent("toast");
    expect(shown).toEqual({ type: "toast", id: shown.id, style: "animated", title: "Loading", message: "one moment", hidden: false });
    expect(retitled).toMatchObject({ id: shown.id, title: "Done", style: "animated" });
    expect(cleared).not.toHaveProperty("message");
    expect(restyled).toMatchObject({ id: shown.id, style: "success", hidden: false });
    expect(hidden).toMatchObject({ id: shown.id, title: "Done", hidden: true });
    expect([toast.title, toast.message, toast.style]).toEqual(["Done", undefined, "success"]);
  });

  test("showToast still accepts the old (style, title, message) form", async () => {
    await api.showToast(api.Toast.Style.Failure, "Could not load", "offline");
    expect(sent("toast")).toEqual([expect.objectContaining({ style: "failure", title: "Could not load", message: "offline" })]);
  });

  test("a toast defaults to a success style and gets its own id", async () => {
    const first = new api.Toast({});
    const second = new api.Toast({ title: "Second" });
    await first.show();
    await second.show();
    const [one, two] = sent("toast");
    expect(one).toMatchObject({ style: "success", title: "", hidden: false });
    expect(two.id).not.toBe(one.id);
  });

  test("toast actions are kept on the handle without sending anything", () => {
    const toast = new api.Toast({ title: "Saved" });
    const undo = { title: "Undo", onAction: () => {} };
    toast.primaryAction = undo;
    toast.secondaryAction = undo;
    expect(toast.primaryAction).toBe(undo);
    expect(toast.secondaryAction).toBe(undo);
    expect(sent()).toEqual([]);
  });

  test("changing the options object after creating the toast does not change the toast", async () => {
    const options = { title: "Original" };
    const toast = new api.Toast(options);
    options.title = "Mutated";
    await toast.show();
    expect(sent("toast")[0].title).toBe("Original");
  });

  test("showHUD sends the title", async () => {
    await api.showHUD("Copied", { clearRootSearch: true });
    expect(sent()).toEqual([{ type: "hud", title: "Copied" }]);
  });
});

describe("confirmAlert", () => {
  const options = (calls: string[]) => ({
    title: 'Delete "notes"?',
    message: String.raw`C:\temp`,
    primaryAction: { title: "Delete", style: api.Alert.ActionStyle.Destructive, onAction: () => calls.push("confirmed") },
    dismissAction: { title: "Keep", onAction: () => calls.push("dismissed") },
  });

  test("resolves true and runs the primary action when its button is pressed", async () => {
    const tool = stubSpawnSync("button returned:Delete\n");
    const calls: string[] = [];
    expect(await api.confirmAlert(options(calls))).toBe(true);
    expect(calls).toEqual(["confirmed"]);

    const [program, flag, script] = tool.commands()[0];
    expect([program, flag]).toEqual(["osascript", "-e"]);
    expect(script).toBe(String.raw`display alert "Delete \"notes\"?" message "C:\\temp" buttons {"Keep", "Delete"} default button 2`);
  });

  test("resolves false and runs the dismiss action otherwise", async () => {
    stubSpawnSync("button returned:Keep\n");
    const calls: string[] = [];
    expect(await api.confirmAlert(options(calls))).toBe(false);
    expect(calls).toEqual(["dismissed"]);
  });

  test("uses OK and Cancel when no actions are given", async () => {
    const tool = stubSpawnSync("button returned:OK\n");
    expect(await api.confirmAlert({ title: "Sure?" })).toBe(true);
    expect(tool.commands()[0][2]).toBe('display alert "Sure?" message "" buttons {"Cancel", "OK"} default button 2');
  });
});

describe("window and system", () => {
  test("window calls each send their message", async () => {
    await api.closeMainWindow({ clearRootSearch: true });
    await api.popToRoot();
    await api.clearSearchBar();
    await api.openExtensionPreferences();
    await api.openCommandPreferences();
    expect(sent().map((message) => message.type)).toEqual(["close", "popToRoot", "clearSearchBar", "openPreferences", "openPreferences"]);
  });

  test("open sends the target with the application as a name, a path, or nothing", async () => {
    await api.open("https://example.com");
    await api.open("/tmp/a.txt", "com.apple.TextEdit");
    await api.open("/tmp/a.txt", { name: "TextEdit" });
    await api.open("/tmp/a.txt", { name: "TextEdit", path: "/Applications/TextEdit.app" });
    expect(sent("open")).toEqual([
      { type: "open", target: "https://example.com" },
      { type: "open", target: "/tmp/a.txt", application: "com.apple.TextEdit" },
      { type: "open", target: "/tmp/a.txt", application: "TextEdit" },
      { type: "open", target: "/tmp/a.txt", application: "/Applications/TextEdit.app" },
    ]);
  });

  test("getApplications parses the Spotlight listing once and reuses it", async () => {
    const tool = stubSpawnSync(
      [
        "/Applications/Safari.app   kMDItemCFBundleIdentifier = com.apple.Safari",
        "/Applications/Odd Tool.app   kMDItemCFBundleIdentifier = (null)",
        "/Applications/Bare.app",
        "",
      ].join("\n"),
    );
    const applications = await api.getApplications();
    expect(applications).toEqual([
      { name: "Safari", path: "/Applications/Safari.app", bundleId: "com.apple.Safari" },
      { name: "Odd Tool", path: "/Applications/Odd Tool.app", bundleId: undefined },
      { name: "Bare", path: "/Applications/Bare.app", bundleId: undefined },
    ]);
    expect(await api.getApplications("/tmp/file.txt")).toBe(applications);
    expect(tool.commands()).toHaveLength(1);
    expect(tool.commands()[0][0]).toBe("mdfind");
  });

  test("the default and frontmost application are Finder for now", async () => {
    expect(await api.getDefaultApplication("/tmp/file.txt")).toMatchObject({ name: "Finder", bundleId: "com.apple.finder" });
    expect(await api.getFrontmostApplication()).toMatchObject({ name: "Finder" });
  });

  test("calls that are not supported yet reject with a message saying so", async () => {
    await expect(api.getSelectedText()).rejects.toThrow("selected text isn't supported yet");
    await expect(api.getSelectedFinderItems()).rejects.toThrow("Finder selection isn't supported yet");
    await expect(api.launchCommand({ name: "other" })).rejects.toThrow("launchCommand isn't supported yet");
    expect(() => api.AI.ask()).toThrow("AI isn't supported yet");
    expect(await api.updateCommandMetadata({ subtitle: "3 unread" })).toBeUndefined();
  });

  test("captureException logs the error", () => {
    const consoleError = spyOn(console, "error").mockImplementation(() => {});
    const error = new Error("captured");
    api.captureException(error);
    expect(consoleError.mock.calls).toEqual([[error]]);
  });
});

describe("Clipboard", () => {
  test("copy sends text from a string, a number, or a content object", async () => {
    await api.Clipboard.copy("plain");
    await api.Clipboard.copy(7);
    await api.Clipboard.copy({ text: "from text" });
    await api.Clipboard.copy({ file: "/tmp/a.png" });
    await api.Clipboard.copy({ html: "<b>bold</b>" });
    await api.Clipboard.copy({});
    expect(sent("copy").map((message) => message.text)).toEqual(["plain", "7", "from text", "/tmp/a.png", "<b>bold</b>", ""]);
  });

  test("paste sends the text to paste", async () => {
    await api.Clipboard.paste("typed");
    await api.Clipboard.paste({ text: "from object" });
    await api.Clipboard.paste({});
    expect(sent()).toEqual([
      { type: "paste", text: "typed" },
      { type: "paste", text: "from object" },
      { type: "paste", text: "" },
    ]);
  });

  test("clear copies an empty string", async () => {
    await api.Clipboard.clear();
    expect(sent()).toEqual([{ type: "copy", text: "" }]);
  });

  test("readText and read return what pbpaste prints", async () => {
    const tool = stubSpawnSync("on the clipboard");
    expect(await api.Clipboard.readText()).toBe("on the clipboard");
    expect(await api.Clipboard.read()).toEqual({ text: "on the clipboard" });
    expect(tool.commands()).toEqual([["pbpaste"], ["pbpaste"]]);
  });

  test("an empty clipboard reads as undefined text", async () => {
    stubSpawnSync("");
    expect(await api.Clipboard.readText()).toBeUndefined();
    expect(await api.Clipboard.read()).toEqual({ text: "" });
  });
});

describe("LocalStorage", () => {
  test("stores, lists, removes and clears values, keeping their types", async () => {
    await api.LocalStorage.clear();
    expect(await api.LocalStorage.getItem("missing")).toBeUndefined();

    await api.LocalStorage.setItem("name", "Ada");
    await api.LocalStorage.setItem("count", 3);
    await api.LocalStorage.setItem("enabled", true);
    expect(await api.LocalStorage.getItem("name")).toBe("Ada");
    expect(await api.LocalStorage.getItem<number>("count")).toBe(3);
    expect(await api.LocalStorage.allItems()).toEqual({ name: "Ada", count: 3, enabled: true });

    await api.LocalStorage.removeItem("count");
    expect(await api.LocalStorage.allItems()).toEqual({ name: "Ada", enabled: true });

    await api.LocalStorage.clear();
    expect(await api.LocalStorage.allItems()).toEqual({});
  });

  test("keeps its values in the extension's support folder", async () => {
    await api.LocalStorage.setItem("kept", "yes");
    expect(JSON.parse(fs.readFileSync(path.join(runtime.supportPath, "local-storage.json"), "utf8")).kept).toBe("yes");
  });

  test("treats a missing or damaged file as empty", async () => {
    fs.writeFileSync(path.join(runtime.supportPath, "local-storage.json"), "{not json");
    expect(await api.LocalStorage.allItems()).toEqual({});
    await api.LocalStorage.setItem("fresh", "start");
    expect(await api.LocalStorage.allItems()).toEqual({ fresh: "start" });
  });
});

describe("Cache", () => {
  test("stores strings and reports what it holds", () => {
    const cache = new api.Cache({ namespace: "basic" });
    expect(cache.isEmpty).toBe(true);
    cache.set("token", "abc");
    expect(cache.isEmpty).toBe(false);
    expect(cache.has("token")).toBe(true);
    expect(cache.get("token")).toBe("abc");
    expect(cache.has("other")).toBe(false);
    expect(cache.get("other")).toBeUndefined();

    expect(cache.remove("token")).toBe(true);
    expect(cache.remove("token")).toBe(false);
    cache.set("a", "1");
    cache.clear();
    expect(cache.isEmpty).toBe(true);
  });

  test("persists per namespace across instances", () => {
    new api.Cache({ namespace: "persisted" }).set("key", "value");
    expect(new api.Cache({ namespace: "persisted" }).get("key")).toBe("value");
    expect(new api.Cache({ namespace: "elsewhere" }).has("key")).toBe(false);
    expect(new api.Cache().has("key")).toBe(false);
    expect(fs.existsSync(path.join(runtime.supportPath, "cache-persisted.json"))).toBe(true);
  });

  test("its methods work when passed around unbound", () => {
    const { set, get, has, remove, clear, subscribe } = new api.Cache({ namespace: "unbound" });
    const seen: unknown[][] = [];
    subscribe((key, data) => seen.push([key, data]));
    set("key", "value");
    expect(get("key")).toBe("value");
    expect(has("key")).toBe(true);
    expect(remove("key")).toBe(true);
    clear();
    expect(seen).toEqual([
      ["key", "value"],
      ["key", undefined],
      [undefined, undefined],
    ]);
  });

  test("tells subscribers about changes until they unsubscribe", () => {
    const cache = new api.Cache({ namespace: "subscribers" });
    const first: unknown[] = [];
    const second: unknown[] = [];
    const unsubscribe = cache.subscribe((key) => first.push(key));
    cache.subscribe((key) => second.push(key));
    cache.set("a", "1");
    unsubscribe();
    cache.set("b", "2");
    expect(first).toEqual(["a"]);
    expect(second).toEqual(["a", "b"]);
  });
});

describe("getPreferenceValues", () => {
  const manifest = {
    name: "system-tests",
    preferences: [{ name: "greeting", default: "Hello" }, { name: "token" }, { name: "shout", default: false }],
    commands: [{ name: "main", preferences: [{ name: "limit", default: 10 }] }, { name: "other", preferences: [{ name: "unrelated", default: 1 }] }],
  };
  const preferencesFile = () => path.join(runtime.supportPath, "preferences.json");
  beforeEach(() => {
    ctx.manifest = manifest;
    fs.rmSync(preferencesFile(), { force: true });
  });

  test("uses what the app passes in the environment, ignoring the manifest", () => {
    process.env.FLOE_PREFERENCES = JSON.stringify({ greeting: "Hi", token: "secret" });
    expect(api.getPreferenceValues()).toEqual({ greeting: "Hi", token: "secret" });
  });

  test("without the app, falls back to the defaults of the extension and the running command", () => {
    expect(api.getPreferenceValues()).toEqual({ greeting: "Hello", shout: false, limit: 10 });
  });

  test("values in preferences.json override the defaults", () => {
    fs.writeFileSync(preferencesFile(), JSON.stringify({ greeting: "Hola", token: "from file" }));
    expect(api.getPreferenceValues()).toEqual({ greeting: "Hola", shout: false, limit: 10, token: "from file" });
  });

  test("a manifest without preferences gives an empty object", () => {
    ctx.manifest = { name: "bare" };
    expect(api.getPreferenceValues()).toEqual({});
  });

  test("the deprecated preferences object reads the same values lazily", () => {
    expect(api.preferences.greeting).toEqual({ value: "Hello" });
    process.env.FLOE_PREFERENCES = JSON.stringify({ greeting: "Hi" });
    expect(api.preferences.greeting.value).toBe("Hi");
    expect(api.preferences.missing).toEqual({ value: undefined });
  });
});

describe("environment", () => {
  test("reflects the running extension and command", () => {
    ctx.manifest = { name: "weather", author: "ada", owner: "team" };
    expect(api.environment.extensionName).toBe("weather");
    expect(api.environment.commandName).toBe("main");
    expect(api.environment.commandMode).toBe("view");
    expect(api.environment.supportPath).toBe(runtime.supportPath);
    expect(api.environment.assetsPath).toBe(path.join(ctx.extDir, "assets"));
    expect(api.environment.ownerOrAuthorName).toBe("team");
    expect(api.environment.canAccess(api.AI)).toBe(false);
    expect(api.environment.launchType).toBe(api.LaunchType.UserInitiated);
  });

  test("falls back from owner to author to an empty name", () => {
    ctx.manifest = { name: "weather", author: "ada" };
    expect(api.environment.ownerOrAuthorName).toBe("ada");
    ctx.manifest = { name: "weather" };
    expect(api.environment.ownerOrAuthorName).toBe("");
  });
});

describe("constants", () => {
  test("Icon and Color turn any name into a tagged string", () => {
    expect(api.Icon.MagnifyingGlass).toBe("icon:MagnifyingGlass");
    expect(api.Icon.SomethingRaycastAddsLater).toBe("icon:SomethingRaycastAddsLater");
    expect(api.Color.Red).toBe("color:Red");
    expect(api.Color.SecondaryText).toBe("color:SecondaryText");
    expect((api.Icon as Record<symbol, unknown>)[Symbol.iterator]).toBeUndefined();
    expect(JSON.stringify({ icon: api.Icon.Star })).toBe('{"icon":"icon:Star"}');
  });

  test("the enums extensions compare against have Raycast's values", () => {
    expect(api.Image.Mask).toEqual({ Circle: "circle", RoundedRectangle: "roundedRectangle" });
    expect(api.Alert.ActionStyle.Destructive).toBe("destructive");
    expect(api.PopToRootType.Immediate).toBe("immediate");
    expect(api.LaunchType.Background).toBe("background");
    expect(api.OAuth.RedirectMethod.Web).toBe("web");
    expect(api.Keyboard.Shortcut.Common.Copy).toEqual({ modifiers: ["cmd", "shift"], key: "c" });
    expect(api.Keyboard.Shortcut.Common.Refresh).toEqual({ modifiers: ["cmd"], key: "r" });
  });
});

describe("OAuth", () => {
  test("creating a client fails, since sign-in does not exist yet", () => {
    expect(() => new api.OAuth.PKCEClient({ providerName: "GitHub" })).toThrow("OAuth isn't supported yet");
  });

  test("every other entry point fails the same way or has no tokens", async () => {
    const client = Object.create(api.OAuth.PKCEClient.prototype) as InstanceType<typeof api.OAuth.PKCEClient>;
    await expect(client.authorizationRequest({ endpoint: "https://example.com" })).rejects.toThrow("OAuth isn't supported yet");
    await expect(client.authorize({})).rejects.toThrow("OAuth isn't supported yet");
    expect(await client.getTokens()).toBeUndefined();
  });
});

describe("deprecated aliases", () => {
  test("point at the current components", () => {
    expect(api.ActionPanelItem).toBe(api.Action);
    expect(api.ActionPanelSection).toBe(api.ActionPanel.Section);
    expect(api.ActionPanelSubmenu).toBe(api.ActionPanel.Submenu);
    expect(api.CopyToClipboardAction).toBe(api.Action.CopyToClipboard);
    expect(api.OpenInBrowserAction).toBe(api.Action.OpenInBrowser);
    expect(api.OpenAction).toBe(api.Action.Open);
    expect(api.OpenWithAction).toBe(api.Action.OpenWith);
    expect(api.PasteAction).toBe(api.Action.Paste);
    expect(api.PushAction).toBe(api.Action.Push);
    expect(api.ShowInFinderAction).toBe(api.Action.ShowInFinder);
    expect(api.SubmitFormAction).toBe(api.Action.SubmitForm);
    expect(api.TrashAction).toBe(api.Action.Trash);
    expect(api.ListItem).toBe(api.List.Item);
    expect(api.ListSection).toBe(api.List.Section);
    expect(api.FormTextField).toBe(api.Form.TextField);
    expect(api.FormTextArea).toBe(api.Form.TextArea);
    expect(api.FormCheckbox).toBe(api.Form.Checkbox);
    expect(api.FormDatePicker).toBe(api.Form.DatePicker);
    expect(api.FormDropdown).toBe(api.Form.Dropdown);
    expect(api.FormDropdownItem).toBe(api.Form.Dropdown.Item);
    expect(api.FormDropdownSection).toBe(api.Form.Dropdown.Section);
    expect(api.FormSeparator).toBe(api.Form.Separator);
    expect(api.FormTagPicker).toBe(api.Form.TagPicker);
    expect(api.FormTagPickerItem).toBe(api.Form.TagPicker.Item);
    expect(api.ImageMask).toBe(api.Image.Mask);
    expect(api.AlertActionStyle).toBe(api.Alert.ActionStyle);
    expect(api.ToastStyle).toBe(api.Toast.Style);
  });

  test("the old clipboard functions send the same messages", async () => {
    await api.copyTextToClipboard("old copy");
    await api.pasteText("old paste");
    await api.clearClipboard();
    expect(sent()).toEqual([
      { type: "copy", text: "old copy" },
      { type: "paste", text: "old paste" },
      { type: "copy", text: "" },
    ]);
  });

  test("the old storage functions read and write LocalStorage", async () => {
    await api.clearLocalStorage();
    await api.setLocalStorageItem("legacy", "value");
    expect(await api.getLocalStorageItem("legacy")).toBe("value");
    expect(await api.LocalStorage.getItem("legacy")).toBe("value");
    expect(await api.allLocalStorageItems()).toEqual({ legacy: "value" });
    await api.removeLocalStorageItem("legacy");
    expect(await api.allLocalStorageItems()).toEqual({});
  });
});
