'use strict'

const $ = (sel) => document.querySelector(sel)

const input = $('#input')
const result = $('#result')
const status = $('#status')
const sourceSel = $('#source-lang')
const dictionaryBtn = $('#dictionary-mode')
const swapBtn = $('#swap-languages')
const targetSel = $('#target-lang')
const resultbar = $('#resultbar')
const copyBtn = $('#copy')
const pinBtn = $('#pin')
const settingsBtn = $('#settings')
const translateBtn = $('#translate')
const stopBtn = $('#stop')
const retryBtn = $('#retry')
const speakInputBtn = $('#speak-input')
const speakResultBtn = $('#speak-result')
const appEl = $('.app')
const resizer = $('#resizer')

let streamToken = 0
let pinned = false
let rawResult = '' // 累积的原始译文（Markdown 源），用于渲染与复制
let renderScheduled = false
let renderSeq = 0
let appliedSeq = 0
let streaming = false // 是否正在流式生成（控制结尾闪烁光标）
let requestMode = 'auto'
let forcedSource = ''
let languageList = []
let forcedTarget = '' // 用户手动选的目标语言（''=自动方向）；窗口内保持，不落盘
let lastSource = 'auto' // 最近一次的检测源语言（用于朗读原文挑发音）
let lastTarget = '' // 最近一次的目标语言（用于朗读译文挑发音）

// 让窗口高度自动贴合内容：卡片高度一变就报给主进程，主进程据此调整窗口高度。
// 没结果时只剩输入框（很矮），有结果/提示时自动长高，避免下方留空白。
new ResizeObserver(() => {
  window.api.resizeHeight(Math.ceil(appEl.getBoundingClientRect().height))
}).observe(appEl)

input.addEventListener('input', () => {
  stopStreaming()
  requestMode = 'auto'
  setMode('translate')
  lastSource = 'auto'
  lastTarget = ''
  updateLanguageControls()
})

// 右边缘宽度拖拽：指针捕获让整段拖动都在手柄上收到事件（光标移出窗口也不丢），
// 拖动期间主进程抑制失焦收起，所以不会「刚拖就把窗口关了」。只调整宽度，高度仍随内容。
if (resizer) {
  let resizing = false
  let startX = 0
  resizer.addEventListener('pointerdown', (e) => {
    if (e.button !== 0) return
    resizing = true
    startX = e.screenX
    try {
      resizer.setPointerCapture(e.pointerId)
    } catch {}
    appEl.classList.add('resizing')
    window.api.resizeStart()
    e.preventDefault()
  })
  resizer.addEventListener('pointermove', (e) => {
    if (resizing) window.api.resizeMove(e.screenX - startX)
  })
  const endResize = (e) => {
    if (!resizing) return
    resizing = false
    appEl.classList.remove('resizing')
    try {
      resizer.releasePointerCapture(e.pointerId)
    } catch {}
    window.api.resizeEnd()
  }
  resizer.addEventListener('pointerup', endResize)
  resizer.addEventListener('pointercancel', endResize)
}

function setMode(mode) {
  dictionaryBtn.setAttribute('aria-pressed', String(mode === 'dict'))
  translateBtn.setAttribute('aria-pressed', String(mode === 'translate'))
}

function updateLanguageControls() {
  const source = forcedSource || lastSource
  const target = forcedTarget || lastTarget
  const sourceLanguage = languageList.find((language) => language.code === source)
  const targetLanguage = languageList.find((language) => language.code === target)
  sourceSel.value = forcedSource
  targetSel.value = forcedTarget
  sourceSel.title = (forcedSource ? '原文语言' : '自动识别') + (sourceLanguage ? '：' + sourceLanguage.label : '')
  targetSel.title = (forcedTarget ? '译文语言' : '自动选择') + (targetLanguage ? '：' + targetLanguage.label : '')
  const mixed = hasMixedLanguageScripts(input.value)
  swapBtn.disabled = !mixed || !sourceLanguage || !targetLanguage || source === target
  swapBtn.title = !mixed ? '仅混合语言原文可交换' : swapBtn.disabled ? '请先确定两种不同的语言' : '交换语言'
}

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

