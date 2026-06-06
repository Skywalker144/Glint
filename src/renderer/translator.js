'use strict'

const $ = (sel) => document.querySelector(sel)

const input = $('#input')
const result = $('#result')
const status = $('#status')
const langtag = $('#langtag')
const resultbar = $('#resultbar')
const copyBtn = $('#copy')
const appEl = $('.app')

let lastTranslated = ''

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

async function doTranslate() {
  const text = input.value.trim()
  result.textContent = ''
  resultbar.hidden = true
  if (!text) {
    status.textContent = ''
    return
  }

  status.textContent = '翻译中…'
  try {
    const r = await window.api.translate(text)
    status.textContent = ''
    langtag.textContent = langName(r.source) + ' → ' + langName(r.target)
    result.textContent = r.translated
    lastTranslated = r.translated
    resultbar.hidden = !r.translated
  } catch (e) {
    status.textContent = '翻译失败：' + e.message
  }
}

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
  result.textContent = ''
  resultbar.hidden = true
  status.textContent = msg
})
