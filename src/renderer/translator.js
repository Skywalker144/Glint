'use strict'

const $ = (sel) => document.querySelector(sel)

const input = $('#input')
const result = $('#result')
const status = $('#status')
const langtag = $('#langtag')
const arrowEl = $('.arrow')
const targetSel = $('#target-lang')
const resultbar = $('#resultbar')
const copyBtn = $('#copy')
const copyPlainBtn = $('#copy-plain')
const pinBtn = $('#pin')
const settingsBtn = $('#settings')
const translateBtn = $('#translate')
const stopBtn = $('#stop')
const retryBtn = $('#retry')
const speakInputBtn = $('#speak-input')
const speakResultBtn = $('#speak-result')
const appEl = $('.app')

let lastTranslated = ''
let streamToken = 0
let pinned = false
let rawResult = '' // 累积的原始译文（Markdown 源），用于渲染与复制
let renderScheduled = false
let renderSeq = 0
let appliedSeq = 0
let streaming = false // 是否正在流式生成（控制结尾闪烁光标）
let forcedTarget = '' // 用户手动选的目标语言（''=自动方向）；窗口内保持，不落盘
let lastSource = 'auto' // 最近一次的检测源语言（用于朗读原文挑发音）
let lastTarget = '' // 最近一次的目标语言（用于朗读译文挑发音）

// 让窗口高度自动贴合内容：卡片高度一变就报给主进程，主进程据此调整窗口高度。
// 没结果时只剩输入框（很矮），有结果/提示时自动长高，避免下方留空白。
new ResizeObserver(() => {
  window.api.resizeHeight(Math.ceil(appEl.getBoundingClientRect().height))
}).observe(appEl)

// 输入框高度自适应：没结果时用 CSS 固定高（宽松、好粘贴）；有结果时贴合内容——
// 短原文收到最小、长原文最多撑到 ~84px（约 3 行）再内部滚动，
// 避免长原文被死收成 46px（约 1.5 行）而截断显得怪。
function autoSizeInput() {
  if (!appEl.classList.contains('has-result')) {
    input.style.height = '' // 回到 CSS 的 84px
    return
  }
  input.style.height = 'auto'
  input.style.height = Math.min(84, Math.max(40, input.scrollHeight)) + 'px'
}
input.addEventListener('input', autoSizeInput)

const LANG_NAMES = {
  'zh-CN': '中文',
  zh: '中文',
  en: '英语',
  ja: '日语',
  ko: '韩语',
  fr: '法语',
  de: '德语',
  es: '西班牙语',
  ru: '俄语',
  it: '意大利语',
  pt: '葡萄牙语',
  auto: '自动',
}
const langName = (code) => LANG_NAMES[code] || code || '自动'

// 目标语言 → 朗读用的 BCP-47 语言标签（speechSynthesis 据此挑系统语音）。
const SPEAK_LANG = {
  'zh-CN': 'zh-CN', zh: 'zh-CN', en: 'en-US', ja: 'ja-JP', ko: 'ko-KR',
  fr: 'fr-FR', de: 'de-DE', es: 'es-ES', ru: 'ru-RU', it: 'it-IT', pt: 'pt-PT',
}

// 输入还没翻译过时，按文字系统粗判语言，给朗读挑个合适发音。
function guessLang(t) {
  if (/[぀-ヿ]/.test(t)) return 'ja'
  if (/[가-힯]/.test(t)) return 'ko'
  if (/[㐀-鿿]/.test(t)) return 'zh-CN'
  if (/[Ѐ-ӿ]/.test(t)) return 'ru'
  return 'en'
}

let currentAudio = null

// 本地语音（Web Speech）：作为在线 TTS 的离线 / 失败回退。
function speakLocal(text, code) {
  if (!window.speechSynthesis) return
  try {
    window.speechSynthesis.cancel()
    const u = new SpeechSynthesisUtterance(text)
    const lang = SPEAK_LANG[code]
    if (lang) u.lang = lang
    window.speechSynthesis.speak(u)
  } catch {}
}

