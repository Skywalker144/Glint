'use strict'

const fs = require('fs')
const path = require('path')
const { app } = require('electron')
const {
  DEFAULT_SYSTEM_PROMPT,
  DEFAULT_DICTIONARY_PROMPT,
  LEGACY_SYSTEM_PROMPTS,
  LEGACY_DICTIONARY_PROMPTS,
} = require('./engines/prompt')

// 设置持久化在 userData/settings.json。

const DEFAULTS = {
  engine: 'google', // 选中的服务商 id（见 engines/providers.js）
  launchAtLogin: false, // 开机自启
  pinned: false, // 钉住主窗口：false 时失焦自动隐藏，true 时常驻
  windowWidth: 420, // 翻译窗宽度：可横向拖拽，记住上次
  proxy: { enabled: false, url: '' }, // 网络代理：如 Clash 的 127.0.0.1:7890
  primaryLanguage: 'zh-CN', // 主语言：非主语言输入会翻到这里
  secondaryLanguage: 'en', // 副语言：主语言输入会翻到这里
  systemPrompt: DEFAULT_SYSTEM_PROMPT, // AI 翻译服务商使用的系统提示词模板
  dictionaryMode: true, // 输入单个词时用 AI 词典（仅 AI 引擎）
  dictionaryPrompt: DEFAULT_DICTIONARY_PROMPT, // 词典模式的系统提示词模板
  hotkeys: {
    input: 'Alt+Q', // 输入翻译
    screenshot: 'Alt+W', // 截图翻译
    selection: 'Alt+E', // 划词翻译
    clipboard: 'Alt+R', // 翻译剪贴板
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
  if (raw && LEGACY_SYSTEM_PROMPTS.includes(raw.systemPrompt)) {
    raw.systemPrompt = DEFAULT_SYSTEM_PROMPT
  }
  if (raw && LEGACY_DICTIONARY_PROMPTS.includes(raw.dictionaryPrompt)) {
    raw.dictionaryPrompt = DEFAULT_DICTIONARY_PROMPT
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
