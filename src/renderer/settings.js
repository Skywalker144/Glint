'use strict'

const $ = (s) => document.querySelector(s)
const $$ = (s) => Array.from(document.querySelectorAll(s))

let metaList = []
let metaById = {}
let languageList = []
let languageByCode = {}
let defaultSettings = { systemPrompt: '', dictionaryPrompt: '' }
let historyItems = []
let state = {
  engine: 'google',
  launchAtLogin: false,
  primaryLanguage: 'zh-CN',
  secondaryLanguage: 'en',
  systemPrompt: '',
  dictionaryMode: true,
  dictionaryPrompt: '',
  pinned: false,
  proxy: { enabled: false, url: '' },
  hotkeys: { input: '', screenshot: '', selection: '', clipboard: '' },
  providers: {},
}

// 窗口高度随当前栏内容自适应：卡片高度一变就报给主进程。
const appEl = $('.app')
let lastReportedHeight = 0
new ResizeObserver(() => {
  const h = Math.ceil(appEl.getBoundingClientRect().height)
  if (Math.abs(h - lastReportedHeight) > 1) {
    lastReportedHeight = h
    window.api.resizeSettings(h)
  }
}).observe(appEl)

/* ---------------- 通用工具 ---------------- */

function clone(v) {
  return JSON.parse(JSON.stringify(v || {}))
}

function normalizeSettings(s) {
  const hotkeys = s && s.hotkeys ? s.hotkeys : {}
  return {
    engine: (s && s.engine) || 'google',
    launchAtLogin: !!(s && s.launchAtLogin),
    primaryLanguage: (s && s.primaryLanguage) || 'zh-CN',
    secondaryLanguage: (s && s.secondaryLanguage) || 'en',
    systemPrompt: (s && s.systemPrompt) || defaultSettings.systemPrompt || '',
    dictionaryMode: s && s.dictionaryMode !== undefined ? !!s.dictionaryMode : true,
    dictionaryPrompt: (s && s.dictionaryPrompt) || defaultSettings.dictionaryPrompt || '',
    pinned: !!(s && s.pinned),
    proxy: {
      enabled: !!(s && s.proxy && s.proxy.enabled),
      url: (s && s.proxy && s.proxy.url) || '',
    },
    hotkeys: {
      input: hotkeys.input || '',
      screenshot: hotkeys.screenshot || '',
      selection: hotkeys.selection || '',
      clipboard: hotkeys.clipboard || '',
    },
    providers: clone((s && s.providers) || {}),
  }
}

let saveTimer = null
let savedClearTimer = null

// 自动保存：任一设置项变化都即时落盘，没有「保存」按钮。统一走 400ms 防抖——文本输入不会每个
// 按键都写盘 / 反复重设代理，开关 / 下拉 / 快捷键这类离散改动也合并成一次写入。
function scheduleSave() {
  clearTimeout(saveTimer)
  saveTimer = setTimeout(saveNow, 400)
}
function saveNow() {
  clearTimeout(saveTimer)
  saveTimer = null
  window.api
    .saveSettings(state)
    .then((r) => {
      if (r && r.hotkeyErrors && r.hotkeyErrors.length) {
        const names = { input: '输入翻译', screenshot: '截图翻译', selection: '划词翻译', clipboard: '剪贴板翻译' }
        flashSaveStatus('✗ 快捷键无法注册（可能被占用）：' + r.hotkeyErrors.map((k) => names[k]).join('、'), 'err')
      } else {
        flashSaveStatus('✓ 已自动保存', 'ok')
      }
    })
    .catch((e) => flashSaveStatus('✗ 保存失败：' + e.message, 'err'))
}
// 标题栏的自动保存提示：成功短暂显示后淡出，错误保留以便看到。
function flashSaveStatus(text, cls) {
  setStatus('#save-status', text, cls)
  clearTimeout(savedClearTimer)
  if (cls === 'ok') savedClearTimer = setTimeout(() => setStatus('#save-status', ''), 1600)
}