// 朗读：优先用主进程取的在线自然语音（Google TTS，神经网络音质），
// 离线 / 失败时回退本地 Web Speech。btn 仅用于播放时高亮。
async function speak(text, code, btn) {
  text = (text || '').trim()
  if (!text) return
  if (currentAudio) {
    try { currentAudio.pause() } catch {}
    currentAudio = null
  }
  if (window.speechSynthesis) window.speechSynthesis.cancel()
  if (btn) btn.classList.add('speaking')
  const clear = () => btn && btn.classList.remove('speaking')
  try {
    const r = await window.api.speak(text, code)
    if (r && r.ok && r.audio) {
      const audio = new Audio('data:audio/mpeg;base64,' + r.audio)
      currentAudio = audio
      audio.onended = clear
      audio.onerror = clear
      await audio.play()
      return
    }
  } catch {}
  clear()
  speakLocal(text, code) // 离线 / 失败回退本地语音
}

// 三态按钮：idle 显示「翻译」、streaming 显示「停止」、error 显示「重试」。
function setPhase(phase) {
  translateBtn.hidden = phase !== 'idle'
  stopBtn.hidden = phase !== 'streaming'
  retryBtn.hidden = phase !== 'error'
}

// 把累积的原始译文渲染成 HTML（Markdown + 公式）。token/seq 守卫，避免过期或乱序覆盖。
function renderResult() {
  const token = streamToken
  const seq = ++renderSeq
  window.api.renderMarkdown(rawResult).then((html) => {
    if (token !== streamToken || seq < appliedSeq) return
    appliedSeq = seq
    result.innerHTML = html
    appEl.classList.toggle('has-result', !!rawResult)
    autoSizeInput()
    if (streaming && rawResult) {
      const caret = document.createElement('span')
      caret.className = 'stream-caret'
      ;(result.lastElementChild || result).appendChild(caret)
    }
  })
}
function scheduleRender() {
  if (renderScheduled) return
  renderScheduled = true
  requestAnimationFrame(() => {
    renderScheduled = false
    renderResult()
  })
}

function doTranslate() {
  const text = input.value.trim()
  result.textContent = ''
  rawResult = ''
  resultbar.hidden = true
  appEl.classList.remove('has-result')
  autoSizeInput()
  streaming = false
  if (!text) {
    status.textContent = ''
    setPhase('idle')
    return
  }
  status.textContent = '翻译中…'
  lastTranslated = ''
  streaming = true
  setPhase('streaming')
  window.api.translateStream(text, ++streamToken, forcedTarget || '')
}

// 停止：中断在途请求，保留已生成的部分。
function stopStreaming() {
  if (!streaming) return
  window.api.stopStream()
  streamToken++ // 作废在途事件
  streaming = false
  status.textContent = ''
  setPhase('idle')
  if (rawResult) {
    lastTranslated = rawResult
    resultbar.hidden = false
  }
  renderResult()
}

// 流式事件：meta 定方向、delta 累积并重渲、done 收尾、error 报错。忽略过期 token。
window.api.onTranslateEvent((m) => {
  if (m.token !== streamToken) return
  if (m.type === 'meta') {
    lastSource = m.source || 'auto'
    lastTarget = m.target || ''
    const dict = m.mode === 'dict'
    arrowEl.hidden = dict // 词典查词没有「源→目标」方向，藏掉箭头免得误读
    langtag.textContent = dict ? '词典 · ' + (m.word || '') : langName(m.source)
  } else if (m.type === 'delta') {
    status.textContent = ''
    rawResult += m.delta
    scheduleRender()
  } else if (m.type === 'done') {
    status.textContent = ''
    streaming = false
    setPhase('idle')
    rawResult = (m.item && m.item.translated) || rawResult
    lastTranslated = rawResult
    resultbar.hidden = !rawResult
    renderResult()
  } else if (m.type === 'error') {
    streaming = false
    setPhase('error')
    status.textContent = '翻译失败：' + m.error
  }
})

