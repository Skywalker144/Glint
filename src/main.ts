import { invoke, Channel } from "@tauri-apps/api/core";
import { listen } from "@tauri-apps/api/event";
import { getCurrentWindow } from "@tauri-apps/api/window";
import { QueryState, type Mode } from "./query.ts";
import type { Card, Prepared, Settings, SavedWord } from "./types.ts";
import "./style.css";

const root = document.querySelector<HTMLDivElement>("#app")!;
root.innerHTML = `
  <header data-tauri-drag-region>
    <button id="close" class="close" title="收起 · Esc" aria-label="收起">×</button>
    <span class="brand" data-tauri-drag-region>✦ <b>Glint</b></span>
    <nav><button id="favorite" title="收藏" aria-label="收藏" disabled>☆</button><button id="book" title="生词本">生词本</button><button id="pin" title="固定窗口" aria-pressed="false">固定</button><button id="settings" title="设置" aria-label="设置">⚙</button></nav>
  </header>
  <main id="query-view">
    <div class="input-wrap"><textarea id="input" rows="3" placeholder="输入单词、短语或需要翻译的文字…" aria-label="原文" spellcheck="false"></textarea><button id="submit" class="submit" title="查询 · Enter" aria-label="查询">↵</button></div>
    <details class="context-field"><summary>添加语境（可选）</summary><textarea id="context" rows="2" placeholder="粘贴单词所在的句子，收藏时一并保存" aria-label="语境"></textarea></details>
    <div class="languages"><select id="source" aria-label="源语言"></select><button id="swap" title="交换语言" aria-label="交换语言">⇄</button><select id="target" aria-label="目标语言"></select><button id="auto" class="subtle">恢复自动</button></div>
    <div class="modebar"><div role="tablist" aria-label="查询模式"><button id="dictionary" role="tab" aria-selected="true">词典</button><button id="translation" role="tab" aria-selected="false">翻译</button></div><span id="state"></span></div>
    <section id="result"><div class="empty"><span class="spark">✦</span><h1>让理解，自然发生。</h1><p>查一个词，读懂一句话。</p><small>Enter 查询 · Shift + Enter 换行</small></div></section>
    <footer><span id="origin">本地词典 · 离线可用</span><div><button id="copy" hidden>复制译文</button><button id="stop" hidden>停止</button><button id="retry" hidden>重试</button></div></footer>
  </main>
  <main id="settings-view" hidden><div class="section-heading"><h1>设置</h1><button class="back">返回</button></div>
    <form id="settings-form"><p class="eyebrow">AI 翻译服务</p><label>API 基础地址<input id="endpoint" type="url" required></label><label>模型<input id="model" required></label><label>API Key<input id="key" type="password" autocomplete="off" placeholder="输入密钥，保存在系统钥匙串"></label><p id="key-state" class="hint"></p>
    <p class="eyebrow">全局快捷键</p><label>划词翻译<input id="shortcut-0" class="shortcut" readonly aria-label="录制划词翻译快捷键"></label><label>输入翻译<input id="shortcut-1" class="shortcut" readonly aria-label="录制输入翻译快捷键"></label><label>截图翻译<input id="shortcut-2" class="shortcut" readonly aria-label="录制截图翻译快捷键"></label><p class="hint">点击快捷键后按下新组合，需包含 ⌘、⌥ 或 ⌃。冲突时保留原绑定。</p><div class="actions"><button type="button" id="test">测试连接</button><button type="submit" class="primary">保存设置</button></div></form>
    <details class="permissions"><summary>取词与截图权限</summary><p>在系统设置 → 隐私与安全性中，为 Glint 开启「辅助功能」和「屏幕与系统音频录制」，然后重新启动应用。</p></details>
  </main>
  <main id="book-view" hidden><div class="section-heading"><h1>生词本 <small id="word-count"></small></h1><button class="back">返回</button></div><input id="search" type="search" placeholder="搜索原词、释义或语境" aria-label="搜索生词本"><div class="actions"><button id="import">导入</button><button id="export">导出</button></div><div id="words"></div></main>
  <div id="notice" role="status" hidden></div>`;