// 设置项变化的统一入口：更新派生 UI（徽章、提示词统计）并触发自动保存。
function markDirty() {
  renderProviderState()
  renderPromptMeta()
  scheduleSave()
}

function languageLabel(code) {
  if (code === 'auto') return '自动'
  return (languageByCode[code] && languageByCode[code].label) || code || '自动'
}

function oneLine(text) {
  return (text || '').replace(/\s+/g, ' ').trim()
}

function formatTime(iso) {
  if (!iso) return ''
  const d = new Date(iso)
  if (Number.isNaN(d.getTime())) return ''
  return d.toLocaleString('zh-CN', {
    month: '2-digit',
    day: '2-digit',
    hour: '2-digit',
    minute: '2-digit',
  })
}

function setStatus(sel, text, cls) {
  const el = $(sel)
  el.textContent = text || ''
  el.className = 's-status' + (cls ? ' ' + cls : '')
}

function setBadge(sel, text, cls) {
  const el = $(sel)
  el.textContent = text || ''
  el.className = 's-badge' + (cls ? ' ' + cls : '')
}

function requestClose() {
  if (saveTimer) saveNow() // 关窗前把待保存的防抖立即落盘
  window.api.closeSettings()
}

/* ---------------- 标签切换 ---------------- */

function selectTab(name) {
  $$('.s-tab').forEach((t) => t.classList.toggle('active', t.dataset.tab === name))
  $$('.s-panel').forEach((p) => {
    p.hidden = p.dataset.panel !== name
  })
  if (name === 'permissions') refreshPermissions()
  if (name === 'history') loadHistory()
  if (name === 'about') checkUpdate()
}

$$('.s-tab').forEach((tab) => {
  tab.addEventListener('click', () => selectTab(tab.dataset.tab))
})

/* ---------------- 通用 ---------------- */

$('#launch-at-login').addEventListener('change', (e) => {
  state.launchAtLogin = e.target.checked
  markDirty()
})

$('#pin-window').addEventListener('change', (e) => {
  state.pinned = e.target.checked
  markDirty()
})

$('#proxy-enabled').addEventListener('change', (e) => {
  state.proxy.enabled = e.target.checked
  markDirty()
})
$('#proxy-url').addEventListener('input', (e) => {
  state.proxy.url = e.target.value.trim()
  markDirty()
})
$('#proxy-test').addEventListener('click', async () => {
  const btn = $('#proxy-test')
  const old = btn.textContent
  btn.textContent = '测试中…'
  btn.disabled = true
  const r = await window.api.testProxy({ url: state.proxy.url })
  btn.textContent = old
  btn.disabled = false
  if (r.ok) setStatus('#proxy-status', '✓ 连通（' + r.ms + 'ms）', 'ok')
  else setStatus('#proxy-status', '✗ ' + r.error, 'err')
})

/* ---------------- 快捷键录制 ---------------- */

const SYM = {
  Command: '⌘', Control: '⌃', Alt: '⌥', Shift: '⇧', CommandOrControl: '⌘',
  Return: '⏎', Space: '␣', Up: '↑', Down: '↓', Left: '←', Right: '→',
}

function displayAccel(accel) {
  if (!accel) return ''
  return accel.split('+').map((p) => SYM[p] || p).join(' ')
}

function keyFromCode(code) {
  let m
  if ((m = /^Key([A-Z])$/.exec(code))) return m[1]
  if ((m = /^Digit(\d)$/.exec(code))) return m[1]
  if (/^F([1-9]|1[0-9]|2[0-4])$/.test(code)) return code
  const map = {
    Space: 'Space', Enter: 'Return', Tab: 'Tab', Backspace: 'Backspace', Delete: 'Delete',
    ArrowUp: 'Up', ArrowDown: 'Down', ArrowLeft: 'Left', ArrowRight: 'Right',
    Home: 'Home', End: 'End', PageUp: 'PageUp', PageDown: 'PageDown',
    Minus: '-', Equal: '=', BracketLeft: '[', BracketRight: ']', Backslash: '\\',
    Semicolon: ';', Quote: "'", Comma: ',', Period: '.', Slash: '/', Backquote: '`',
  }
  return map[code] || null
}