function setPhase(phase) {
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
  streamToken++
  window.api.stopStream()
  lastSource = forcedSource || 'auto'
  lastTarget = forcedTarget
  updateLanguageControls()
  result.textContent = ''
  rawResult = ''
  resultbar.hidden = true
  streaming = false
  if (!text) {
    status.textContent = ''
    setPhase('idle')
    return
  }
  status.textContent = requestMode === 'dict' ? '查词中…' : '翻译中…'
  streaming = true
  setPhase('streaming')
  window.api.translateStream(text, streamToken, { source: forcedSource, target: forcedTarget, mode: requestMode })
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
    setMode(m.mode)
    updateLanguageControls()
  } else if (m.type === 'delta') {
    status.textContent = ''
    rawResult += m.delta
    scheduleRender()
  } else if (m.type === 'done') {
    status.textContent = ''
    streaming = false
    setPhase('idle')
    rawResult = (m.item && m.item.translated) || rawResult
    lastSource = m.item?.source === 'zh' ? 'zh-CN' : m.item?.source || lastSource
    lastTarget = m.item?.target || lastTarget
    updateLanguageControls()
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
  // 中文输入法组词期间的回车/Esc 是「上屏 / 取消候选」（比如不切输入法直接打英文，
  // 打完按回车把英文上屏），要交给输入法处理，别当成提交翻译或关窗——否则上屏的回车
  // 会顺带触发翻译。isComposing 偶尔来不及置位，再用 keyCode 229 兜底。
  if (e.isComposing || e.keyCode === 229) return
  if (e.key === 'Enter' && !e.shiftKey) {
    e.preventDefault()
    doTranslate()
  } else if (e.key === 'Escape') {
    window.api.hide()
  }
})

for (const [button, mode] of [[dictionaryBtn, 'dict'], [translateBtn, 'translate']]) {
  button.addEventListener('click', () => {
    requestMode = mode
    setMode(mode)
    doTranslate()
  })
}

stopBtn.addEventListener('click', stopStreaming)
retryBtn.addEventListener('click', doTranslate)
$('#close').addEventListener('click', () => window.api.hide())
settingsBtn.addEventListener('click', () => window.api.openSettings())

for (const select of [sourceSel, targetSel]) {
  select.addEventListener('change', () => {
    forcedSource = sourceSel.value
    forcedTarget = targetSel.value
    lastSource = 'auto'
    lastTarget = ''
    updateLanguageControls()
    if (input.value.trim()) doTranslate()
    else input.focus()
  })
}

swapBtn.addEventListener('click', () => {
  const source = forcedSource || lastSource
  forcedSource = forcedTarget || lastTarget
  forcedTarget = source
  updateLanguageControls()
  if (input.value.trim()) doTranslate()
})

// 朗读原文 / 译文
speakInputBtn.addEventListener('click', () => {
  const t = input.value.trim()
  speak(t, forcedSource || (lastSource !== 'auto' ? lastSource : guessLang(t)), speakInputBtn)
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
  window.api.copyText(result.innerText.trim())
  copyBtn.textContent = '已复制'
  setTimeout(() => (copyBtn.textContent = '复制'), 1200)
})

document.addEventListener('keydown', (e) => {
  if (e.key === 'Escape') window.api.hide()
})

async function loadLanguages() {
  languageList = await window.api.getLanguages()
  for (const select of [sourceSel, targetSel]) {
    for (const language of languageList) {
      const option = document.createElement('option')
      option.value = language.code
      option.textContent = language.shortLabel || language.label
      select.appendChild(option)
    }
  }
  updateLanguageControls()
}
loadLanguages()

// 来自主进程的指令
window.api.onFocusInput(() => {
  input.value = ''
  requestMode = 'auto'
  setMode('translate')
  lastSource = 'auto'
  lastTarget = ''
  updateLanguageControls()
  streamToken++ // 作废可能在途的流
  streaming = false
  setPhase('idle')
  result.textContent = ''
  rawResult = ''
  status.textContent = ''
  resultbar.hidden = true
  input.focus()
})

window.api.onTranslateText((text) => {
  requestMode = 'auto'
  input.value = text
  input.focus()
  doTranslate()
})

window.api.onShowMessage((msg) => {
  requestMode = 'auto'
  setMode('translate')
  lastSource = 'auto'
  lastTarget = ''
  updateLanguageControls()
  streamToken++ // 作废可能在途的流
  streaming = false
  setPhase('idle')
  result.textContent = ''
  rawResult = ''
  resultbar.hidden = true
  status.textContent = msg
  // 把焦点收到输入框并全选已有文字：
  // - 焦点不落到第一个可聚焦元素（设置齿轮），免得它上面画出键盘焦点环、还可能误触发设置；
  // - 全选让用户在取词 / 识别失败后直接打字就能替换掉原文框里残留的旧文字。
  input.focus()
  input.select()
})
