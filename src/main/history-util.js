'use strict'

// 翻译历史的纯逻辑（归一化 + 去重）。刻意不依赖 electron，方便单测。

const MAX_HISTORY = 100

function normalizeItem(item) {
  if (!item || !item.original || !item.translated) return null
  return {
    id: item.id || String(Date.now()),
    createdAt: item.createdAt || new Date().toISOString(),
    original: String(item.original),
    translated: String(item.translated),
    source: item.source || 'auto',
    target: item.target || '',
    engine: item.engine || '',
  }
}

// 把 item 插到队首，去掉与之原文+译文都相同的旧条目，并截断到上限。
function dedupe(list, item, max = MAX_HISTORY) {
  const same = (h) => h.original === item.original && h.translated === item.translated
  return [item, ...(list || []).filter((h) => !same(h))].slice(0, max)
}

module.exports = { MAX_HISTORY, normalizeItem, dedupe }