function buildAccel(e) {
  const mods = []
  if (e.metaKey) mods.push('Command')
  if (e.ctrlKey) mods.push('Control')
  if (e.altKey) mods.push('Alt')
  if (e.shiftKey) mods.push('Shift')
  const key = keyFromCode(e.code)
  if (!key) return null
  return [...mods, key].join('+')
}

function renderHotkey(el) {
  el.value = displayAccel(state.hotkeys[el.dataset.key])
}

$$('.recorder').forEach((el) => {
  el.addEventListener('focus', () => {
    el.classList.add('recording')
    el.value = '按下组合键…'
  })
  el.addEventListener('blur', () => {
    el.classList.remove('recording')
    renderHotkey(el)
  })
  el.addEventListener('keydown', (e) => {
    e.preventDefault()
    e.stopPropagation()
    if (['Escape', 'Delete', 'Backspace'].includes(e.code)) {
      state.hotkeys[el.dataset.key] = ''
      el.blur()
      markDirty()
      return
    }
    const accel = buildAccel(e)
    if (!accel) return
    state.hotkeys[el.dataset.key] = accel
    el.blur()
    markDirty()
  })
})

/* ---------------- 翻译 / AI ---------------- */

function cfgFor(id) {
  if (!state.providers[id]) {
    const meta = metaById[id] || {}
    state.providers[id] = { apiKey: '', model: meta.defaultModel || '', baseURL: meta.needsBaseURL ? '' : undefined }
  }
  return state.providers[id]
}

function providerStatus(meta, cfg) {
  if (!meta) return { text: '未知', cls: 'err' }
  if (meta.kind === 'free') return { text: '无需配置', cls: 'ok' }
  if (meta.needsBaseURL && !(cfg && cfg.baseURL)) return { text: '缺少 Base URL', cls: 'err' }
  if (meta.needsKey && !(cfg && cfg.apiKey)) return { text: '缺少 Key', cls: 'err' }
  if (!(cfg && cfg.model)) return { text: '未选模型', cls: 'warn' }
  return { text: '已配置', cls: 'ok' }
}

function setModels(ids) {
  const dl = $('#ai-models')
  dl.innerHTML = ''
  for (const id of ids || []) {
    const o = document.createElement('option')
    o.value = id
    dl.appendChild(o)
  }
}

function renderProviderOptions() {
  const sel = $('#provider')
  sel.innerHTML = ''
  for (const m of metaList) {
    const o = document.createElement('option')
    o.value = m.id
    o.textContent = m.label
    sel.appendChild(o)
  }
}

function renderLanguageOptions() {
  for (const sel of [$('#primary-language'), $('#secondary-language')]) {
    sel.innerHTML = ''
    for (const l of languageList) {
      const o = document.createElement('option')
      o.value = l.code
      o.textContent = l.label
      sel.appendChild(o)
    }
  }
}

function renderLanguageRules() {
  $('#primary-language').value = state.primaryLanguage
  $('#secondary-language').value = state.secondaryLanguage
  $('#primary-rule-label').textContent = languageLabel(state.primaryLanguage) + '输入'
  $('#primary-rule-target').textContent = '翻译成' + languageLabel(state.secondaryLanguage)
  $('#fallback-rule-label').textContent = '非' + languageLabel(state.primaryLanguage) + '输入'
  $('#fallback-rule-target').textContent = '翻译成' + languageLabel(state.primaryLanguage)
}

