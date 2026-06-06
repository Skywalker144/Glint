'use strict'

const $ = (sel) => document.querySelector(sel)

const input = $('#input')
const result = $('#result')
const status = $('#status')
const langtag = $('#langtag')
const resultbar = $('#resultbar')
const copyBtn = $('#copy')
const pinBtn = $('#pin')
const appEl = $('.app')

let lastTranslated = ''
let streamToken = 0
let pinned = false

// 让窗口高度自动贴合内容：卡片高度一变就报给主进程，主进程据此调整窗口高度。
// 没结果时只剩输入框（很矮），有结果/提示时自动长高，避免下方留空白。
new ResizeObserver(() => {
  window.api.resizeHeight(Math.ceil(appEl.getBoundingClientRect().height))
}).observe(appEl)

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

function doTranslate() {
  const text = input.value.trim()
  result.textContent = ''
  resultbar.hidden = true
  if (!text) {
    status.textContent = ''
    return
  }
  status.textContent = '翻译中…'
  lastTranslated = ''
  window.api.translateStream(text, ++streamToken)
}

// 流式事件：meta 定方向、delta 增量追加、done 收尾、error 报错。忽略过期 token，避免串流。
window.api.onTranslateEvent((m) => {
  if (m.token !== streamToken) return
  if (m.type === 'meta') {
    langtag.textContent =
      m.mode === 'dict' ? '词典 · ' + (m.word || '') : langName(m.source) + ' → ' + langName(m.target)
  } else if (m.type === 'delta') {
    status.textContent = ''
    result.textContent += m.delta
  } else if (m.type === 'done') {
    status.textContent = ''
    const finalText = (m.item && m.item.translated) || result.textContent
    result.textContent = finalText
    lastTranslated = finalText
    resultbar.hidden = !finalText
  } else if (m.type === 'error') {
    status.textContent = '翻译失败：' + m.error
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

$('#translate').addEventListener('click', doTranslate)
$('#close').addEventListener('click', () => window.api.hide())

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

document.addEventListener('keydown', (e) => {
  if (e.key === 'Escape') window.api.hide()
})

// 来自主进程的指令
window.api.onFocusInput(() => {
  streamToken++ // 作废可能在途的流
  input.value = ''
  result.textContent = ''
  status.textContent = ''
  resultbar.hidden = true
  langtag.textContent = '自动检测语言'
  input.focus()
})

window.api.onTranslateText((text) => {
  input.value = text
  input.focus()
  doTranslate()
})

window.api.onShowMessage((msg) => {
  streamToken++ // 作废可能在途的流
  result.textContent = ''
  resultbar.hidden = true
  status.textContent = msg
})