// 译文里的链接点击 → 用系统浏览器打开（不在窗口内导航）
result.addEventListener('click', (e) => {
  const a = e.target.closest('a')
  if (a && a.href) {
    e.preventDefault()
    window.api.openExternal(a.href)
  }
})

input.addEventListener('keydown', (e) => {
  if (e.key === 'Enter' && !e.shiftKey) {
    e.preventDefault()
    doTranslate()
  } else if (e.key === 'Escape') {
    window.api.hide()
  }
})

translateBtn.addEventListener('click', doTranslate)
stopBtn.addEventListener('click', stopStreaming)
retryBtn.addEventListener('click', doTranslate)
$('#close').addEventListener('click', () => window.api.hide())
settingsBtn.addEventListener('click', () => window.api.openSettings())

// 目标语言选择：''=自动方向。改完若有输入就立即重翻。
targetSel.addEventListener('change', () => {
  forcedTarget = targetSel.value
  if (input.value.trim()) doTranslate()
  else input.focus()
})

// 朗读原文 / 译文
speakInputBtn.addEventListener('click', () => {
  const t = input.value.trim()
  speak(t, lastSource !== 'auto' ? lastSource : guessLang(t), speakInputBtn)
})
speakResultBtn.addEventListener('click', () => speak(result.innerText, lastTarget, speakResultBtn))

function renderPin() {
  pinBtn.classList.toggle('pinned', pinned)
  pinBtn.title = pinned
    ? '已钉住，点击取消（切到别的应用不消失）'
    : '钉住窗口（开启后切到别的应用也不消失）'
}
pinBtn.addEventListener('click', () => {
  pinned = !pinned
  renderPin()
  window.api.setPinned(pinned)
})
window.api.onPinState((v) => {
  pinned = !!v
  renderPin()
})

copyBtn.addEventListener('click', () => {
  window.api.copyText(lastTranslated)
  copyBtn.textContent = '已复制'
  setTimeout(() => (copyBtn.textContent = '复制译文'), 1200)
})
// 复制纯文本：复制渲染后的可见文字，不带 Markdown 符号（词典条目贴到别处更干净）。
copyPlainBtn.addEventListener('click', () => {
  window.api.copyText(result.innerText.trim())
  copyPlainBtn.textContent = '已复制'
  setTimeout(() => (copyPlainBtn.textContent = '复制纯文本'), 1200)
})

document.addEventListener('keydown', (e) => {
  if (e.key === 'Escape') window.api.hide()
})

// 用目标语言列表填充下拉框（首项「自动」）。
async function loadLanguages() {
  let list = []
  try {
    list = await window.api.getLanguages()
  } catch {}
  targetSel.innerHTML = ''
  const auto = document.createElement('option')
  auto.value = ''
  auto.textContent = '自动'
  targetSel.appendChild(auto)
  for (const l of list || []) {
    const o = document.createElement('option')
    o.value = l.code
    o.textContent = l.label
    targetSel.appendChild(o)
  }
  targetSel.value = forcedTarget
}
loadLanguages()

// 来自主进程的指令
window.api.onFocusInput(() => {
  streamToken++ // 作废可能在途的流
  streaming = false
  setPhase('idle')
  input.value = ''
  result.textContent = ''
  rawResult = ''
  appEl.classList.remove('has-result')
  autoSizeInput()
  status.textContent = ''
  resultbar.hidden = true
  arrowEl.hidden = false
  langtag.textContent = '自动'
  input.focus()
})

window.api.onTranslateText((text) => {
  input.value = text
  input.focus()
  doTranslate()
})

window.api.onShowMessage((msg) => {
  streamToken++ // 作废可能在途的流
  streaming = false
  setPhase('idle')
  result.textContent = ''
  rawResult = ''
  appEl.classList.remove('has-result')
  autoSizeInput()
  resultbar.hidden = true
  status.textContent = msg
})