function renderProviderState() {
  const meta = metaById[state.engine]
  if (!meta) return
  const cfg = cfgFor(state.engine)
  const status = providerStatus(meta, cfg)

  const isFree = meta.kind === 'free'
  $('#provider').value = state.engine
  $('#provider-desc').textContent =
    meta.desc || (isFree ? '开箱即用，适合轻量翻译。' : '使用模型 API 翻译，质量和风格由模型决定。')
  setBadge('#provider-badge', status.text, status.cls)

  // 翻译页：免费引擎给一句说明；AI 引擎就地展开 Key / 模型 / 测试（不再跳到别的页）。
  $('#provider-free-note').hidden = !isFree
  $('#provider-config').hidden = isFree
  // 提示词页：免费引擎不使用提示词 / 词典，藏掉配置只留说明。
  $('#ai-free-note').hidden = !isFree
  $('#ai-prompt-config').hidden = isFree

  if (isFree) return

  $('#baseurl-field').hidden = !meta.needsBaseURL
  $('#ai-baseurl').value = cfg.baseURL || ''

  const link = $('#key-link')
  if (meta.keyURL) {
    link.hidden = false
    link.dataset.url = meta.keyURL
  } else {
    link.hidden = true
    link.dataset.url = ''
  }

  $('#ai-key').value = cfg.apiKey || ''
  $('#ai-key').placeholder = meta.keyHint || 'sk-...'
  $('#ai-model').value = cfg.model || ''
  $('#ai-model').placeholder = meta.defaultModel || '模型名'
  setModels(meta.models)
}

function renderPromptMeta() {
  const prompt = ($('#ai-system-prompt').value || state.systemPrompt || '').trim()
  const has = (name) => new RegExp('\\{\\{?\\s*' + name + '\\s*\\}?\\}|\\$\\{\\s*' + name + '\\s*\\}').test(prompt)
  const toks = []
  if (has('primary')) toks.push('{{primary}}')
  if (has('secondary')) toks.push('{{secondary}}')
  if (has('target')) toks.push('{{target}}')
  const parts = [prompt.length + ' 字符']
  if (toks.length) parts.push('占位符 ' + toks.join(' '))
  else parts.push(languageLabel(state.primaryLanguage) + ' ⇄ ' + languageLabel(state.secondaryLanguage))
  $('#ai-prompt-meta').textContent = parts.join(' · ')
}

$('#provider').addEventListener('change', (e) => {
  state.engine = e.target.value
  cfgFor(state.engine)
  markDirty() // markDirty 内会 renderProviderState，按新服务商就地展开 Key / 模型
})

$('#primary-language').addEventListener('change', (e) => {
  state.primaryLanguage = e.target.value
  if (state.primaryLanguage === state.secondaryLanguage) {
    state.secondaryLanguage = state.primaryLanguage === 'zh-CN' ? 'en' : 'zh-CN'
  }
  renderLanguageRules()
  markDirty()
})

$('#secondary-language').addEventListener('change', (e) => {
  state.secondaryLanguage = e.target.value
  if (state.primaryLanguage === state.secondaryLanguage) {
    state.primaryLanguage = state.secondaryLanguage === 'zh-CN' ? 'en' : 'zh-CN'
  }
  renderLanguageRules()
  markDirty()
})

$('#ai-key').addEventListener('input', (e) => {
  cfgFor(state.engine).apiKey = e.target.value.trim()
  markDirty()
})
$('#ai-model').addEventListener('input', (e) => {
  cfgFor(state.engine).model = e.target.value.trim()
  markDirty()
})
$('#ai-baseurl').addEventListener('input', (e) => {
  cfgFor(state.engine).baseURL = e.target.value.trim()
  markDirty()
})

$('#ai-system-prompt').addEventListener('input', (e) => {
  state.systemPrompt = e.target.value
  markDirty()
})

$('#ai-prompt-reset').addEventListener('click', () => {
  state.systemPrompt = defaultSettings.systemPrompt || ''
  $('#ai-system-prompt').value = state.systemPrompt
  markDirty()
})

$('#dictionary-mode').addEventListener('change', (e) => {
  state.dictionaryMode = e.target.checked
  markDirty()
})
$('#ai-dictionary-prompt').addEventListener('input', (e) => {
  state.dictionaryPrompt = e.target.value
  markDirty()
})
$('#ai-dict-reset').addEventListener('click', () => {
  state.dictionaryPrompt = defaultSettings.dictionaryPrompt || ''
  $('#ai-dictionary-prompt').value = state.dictionaryPrompt
  markDirty()
})

