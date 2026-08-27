'use strict'

// 朗读相关纯逻辑（语言映射 + 切片），不依赖 electron，便于单测。

// 内部语言码 → Google TTS 的 tl 参数。
const TTS_LANG = {
  'zh-CN': 'zh-CN', zh: 'zh-CN', en: 'en', ja: 'ja', ko: 'ko',
  fr: 'fr', de: 'de', es: 'es', ru: 'ru', it: 'it', pt: 'pt',
}

function ttsLang(code) {
  return TTS_LANG[code] || 'en'
}

// Google TTS 单次约 200 字符上限：按 max 切片，尽量在空白/标点处断，不硬切单词。
function splitText(text, max = 190) {
  const out = []
  let s = (text || '').trim()
  const BREAK = /[\s。．.!?！？,，、;；:：]/
  while (s.length > max) {
    let idx = -1
    for (let i = max - 1; i > Math.floor(max * 0.5); i--) {
      if (BREAK.test(s[i])) {
        idx = i
        break
      }
    }
    if (idx < 0) idx = max - 1 // 这一段没有断点（如超长连写）就硬切
    out.push(s.slice(0, idx + 1).trim())
    s = s.slice(idx + 1).trim()
  }
  if (s) out.push(s)
  return out.filter(Boolean)
}

module.exports = { TTS_LANG, ttsLang, splitText }
