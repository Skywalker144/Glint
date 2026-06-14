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

// 各书写系统的「分量」：表意文字（汉字）/ 假名 / 谚文 / 西里尔按字符数计，
// 拉丁按「词」（连续字母段）数计——让「一个汉字 ≈ 一个英文词」，量纲一致，
// 中英混排时才能按主体语种判方向，而不是「文本里沾一个汉字就当中文」
// （否则整段英文里夹个「秒开 / 彻底删除此库」就被判成中文 → 英译英 echo）。
function scriptWeights(text) {
  const t = text || ''
  return {
    han: (t.match(/\p{Script=Han}/gu) || []).length,
    kana: (t.match(/[\p{Script=Hiragana}\p{Script=Katakana}]/gu) || []).length,
    hangul: (t.match(/\p{Script=Hangul}/gu) || []).length,
    cyrillic: (t.match(/\p{Script=Cyrillic}/gu) || []).length,
    latin: (t.match(/[A-Za-zÀ-ÖØ-öø-ÿ]+/g) || []).length,
  }
}

// 判断文本的「主体书写系统」是否属于某语言：混排时按分量比谁主导决定。
// 含假名 / 谚文则排除中文（日文汉字+假名、韩文都不算中文）。
function isProbablyLanguage(text, code) {
  const t = text || ''
  if (!t.trim()) return false
  const w = scriptWeights(t)
  if (code === 'zh-CN') return w.han > 0 && w.kana === 0 && w.hangul === 0 && w.han >= w.latin
  if (code === 'ja') return w.kana > 0
  if (code === 'ko') return w.hangul > 0
  if (code === 'ru') return w.cyrillic > 0
  if (['en', 'fr', 'de', 'es', 'it', 'pt'].includes(code)) {
    return w.latin > 0 && w.kana === 0 && w.hangul === 0 && w.cyrillic === 0 && w.latin >= w.han
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
  // 形态上得像「一个 token」：无内部空白、无数字/句读，只由字母（含撇号 / 连字符 / 中点）组成。
  if (!/^[\p{L}\p{M}][\p{L}\p{M}'’\-·]*$/u.test(t)) return false
  // 中日韩没有词间空格，光靠「无空白」会把整句也当成词。把汉字 / 平假名 / 片假名算作同一个 CJK 桶
  // （日文「食べる」这种汉字+假名混写是单词常态，不算多语言），含 CJK 时再加两道闸：
  const cjk = (t.match(/[\p{Script=Han}\p{Script=Hiragana}\p{Script=Katakana}]/gu) || []).length
  if (cjk > 0) {
    if (cjk > 4) return false // ① 表意字数过多 → 短语 / 句子；真正查词一般 1–4 字
    if (/[A-Za-z]{2,}/.test(t)) return false // ② 汉字里夹着成段拉丁词（LLM、API、用AI…）→ 短语；只夹单字母的借词（T恤、C语言）仍当词
  }
  return true
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