$('#key-link').addEventListener('click', () => {
  const url = $('#key-link').dataset.url
  if (url) window.api.openExternal(url)
})

$('#ai-load').addEventListener('click', async () => {
  const cfg = cfgFor(state.engine)
  const btn = $('#ai-load')
  const old = btn.textContent
  btn.textContent = '加载中…'
  btn.disabled = true
  const r = await window.api.fetchModels({ engine: state.engine, apiKey: cfg.apiKey, baseURL: cfg.baseURL })
  btn.textContent = old
  btn.disabled = false
  if (!r.ok) {
    setStatus('#ai-status', '✗ ' + r.error, 'err')
    return
  }
  setModels(r.models)
  setStatus('#ai-status', '✓ 已加载 ' + r.models.length + ' 个模型，点模型框可搜索选择', 'ok')
})

$('#ai-test').addEventListener('click', async () => {
  const cfg = cfgFor(state.engine)
  const meta = metaById[state.engine]
  if (meta.needsBaseURL && !cfg.baseURL) {
    setStatus('#ai-status', '✗ 请先填 Base URL', 'err')
    return
  }
  if (!cfg.apiKey || !cfg.model) {
    setStatus('#ai-status', '✗ 请先填 API Key 和模型', 'err')
    return
  }
  setStatus('#ai-status', '测试中…', '')
  const r = await window.api.testEngine({
    engine: state.engine,
    apiKey: cfg.apiKey,
    model: cfg.model,
    baseURL: cfg.baseURL,
    systemPrompt: state.systemPrompt,
  })
  if (r.ok) setStatus('#ai-status', '✓ 成功：' + r.text, 'ok')
  else setStatus('#ai-status', '✗ ' + r.error, 'err')
})

/* ---------------- 权限 ---------------- */

function permissionTone(ok) {
  return ok ? 'ok' : 'err'
}

function renderPermissions(p) {
  if (!p || p.platform !== 'darwin') {
    setBadge('#perm-accessibility', '无需配置', 'ok')
    setBadge('#perm-screen', '无需配置', 'ok')
    setBadge('#perm-ocr', 'Tesseract', 'ok')
    $('#perm-ocr-desc').textContent = '当前平台使用 Tesseract OCR。'
    $('#open-accessibility').disabled = true
    $('#open-screen').disabled = true
    return
  }

  const screenGranted = p.screen === 'granted'
  setBadge('#perm-accessibility', p.accessibility ? '已授权' : '未授权', permissionTone(p.accessibility))
  setBadge('#perm-screen', screenGranted ? '已授权' : '未授权', permissionTone(screenGranted))
  setBadge('#perm-ocr', 'Vision', 'ok')
  $('#perm-ocr-desc').textContent = 'macOS 使用系统 Vision OCR。'
  $('#open-accessibility').disabled = false
  $('#open-screen').disabled = false
}

async function refreshPermissions() {
  if (!window.api.getPermissions) return
  try {
    renderPermissions(await window.api.getPermissions())
  } catch {
    setBadge('#perm-accessibility', '未知', 'warn')
    setBadge('#perm-screen', '未知', 'warn')
    setBadge('#perm-ocr', '未知', 'warn')
  }
}

$('#open-accessibility').addEventListener('click', () => window.api.openPermissionSettings('accessibility'))
$('#open-screen').addEventListener('click', () => window.api.openPermissionSettings('screen'))
$('#refresh-permissions').addEventListener('click', refreshPermissions)

/* ---------------- 历史 ---------------- */

function filteredHistory() {
  const q = ($('#history-search').value || '').trim().toLowerCase()
  if (!q) return historyItems
  return historyItems.filter((item) => {
    return (
      (item.original || '').toLowerCase().includes(q) ||
      (item.translated || '').toLowerCase().includes(q)
    )
  })
}