function element<T extends HTMLElement = HTMLElement>(id: string): T {
  return document.getElementById(id) as T;
}
function report(error: unknown) {
  element("notice").textContent = String(error);
  element("notice").hidden = false;
}
function clearNotice() {
  element("notice").hidden = true;
}
function action(id: string, handler: () => unknown) {
  element(id).addEventListener("click", () => {
    clearNotice();
    Promise.resolve().then(handler).catch(report);
  });
}
function escape(text: string) {
  return text.replace(
    /[&<>"']/g,
    (c) =>
      ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;" })[
        c
      ]!,
  );
}

const state = new QueryState();
const input = element<HTMLTextAreaElement>("input");
const result = element("result");
let card: Card | null = null;
let localCard: Card | null = null;
let savedWords: SavedWord[] = [];
let pinned = false;
let busy = false;
let view = "query";
const languages: Record<string, string> = {
  auto: "自动",
  zh: "中文",
  en: "英语",
  ja: "日语",
  ko: "韩语",
  fr: "法语",
  de: "德语",
  es: "西班牙语",
  ru: "俄语",
  it: "意大利语",
  pt: "葡萄牙语",
};
for (const id of ["source", "target"]) {
  element(id).innerHTML = Object.entries(languages)
    .map(([code, name]) => `<option value="${code}">${name}</option>`)
    .join("");
}

function controls() {
  element<HTMLButtonElement>("favorite").disabled =
    !card || state.stale || busy;
  element<HTMLButtonElement>("swap").disabled =
    !state.resolvedSource || !state.resolvedTarget || busy;
  element("stop").hidden = !busy;
  element("retry").hidden = !state.input.trim() || busy;
  element("copy").hidden = state.mode !== "translation" || !state.output;
  element("state").textContent = busy
    ? "正在查询…"
    : state.stale
      ? "原文已修改 · 待查询"
      : "";
  element("dictionary").setAttribute(
    "aria-selected",
    String(state.mode === "dictionary"),
  );
  element("translation").setAttribute(
    "aria-selected",
    String(state.mode === "translation"),
  );
  for (const id of ["source", "target"] as const) {
    const select = element<HTMLSelectElement>(id);
    select.value = state[id];
    const resolved =
      id === "source" ? state.resolvedSource : state.resolvedTarget;
    select.options[0].text = resolved
      ? `自动（${languages[resolved] ?? resolved}）`
      : "自动";
  }
}

async function stop() {
  const previous = state.request;
  state.request++;
  busy = false;
  state.complete = false;
  controls();
  await invoke("cancel", { id: previous });
}

async function showView(next: string) {
  view = next;
  for (const name of ["query", "settings", "book"])
    element(`${name}-view`).hidden = name !== next;
  await invoke("pin", { pinned: pinned || next !== "query" });
  if (next === "query") input.focus();
}

function renderCard(value: Card) {
  card = value;
  result.innerHTML = `<div class="word-heading"><h1>${escape(value.entry.word)}</h1><button id="speak" class="subtle">◖ 系统朗读</button></div>
    ${value.entry.word !== value.original ? `<p class="query-original">原查询：${escape(value.original)}</p>` : ""}
    ${value.entry.phonetic ? `<p class="phonetic">/${escape(value.entry.phonetic)}/</p>` : ""}
    ${value.relations.length ? `<div class="relations">${value.relations.map((r) => `<div>${escape(value.original)} → <button class="lemma" data-lemma="${escape(r.lemma)}">${escape(r.lemma)}</button><span>${escape(r.relation)}</span></div>`).join("")}${value.confirmed ? "" : "<small>保留原词义；词形关系不代表同一义项。</small>"}</div>` : ""}
    <div class="definitions">${value.entry.translation
      .split("\n")
      .filter(Boolean)
      .map((line) => `<p>${escape(line)}</p>`)
      .join("")}</div>
    ${value.entry.definition ? `<details><summary>${value.source === "ECDICT" ? "英文释义" : "例句与补充"}</summary><p class="multiline">${escape(value.entry.definition)}</p></details>` : ""}
    ${value.source === "ECDICT" ? '<button id="supplement" class="supplement">用 AI 补充例句与辨析</button><div id="supplement-result"></div>' : ""}`;
  element("origin").textContent =
    value.source === "ECDICT"
      ? "ECDICT · 本地词典"
      : "AI 释义 · 请结合语境判断";
  action("speak", () => invoke("speak", { text: value.entry.word }));
  result.querySelectorAll<HTMLButtonElement>("[data-lemma]").forEach(
    (button) =>
      (button.onclick = () => {
        input.value = button.dataset.lemma!;
        state.edit(input.value);
        void query("dictionary");
      }),
  );
  if (value.source === "ECDICT") action("supplement", supplement);
  controls();
}

