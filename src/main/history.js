'use strict'

const fs = require('fs')
const path = require('path')
const { app } = require('electron')

const MAX_HISTORY = 100
let cache = null

function file() {
  return path.join(app.getPath('userData'), 'history.json')
}

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

function load() {
  if (cache) return cache
  try {
    const raw = JSON.parse(fs.readFileSync(file(), 'utf8'))
    cache = Array.isArray(raw) ? raw.map(normalizeItem).filter(Boolean) : []
  } catch {
    cache = []
  }
  return cache
}

function persist() {
  try {
    fs.writeFileSync(file(), JSON.stringify(load(), null, 2), 'utf8')
  } catch (e) {
    console.warn('保存翻译历史失败：', e.message)
  }
}

function list() {
  return load()
}

function add(item) {
  const normalized = normalizeItem({ ...item, id: String(Date.now()), createdAt: new Date().toISOString() })
  if (!normalized) return list()
  const same = (h) => h.original === normalized.original && h.translated === normalized.translated
  cache = [normalized, ...load().filter((h) => !same(h))].slice(0, MAX_HISTORY)
  persist()
  return cache
}

function clear() {
  cache = []
  persist()
  return cache
}

module.exports = { list, add, clear }
