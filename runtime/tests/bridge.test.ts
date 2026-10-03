//
//  bridge.test.ts
//  Project: Floe
//
//  Copyright (Floe) © 2026 René Jiménez
//  Licensed under the GNU AGPLv3

import { afterEach, describe, expect, spyOn, test } from "bun:test";
import { handlePop, handlePopToRoot, handleReply, request, send, setPopHandler, setPopToRootHandler, setSink } from "../bridge";

afterEach(() => {
  setSink();
  setPopHandler(() => send({ type: "exit" }));
  setPopToRootHandler(() => {});
});

describe("send", () => {
  test("writes one JSON line per message to the sink", () => {
    const lines: string[] = [];
    setSink((line) => lines.push(line));
    send({ type: "hud", title: "line one\nline two" });
    send({ type: "close", skipped: undefined });
    expect(lines).toEqual(['{"type":"hud","title":"line one\\nline two"}\n', '{"type":"close"}\n']);
  });

  test("writes to stdout unless a sink is set, and again once it is reset", () => {
    const stdout = spyOn(process.stdout, "write").mockImplementation(() => true);
    try {
      send({ type: "pong" });
      setSink(() => {});
      send({ type: "ignored" });
      setSink();
      send({ type: "exit" });
      expect(stdout.mock.calls.map(([line]) => line)).toEqual(['{"type":"pong"}\n', '{"type":"exit"}\n']);
    } finally {
      stdout.mockRestore();
    }
  });
});

describe("pop handlers", () => {
  test("the installed handlers receive the app's pop and pop-to-root", () => {
    const calls: string[] = [];
    setPopHandler(() => calls.push("pop"));
    setPopToRootHandler(() => calls.push("popToRoot"));
    handlePop();
    handlePopToRoot();
    expect(calls).toEqual(["pop", "popToRoot"]);
  });
});

describe("requests", () => {
  test("each request gets its own id, and a reply settles only the request it names", async () => {
    const messages: Record<string, any>[] = [];
    setSink((line) => messages.push(JSON.parse(line)));
    const first = request<string>("ai.ask", { prompt: "one" });
    const second = request<string>("ai.ask");
    expect(messages.map((message) => message.type)).toEqual(["request", "request"]);
    expect(messages[0].id).not.toBe(messages[1].id);
    expect(messages[1].params).toEqual({});
    handleReply({ id: messages[1].id, result: "second" });
    handleReply({ id: messages[0].id, error: "first failed" });
    expect(await second).toBe("second");
    await expect(first).rejects.toThrow("first failed");
  });

  test("a reply nobody is waiting for is ignored", () => {
    expect(() => handleReply({ id: -1, result: "stray" })).not.toThrow();
  });
});