async function supplement() {
  if (!localCard || busy || state.stale) return;
  const id = state.begin();
  busy = true;
  controls();
  try {
    const channel = new Channel<{ text: string }>();
    const response = await invoke<string>("translate", {
      id,
      text: state.input,
      source: state.resolvedSource,
      target: state.resolvedTarget,
      dictionary: true,
      channel,
    });
    if (id !== state.request) return;
    const extra: Card = JSON.parse(response);
    element("supplement-result").innerHTML =
      `<details open><summary>AI 补充 · ${escape(extra.source)}</summary><p class="multiline">${escape(extra.entry.definition || extra.entry.translation)}</p></details>`;
  } catch (error) {
    if (id === state.request) report(error);
  } finally {
    if (id === state.request) {
      busy = false;
      state.stale = false;
      controls();
    }
  }
}

async function query(mode?: Mode) {
  if (!input.value.trim()) return;
  await stop();
  clearNotice();
  state.input = input.value.trim();
  const id = state.begin();
  busy = true;
  controls();
  try {
    const prepared = await invoke<Prepared>("prepare", {
      text: state.input,
      source: state.source,
      target: state.target,
    });
    if (id !== state.request) return;
    state.resolvedSource = prepared.source;
    state.resolvedTarget = prepared.target;
    state.mode = mode ?? prepared.mode;
    localCard = prepared.card;
    if (state.mode === "dictionary" && prepared.card) {
      state.stale = false;
      state.complete = true;
      state.output = "";
      renderCard(prepared.card);
      return;
    }
    const channel = new Channel<{ text: string }>();
    channel.onmessage = ({ text }) => {
      if (state.accept(id, text)) {
        element("origin").textContent = "AI 翻译";
        card = null;
        result.innerHTML = `<p class="translation-text">${escape(text)}</p>`;
        controls();
      }
    };
    const response = await invoke<string>("translate", {
      id,
      text: state.input,
      source: prepared.source,
      target: prepared.target,
      dictionary: state.mode === "dictionary",
      channel,
    });
    if (id !== state.request) return;
    state.stale = false;
    state.complete = true;
    if (state.mode === "dictionary") {
      state.output = "";
      renderCard(JSON.parse(response));
    } else {
      state.accept(id, response);
      element("origin").textContent = "AI 翻译";
      card = null;
      result.innerHTML = `<p class="translation-text">${escape(response)}</p>`;
    }
  } catch (error) {
    if (id === state.request) report(error);
  } finally {
    if (id === state.request) {
      busy = false;
      controls();
    }
  }
}

