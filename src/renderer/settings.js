'use strict'

const $ = (s) => document.querySelector(s)

let metaList = [] // 服务商元数据（来自主进程）
let metaById = {}
let state = {
  engine: 'google',
  hotkeys: { input: '', screenshot: '', selection: '' },
  providers: {},
}

/* ---------------- 标签切换 ---------------- */

document.querySelectorAll('.s-tab').forEach((tab) => {
  tab.addEventListener('click', () => {
    document.querySelectorAll('.s-tab').forEach((t) => t.classList.toggle('active', t === tab))
    const name = tab.dataset.tab
    document.querySelectorAll('.s-panel').forEach((p) => {
      p.hidden = p.dataset.panel !== name
    })
  })
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

document.querySelectorAll('.recorder').forEach((el) => {
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
      return
    }
    const accel = buildAccel(e)
    if (!accel) return
    state.hotkeys[el.dataset.key] = accel
    el.blur()
  })
})

/* ---------------- 翻译引擎 ---------------- */

function cfgFor(id) {
  if (!state.providers[id]) {
    const meta = metaById[id] || {}
    state.providers[id] = { apiKey: '', model: meta.defaultModel || '', baseURL: meta.needsBaseURL ? '' : undefined }
  }
  return state.providers[id]
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

function renderEngine() {
  const meta = metaById[state.engine]
  if (!meta) return
  $('#provider').value = state.engine
  $('#provider-desc').textContent = meta.desc || ''

  if (meta.kind === 'free') {
    $('#ai-config').hidden = true
    return
  }
  $('#ai-config').hidden = false
  const cfg = cfgFor(state.engine)

  // Base URL（仅自定义）
  $('#baseurl-field').hidden = !meta.needsBaseURL
  $('#ai-baseurl').value = cfg.baseURL || ''

  // 获取 Key 链接
  const link = $('#key-link')
  if (meta.keyURL) {
    link.hidden = false
    link.dataset.url = meta.keyURL
  } else {
    link.hidden = true
  }

  $('#ai-key').value = cfg.apiKey || ''
  $('#ai-model').value = cfg.model || ''
  $('#ai-model').placeholder = meta.defaultModel || '模型名'
  setModels(meta.models)
  setStatus('#ai-status', '')
}

$('#provider').addEventListener('change', (e) => {
  state.engine = e.target.value
  cfgFor(state.engine)
  renderEngine()
})

$('#ai-key').addEventListener('input', (e) => {
  cfgFor(state.engine).apiKey = e.target.value.trim()
})
$('#ai-model').addEventListener('input', (e) => {
  cfgFor(state.engine).model = e.target.value.trim()
})
$('#ai-baseurl').addEventListener('input', (e) => {
  cfgFor(state.engine).baseURL = e.target.value.trim()
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
  })
  if (r.ok) setStatus('#ai-status', '✓ 成功：' + r.text, 'ok')
  else setStatus('#ai-status', '✗ ' + r.error, 'err')
})

/* ---------------- 状态、保存、取消 ---------------- */

function setStatus(sel, text, cls) {
  const el = $(sel)
  el.textContent = text || ''
  el.className = 's-status' + (cls ? ' ' + cls : '')
}

$('#save').addEventListener('click', async () => {
  const hk = state.hotkeys
  const vals = [hk.input, hk.screenshot, hk.selection]
  if (vals.some((v) => !v)) {
    setStatus('#save-status', '✗ 三个快捷键都要设置', 'err')
    return
  }
  if (new Set(vals).size !== vals.length) {
    setStatus('#save-status', '✗ 快捷键不能重复', 'err')
    return
  }
  const meta = metaById[state.engine]
  const cfg = cfgFor(state.engine)
  if (meta && meta.needsBaseURL && !cfg.baseURL) {
    setStatus('#save-status', '✗ 自定义服务商需要填 Base URL', 'err')
    return
  }
  if (meta && meta.needsKey && !cfg.apiKey) {
    setStatus('#save-status', '✗「' + meta.label + '」需要填 API Key', 'err')
    return
  }

  const r = await window.api.saveSettings(state)
  if (r.hotkeyErrors && r.hotkeyErrors.length) {
    const names = { input: '输入翻译', screenshot: '截图翻译', selection: '划词翻译' }
    setStatus('#save-status', '✗ 无法注册（可能被占用）：' + r.hotkeyErrors.map((k) => names[k]).join('、'), 'err')
    return
  }
  setStatus('#save-status', '✓ 已保存', 'ok')
  setTimeout(() => window.api.closeSettings(), 500)
})

$('#cancel').addEventListener('click', () => window.api.closeSettings())
$('#close').addEventListener('click', () => window.api.closeSettings())
document.addEventListener('keydown', (e) => {
  if (e.key === 'Escape') window.api.closeSettings()
})

/* ---------------- 关于 ---------------- */

$('#about-repo').addEventListener('click', () => {
  const url = $('#about-repo').dataset.url
  if (url) window.api.openExternal(url)
})

window.api.getAppInfo().then((info) => {
  $('#about-version').textContent = 'v' + info.version
  $('#about-repo').dataset.url = info.repo
})

/* ---------------- 初始化 ---------------- */

function populate(s) {
  if (!s) return
  state = {
    engine: s.engine || 'google',
    hotkeys: { ...s.hotkeys },
    providers: JSON.parse(JSON.stringify(s.providers || {})),
  }
  document.querySelectorAll('.recorder').forEach(renderHotkey)
  if (metaList.length) renderEngine()
  setStatus('#save-status', '')
  setStatus('#ai-status', '')
}

window.api.onSettingsData((s) => populate(s))

;(async function init() {
  metaList = await window.api.getProviders()
  metaById = Object.fromEntries(metaList.map((m) => [m.id, m]))
  renderProviderOptions()
  const s = await window.api.getSettings()
  populate(s)
})()