function renderHistory() {
  const list = $('#history-list')
  const items = filteredHistory()
  list.innerHTML = ''
  $('#history-summary').textContent = historyItems.length
    ? '共 ' + historyItems.length + ' 条记录，当前显示 ' + items.length + ' 条'
    : '还没有翻译历史'

  if (!items.length) {
    const empty = document.createElement('div')
    empty.className = 'history-empty'
    empty.textContent = historyItems.length ? '没有匹配的记录' : '翻译成功后会自动保存到这里'
    list.appendChild(empty)
    return
  }

  for (const item of items) {
    const entry = document.createElement('div')
    entry.className = 'history-entry'

    const main = document.createElement('div')
    main.className = 'history-main'
    const original = document.createElement('div')
    original.className = 'history-original'
    original.textContent = oneLine(item.original)
    const translated = document.createElement('div')
    translated.className = 'history-translated'
    translated.textContent = oneLine(item.translated)
    main.append(original, translated)

    const meta = document.createElement('div')
    meta.className = 'history-meta'
    const direction = document.createElement('span')
    direction.textContent = languageLabel(item.source) + ' → ' + languageLabel(item.target)
    const time = document.createElement('span')
    time.textContent = formatTime(item.createdAt)
    meta.append(direction, time)

    const actions = document.createElement('div')
    actions.className = 'history-actions'
    const copyOriginal = document.createElement('button')
    copyOriginal.className = 'ghost'
    copyOriginal.type = 'button'
    copyOriginal.textContent = '复制原文'
    copyOriginal.addEventListener('click', () => {
      window.api.copyText(item.original || '')
      setStatus('#save-status', '✓ 已复制原文', 'ok')
    })
    const copyTranslated = document.createElement('button')
    copyTranslated.className = 'ghost'
    copyTranslated.type = 'button'
    copyTranslated.textContent = '复制译文'
    copyTranslated.addEventListener('click', () => {
      window.api.copyText(item.translated || '')
      setStatus('#save-status', '✓ 已复制译文', 'ok')
    })
    const retry = document.createElement('button')
    retry.className = 'ghost'
    retry.type = 'button'
    retry.textContent = '重新翻译'
    retry.addEventListener('click', async () => {
      setStatus('#save-status', '重新翻译中…')
      try {
        await window.api.translate(item.original || '')
        await loadHistory()
        setStatus('#save-status', '✓ 已重新翻译', 'ok')
      } catch (e) {
        setStatus('#save-status', '✗ ' + e.message, 'err')
      }
    })
    actions.append(copyOriginal, copyTranslated, retry)

    entry.append(main, meta, actions)
    list.appendChild(entry)
  }
}

async function loadHistory() {
  if (!window.api.getHistory) return
  historyItems = await window.api.getHistory()
  renderHistory()
}

$('#history-search').addEventListener('input', renderHistory)
$('#history-refresh').addEventListener('click', loadHistory)
$('#history-clear').addEventListener('click', async () => {
  if (!historyItems.length) return
  if (!window.confirm('确定要清空所有翻译历史吗？')) return
  historyItems = await window.api.clearHistory()
  renderHistory()
  setStatus('#save-status', '✓ 已清空历史', 'ok')
})

/* ---------------- 关闭、关于 ---------------- */

$('#close').addEventListener('click', requestClose)
document.addEventListener('keydown', (e) => {
  if (e.key === 'Escape') requestClose()
})

$('#about-repo').addEventListener('click', () => {
  const url = $('#about-repo').dataset.url
  if (url) window.api.openExternal(url)
})

$('#update-download').addEventListener('click', () => {
  const url = $('#update-download').dataset.url
  if (url) window.api.openExternal(url)
})