input.addEventListener("input", () => {
  const id = state.request;
  state.edit(input.value);
  busy = false;
  void invoke("cancel", { id }).catch(report);
  controls();
});
input.addEventListener("keydown", (event) => {
  if (
    event.key === "Enter" &&
    !event.shiftKey &&
    !event.isComposing &&
    event.keyCode !== 229
  ) {
    event.preventDefault();
    void query();
  }
});
document.addEventListener("keydown", (event) => {
  if (event.key === "Escape" && !event.isComposing) {
    if (view !== "query") void showView("query");
    else void invoke("hide").catch(report);
  }
});
for (const id of ["source", "target"] as const)
  element(id).addEventListener("change", () => {
    const previous = state.request;
    state[id] = element<HTMLSelectElement>(id).value;
    const other = id === "source" ? "target" : "source";
    if (state[other] === "auto")
      state[other] =
        (other === "source" ? state.resolvedSource : state.resolvedTarget) ||
        "auto";
    state.edit(input.value);
    busy = false;
    void invoke("cancel", { id: previous }).catch(report);
    controls();
  });
action("close", () => invoke("hide"));
action("submit", () => query());
action("retry", () => query(state.mode));
action("stop", stop);
action("dictionary", () => query("dictionary"));
action("translation", () => query("translation"));
action("copy", async () => {
  await invoke("copy", { text: state.output });
  report("已复制译文");
});
action("auto", () => {
  state.source = state.target = "auto";
  return query();
});
action("swap", () => {
  const run = state.swap();
  input.value = state.input;
  controls();
  if (run) return query("translation");
});
action("pin", async () => {
  pinned = !pinned;
  await invoke("pin", { pinned: pinned || view !== "query" });
  element("pin").setAttribute("aria-pressed", String(pinned));
});
root.querySelectorAll<HTMLButtonElement>(".back").forEach(
  (button) =>
    (button.onclick = () => {
      clearNotice();
      void showView("query").catch(report);
    }),
);

action("favorite", async () => {
  if (!card || state.stale) return;
  await invoke("save_word", {
    word: {
      id: "",
      card,
      source_language: state.resolvedSource,
      target_language: state.resolvedTarget,
      contexts: [element<HTMLTextAreaElement>("context").value.trim()].filter(
        Boolean,
      ),
      saved_at: Date.now(),
    } satisfies SavedWord,
  });
  report("已收藏到生词本");
});

function renderWords() {
  const search = element<HTMLInputElement>("search").value.toLocaleLowerCase();
  const words = savedWords.filter((word) =>
    `${word.card.original} ${word.card.entry.word} ${word.card.entry.translation} ${word.contexts.join(" ")}`
      .toLocaleLowerCase()
      .includes(search),
  );
  element("word-count").textContent = String(savedWords.length);
  element("words").innerHTML = words.length
    ? words
        .map(
          (word, index) =>
            `<article class="saved-word"><button class="open-word" data-index="${index}"><b>${escape(word.card.entry.word)}</b><small>${escape(word.card.original)} · ${escape(word.card.source)}</small><p>${escape(word.card.entry.translation)}</p></button><button class="delete-word" data-delete="${index}" aria-label="删除 ${escape(word.card.original)}">×</button></article>`,
        )
        .join("")
    : '<p class="hint">还没有匹配的生词。</p>';
  element("words")
    .querySelectorAll<HTMLButtonElement>("[data-index]")
    .forEach(
      (button) =>
        (button.onclick = async () => {
          const word = words[Number(button.dataset.index)];
          await stop();
          state.open(word.card.original);
          input.value = state.input;
          state.source = state.resolvedSource = word.source_language;
          state.target = state.resolvedTarget = word.target_language;
          state.mode = "dictionary";
          state.complete = true;
          element<HTMLTextAreaElement>("context").value =
            word.contexts.join("\n");
          localCard = word.card.source === "ECDICT" ? word.card : null;
          renderCard(word.card);
          await showView("query");
        }),
    );
  element("words")
    .querySelectorAll<HTMLButtonElement>("[data-delete]")
    .forEach(
      (button) =>
        (button.onclick = () => {
          void invoke("delete_word", {
            id: words[Number(button.dataset.delete)].id,
          })
            .then(loadWords)
            .catch(report);
        }),
    );
}
async function loadWords() {
  savedWords = await invoke<SavedWord[]>("vocabulary");
  renderWords();
}
action("book", async () => {
  await showView("book");
  await loadWords();
});
element("search").addEventListener("input", renderWords);
for (const id of ["import", "export"])
  action(id, async () => {
    await invoke("transfer_vocabulary", { import: id === "import" });
    await loadWords();
  });

