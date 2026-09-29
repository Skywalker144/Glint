'use strict'

const { scriptWeights } = require('../shared/language-scripts')

const LANGUAGES = [
  { code: 'zh-CN', label: '中文', promptName: '中文' },
  { code: 'en', label: '英语', promptName: '英文' },
  { code: 'ja', label: '日语', promptName: '日语' },
  { code: 'ko', label: '韩语', promptName: '韩语' },
  { code: 'fr', label: '法语', promptName: '法语' },
  { code: 'de', label: '德语', promptName: '德语' },
  { code: 'es', shortLabel: '西语', label: '西班牙语', promptName: '西班牙语' },
  { code: 'ru', label: '俄语', promptName: '俄语' },
  { code: 'it', shortLabel: '意语', label: '意大利语', promptName: '意大利语' },
  { code: 'pt', shortLabel: '葡语', label: '葡萄牙语', promptName: '葡萄牙语' },
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

// 单靠文字系统无法可靠区分主语言时，把方向判断交给 AI。
// 例如英 / 法 / 德都使用拉丁字母，俄语与其它西里尔语言共用字母，
// 纯汉字文本也可能是中文或日文。这些场景若由程序强制 target，会覆盖模型的正确语种判断。
function needsSemanticDirection(text, primaryLanguage) {
  const t = text || ''
  if (!t.trim()) return false
  const primary = primaryLanguage || 'zh-CN'
  const w = scriptWeights(t)
  const latinPrimary = ['en', 'fr', 'de', 'es', 'it', 'pt'].includes(primary)

  if (latinPrimary) {
    return w.latin > 0 && w.latin >= w.han && w.kana === 0 && w.hangul === 0 && w.cyrillic === 0
  }
  if (primary === 'ru') return w.cyrillic > 0
  if (primary === 'zh-CN') {
    return w.han > 0 && w.kana === 0 && w.hangul === 0 && w.han >= w.latin
  }
  if (primary === 'ja') {
    return w.han > 0 && w.kana === 0 && w.hangul === 0 && w.han >= w.latin
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
    semantic: needsSemanticDirection(text, primary),
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
  needsSemanticDirection,
  pickDirection,
  isWordLookup,
}
