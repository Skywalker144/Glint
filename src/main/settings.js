'use strict'

const fs = require('fs')
const path = require('path')
const { app } = require('electron')

// 设置持久化在 userData/settings.json。

const DEFAULTS = {
  engine: 'google', // 选中的服务商 id（见 engines/providers.js）
  hotkeys: {
    input: 'Alt+Q', // 输入翻译
    screenshot: 'Alt+W', // 截图翻译
    selection: 'Alt+E', // 划词翻译
  },
  // 每个服务商各存各的 Key/模型，切换不丢配置。
  providers: {
    openai: { apiKey: '', model: 'gpt-4o-mini' },
    deepseek: { apiKey: '', model: 'deepseek-chat' },
    anthropic: { apiKey: '', model: 'claude-3-5-haiku-latest' },
    gemini: { apiKey: '', model: 'gemini-2.0-flash' },
    openrouter: { apiKey: '', model: 'openai/gpt-4o-mini' },
    custom: { apiKey: '', model: '', baseURL: '' },
  },
}

// 旧版本配置迁移：顶层 openrouter:{apiKey,model} -> providers.openrouter
function migrate(raw) {
  if (raw && raw.openrouter && !(raw.providers && raw.providers.openrouter)) {
    raw.providers = raw.providers || {}
    raw.providers.openrouter = raw.openrouter
    delete raw.openrouter
  }
  return raw
}

let cache = null

function file() {
  return path.join(app.getPath('userData'), 'settings.json')
}

function isObject(v) {
  return v && typeof v === 'object' && !Array.isArray(v)
}

function deepMerge(base, override) {
  const out = { ...base }
  for (const key of Object.keys(override || {})) {
    if (isObject(out[key]) && isObject(override[key])) {
      out[key] = deepMerge(out[key], override[key])
    } else if (override[key] !== undefined) {
      out[key] = override[key]
    }
  }
  return out
}

// 改名（translator -> glint）后 userData 目录会变，把旧 settings.json 搬过来，避免丢配置。
function migrateOldUserData() {
  try {
    const target = file()
    if (fs.existsSync(target)) return
    const legacy = path.join(app.getPath('appData'), 'translator', 'settings.json')
    if (fs.existsSync(legacy)) {
      fs.mkdirSync(path.dirname(target), { recursive: true })
      fs.copyFileSync(legacy, target)
    }
  } catch {}
}

function load() {
  if (cache) return cache
  migrateOldUserData()
  try {
    cache = deepMerge(DEFAULTS, migrate(JSON.parse(fs.readFileSync(file(), 'utf8'))))
  } catch {
    cache = deepMerge(DEFAULTS, {})
  }
  return cache
}

function get() {
  return load()
}

function save(partial) {
  cache = deepMerge(load(), partial)
  try {
    fs.writeFileSync(file(), JSON.stringify(cache, null, 2), 'utf8')
  } catch (e) {
    console.warn('保存设置失败：', e.message)
  }
  return cache
}

module.exports = { get, save, load, DEFAULTS }