function renderUpdateState(s) {
  if (!s || !s.ok) {
    setStatus('#update-status', s && s.error ? '✗ 检查失败：' + s.error : '', s && s.error ? 'err' : '')
    return
  }
  const action = $('#update-action')
  const dl = $('#update-download')
  dl.dataset.url = s.url || ''
  if (!s.hasUpdate) {
    setStatus('#update-status', '✓ 已是最新版 v' + s.current, 'ok')
    action.hidden = true
    dl.hidden = true
    return
  }
  dl.hidden = false
  if (s.error) {
    setStatus('#update-status', '✗ 下载失败：' + s.error, 'err')
    action.hidden = true
  } else if (s.ready) {
    setStatus('#update-status', '新版 v' + s.latest + ' 已下载', 'ok')
    action.hidden = false
    action.textContent = '重启以更新'
    action.dataset.act = 'apply'
  } else if (s.downloading) {
    setStatus('#update-status', '发现新版 v' + s.latest + '，下载中 ' + Math.round((s.progress || 0) * 100) + '%…', '')
    action.hidden = true
  } else if (s.canAutoUpdate) {
    setStatus('#update-status', '发现新版 v' + s.latest + '，准备下载…', 'ok')
    action.hidden = true
  } else {
    setStatus('#update-status', '发现新版 v' + s.latest + '（当前 v' + s.current + '）', 'ok')
    action.hidden = true
  }
}

async function checkUpdate() {
  setStatus('#update-status', '检查中…', '')
  $('#update-action').hidden = true
  $('#update-download').hidden = true
  renderUpdateState(await window.api.checkUpdate())
}
$('#check-update').addEventListener('click', checkUpdate)
$('#update-action').addEventListener('click', () => {
  if ($('#update-action').dataset.act === 'apply') window.api.applyUpdate()
})
window.api.onUpdateState((s) => renderUpdateState(s))

window.api.getAppInfo().then((info) => {
  $('#about-version').textContent = 'v' + info.version
  $('#about-repo').dataset.url = info.repo
})

async function loadChangelog() {
  if (!window.api.getChangelog) return
  const [log, info] = await Promise.all([window.api.getChangelog(), window.api.getAppInfo()])
  const cur = info && info.version
  const el = $('#changelog')
  el.innerHTML = ''
  for (const e of log || []) {
    const entry = document.createElement('div')
    entry.className = 'changelog-entry'
    const head = document.createElement('div')
    head.className = 'changelog-head'
    const ver = document.createElement('span')
    ver.className = 'changelog-ver'
    ver.textContent = 'v' + e.version
    head.appendChild(ver)
    if (e.version === cur) {
      const badge = document.createElement('span')
      badge.className = 'changelog-cur'
      badge.textContent = '当前'
      head.appendChild(badge)
    }
    if (e.date) {
      const date = document.createElement('span')
      date.className = 'changelog-date'
      date.textContent = e.date
      head.appendChild(date)
    }
    const ul = document.createElement('ul')
    ul.className = 'changelog-list'
    for (const it of e.items || []) {
      const li = document.createElement('li')
      li.textContent = it
      ul.appendChild(li)
    }
    entry.append(head, ul)
    el.appendChild(entry)
  }
}

/* ---------------- 初始化 ---------------- */

function renderAll() {
  $$('.recorder').forEach(renderHotkey)
  $('#launch-at-login').checked = state.launchAtLogin
  $('#pin-window').checked = state.pinned
  $('#proxy-enabled').checked = state.proxy.enabled
  $('#proxy-url').value = state.proxy.url
  $('#ai-system-prompt').value = state.systemPrompt
  $('#dictionary-mode').checked = state.dictionaryMode
  $('#ai-dictionary-prompt').value = state.dictionaryPrompt
  renderLanguageRules()
  renderProviderState()
  renderPromptMeta()
}

function populate(s) {
  state = normalizeSettings(s)
  renderAll()
  setStatus('#save-status', '')
  setStatus('#ai-status', '')
}

window.api.onSettingsData((s) => populate(s))

;(async function init() {
  metaList = await window.api.getProviders()
  languageList = await window.api.getLanguages()
  defaultSettings = await window.api.getSettingDefaults()
  metaById = Object.fromEntries(metaList.map((m) => [m.id, m]))
  languageByCode = Object.fromEntries(languageList.map((l) => [l.code, l]))
  renderProviderOptions()
  renderLanguageOptions()
  populate(await window.api.getSettings())
  refreshPermissions()
  loadChangelog()
})()
