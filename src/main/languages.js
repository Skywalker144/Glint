'use strict'

const LANGUAGES = [
  { code: 'zh-CN', label: '中文', promptName: '中文' },
  { code: 'en', label: '英语', promptName: '英文' },
  { code: 'ja', label: '日语', promptName: '日语' },
  { code: 'ko', label: '韩语', promptName: '韩语' },
  { code: 'fr', label: '法语', promptName: '法语' },
  { code: 'de', label: '德语', promptName: '德语' },
  { code: 'es', label: '西班牙语', promptName: '西班牙语' },
  { code: 'ru', label: '俄语', promptName: '俄语' },
  { code: 'it', label: '意大利语', promptName: '意大利语' },
  { code: 'pt', label: '葡萄牙语', promptName: '葡萄牙语' },
]

const BY_CODE = Object.fromEntries(LANGUAGES.map((l) => [l.code, l]))

function isLanguageCode(code) {
  return !!BY_CODE[code]
}

function languageLabel(code) {
  return (BY_CODE[code] && BY_CODE[code].label) || code || '自动'
}

function promptLanguageName(code) {
  return (BY_CODE[code] && BY_CODE[code].promptName) || languageLabel(code)
}

function hasHan(text) {
  return /[㐀-鿿豈-﫿]/.test(text)
}

function hasKana(text) {
  return /[぀-ヿ]/.test(text)
}

function hasHangul(text) {
  return /[ᄀ-ᇿ㄰-㆏가-힯]/.test(text)
}

function hasCyrillic(text) {
  return /[Ѐ-ӿ]/.test(text)
}

function hasLatin(text) {
  return /[A-Za-zÀ-ÖØ-öø-ÿ]/.test(text)
}

function isProbablyLanguage(text, code) {
  const t = text || ''
  if (!t.trim()) return false
  if (code === 'zh-CN') return hasHan(t) && !hasKana(t) && !hasHangul(t)
  if (code === 'ja') return hasKana(t)
  if (code === 'ko') return hasHangul(t)
  if (code === 'ru') return hasCyrillic(t)
  if (['en', 'fr', 'de', 'es', 'it', 'pt'].includes(code)) {
    return hasLatin(t) && !hasHan(t) && !hasKana(t) && !hasHangul(t) && !hasCyrillic(t)
  }
  return false
}

function pickDirection(text, primaryLanguage, secondaryLanguage) {
  const primary = primaryLanguage || 'zh-CN'
  const secondary = secondaryLanguage || 'en'
  const source = isProbablyLanguage(text, primary) ? primary : 'auto'
  return {
    source,
    target: source === primary ? secondary : primary,
  }
}

// 判断输入是否像「一个单词」（用于切换词典模式）：无内部空白、主要由字母/汉字组成、不太长。
function isWordLookup(text) {
  const t = (text || '').trim()
  if (!t || t.length > 40) return false
  return /^[\p{L}\p{M}][\p{L}\p{M}'’\-·]*$/u.test(t)
}

module.exports = {
  LANGUAGES,
  languageLabel,
  isLanguageCode,
  promptLanguageName,
  isProbablyLanguage,
  pickDirection,
  isWordLookup,
}