async function openSettings() {
  const data = await invoke<{
    settings: Settings;
    has_key: boolean;
    shortcut_errors: string[];
  }>("settings");
  for (const id of ["endpoint", "model"] as const)
    element<HTMLInputElement>(id).value = data.settings[id];
  data.settings.shortcuts.forEach((shortcut, index) => {
    element<HTMLInputElement>(`shortcut-${index}`).value = shortcut;
  });
  element<HTMLInputElement>("key").value = "";
  element("key-state").textContent = data.has_key
    ? "密钥已存入系统钥匙串。留空保留已有密钥。"
    : "尚未配置密钥。本地词典和生词本可正常使用。";
  await showView("settings");
  if (data.shortcut_errors.length)
    report(`快捷键未注册：${data.shortcut_errors.join("、")}。请修改并保存。`);
}
action("settings", openSettings);
for (let index = 0; index < 3; index++)
  element(`shortcut-${index}`).addEventListener("keydown", (event) => {
    if (event.key === "Tab") return;
    event.preventDefault();
    if (
      ["Shift", "Alt", "Control", "Meta", "Tab", "Escape"].includes(event.key)
    )
      return;
    if (!(event.metaKey || event.altKey || event.ctrlKey)) {
      report("快捷键需包含 ⌘、⌥ 或 ⌃。");
      return;
    }
    const modifiers = [
      event.metaKey && "Super",
      event.ctrlKey && "Control",
      event.altKey && "Alt",
      event.shiftKey && "Shift",
    ].filter(Boolean);
    element<HTMLInputElement>(`shortcut-${index}`).value = [
      ...modifiers,
      event.code,
    ].join("+");
  });
function settingsForm() {
  return {
    settings: {
      endpoint: element<HTMLInputElement>("endpoint").value.trim(),
      model: element<HTMLInputElement>("model").value.trim(),
      shortcuts: [0, 1, 2].map(
        (index) => element<HTMLInputElement>(`shortcut-${index}`).value,
      ) as Settings["shortcuts"],
    },
    key: element<HTMLInputElement>("key").value || null,
  };
}
element("settings-form").addEventListener("submit", (event) => {
  event.preventDefault();
  const button =
    element<HTMLButtonElement>(
      "settings-form",
    ).querySelector<HTMLButtonElement>('[type="submit"]')!;
  button.disabled = true;
  void invoke("save_settings", settingsForm())
    .then(() => {
      element<HTMLInputElement>("key").value = "";
      report("设置已保存");
    })
    .catch(report)
    .finally(() => {
      button.disabled = false;
    });
});
action("test", async () => {
  element<HTMLButtonElement>("test").disabled = true;
  report("正在测试连接…");
  try {
    await invoke("test_connection", settingsForm());
    report("连接成功");
  } finally {
    element<HTMLButtonElement>("test").disabled = false;
  }
});

await listen<{ kind: string; text: string; error: string }>(
  "entry",
  async ({ payload }) => {
    clearNotice();
    if (payload.kind === "settings") {
      await openSettings();
      return;
    }
    await stop();
    state.open(payload.text);
    input.value = payload.text;
    element<HTMLTextAreaElement>("context").value = "";
    card = localCard = null;
    result.replaceChildren();
    controls();
    await showView("query");
    if (payload.error) report(payload.error);
    else if (payload.text) await query();
  },
);
await getCurrentWindow().onFocusChanged(({ payload }) => {
  if (payload && view === "query") input.focus();
});
controls();
input.focus();
const startup = await invoke<{ shortcut_errors: string[] }>("shortcut_status");
if (startup.shortcut_errors.length)
  report(
    `快捷键注册失败：${startup.shortcut_errors.join("、")}。请在设置中修改。`,
  );
