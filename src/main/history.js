'use strict'

const fs = require('fs')
const path = require('path')
const { app } = require('electron')
const { MAX_HISTORY, normalizeItem, dedupe } = require('./history-util')

let cache = null

function file() {
  return path.join(app.getPath('userData'), 'history.json')
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
  cache = dedupe(load(), normalized, MAX_HISTORY)
  persist()
  return cache
}

function clear() {
  cache = []
  persist()
  return cache
}

module.exports = { list, add, clear }
