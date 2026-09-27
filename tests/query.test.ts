import { test } from "node:test";
import assert from "node:assert/strict";
import { QueryState } from "../src/query.ts";

test("editing cancels ownership of old results without discarding them", () => {
  const state = new QueryState();
  state.open("hello");
  const id = state.begin();
  state.accept(id, "你好");
  state.edit("world");
  assert.equal(state.accept(id, "旧结果"), false);
  assert.equal(state.output, "你好");
  assert.equal(state.stale, true);
});

test("only the latest query can update output", () => {
  const state = new QueryState();
  const old = state.begin();
  const latest = state.begin();
  assert.equal(state.accept(old, "old"), false);
  assert.equal(state.accept(latest, "new"), true);
});

test("new entry resets direction, editing and retry preserve it", () => {
  const state = new QueryState();
  state.source = "en";
  state.target = "zh";
  state.edit("hello");
  state.begin();
  assert.equal(state.source, "en");
  state.open("goodbye");
  assert.equal(state.source, "auto");
  assert.equal(state.target, "auto");
});

test("swap uses only complete current translation", () => {
  const state = new QueryState();
  state.open("hello");
  state.resolvedSource = "en";
  state.resolvedTarget = "zh";
  state.output = "你好";
  state.complete = true;
  state.mode = "translation";
  state.stale = false;
  assert.equal(state.swap(), true);
  assert.equal(state.input, "你好");
  assert.equal(state.source, "zh");
  assert.equal(state.target, "en");
  state.mode = "dictionary";
  state.output = "hello";
  state.complete = true;
  assert.equal(state.swap(), false);
  assert.equal(state.input, "你好");
});
