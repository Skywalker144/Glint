'use strict'

const settings = require('./settings')
const { translateWith, translateStreamWith } = require('./engines')
const { getProvider } = require('./engines/providers')
const { DEFAULT_DICTIONARY_PROMPT } = require('./engines/prompt')
const history = require('./history')
const { pickDirection, isWordLookup, isLanguageCode } = require('./languages')

function pickTarget(text, primaryLanguage = 'zh-CN', secondaryLanguage = 'en') {
  return pickDirection(text, primaryLanguage, secondaryLanguage).target
}

// 输入像单词、且为 AI 引擎、开启词典时走词典模式。
function isDictLookup(s, engineId, text) {
  const p = getProvider(engineId)
  return s.dictionaryMode !== false && p && p.kind !== 'free' && isWordLookup(text)
}

// 单词时用词典提示词，否则用翻译提示词。
function promptFor(s, engineId, text) {
  return isDictLookup(s, engineId, text) ? s.dictionaryPrompt || DEFAULT_DICTIONARY_PROMPT : s.systemPrompt
}

// 统一入口：根据设置里选中的服务商分发。返回 {original, translated, source, target, engine}
async function translate(text) {
  text = (text || '').trim()
  if (!text) return { original: '', translated: '', source: '', target: '', engine: '' }

  const s = settings.get()
  const direction = pickDirection(text, s.primaryLanguage, s.secondaryLanguage)
  const engineId = s.engine || 'google'
  const cfg = (s.providers && s.providers[engineId]) || {}

  const { translated, source } = await translateWith(engineId, cfg, text, direction.target, {
    systemPrompt: promptFor(s, engineId, text),
    dict: isDictLookup(s, engineId, text),
    primaryLanguage: s.primaryLanguage,
    secondaryLanguage: s.secondaryLanguage,
    source: direction.source,
  })
  const item = { original: text, translated, source, target: direction.target, engine: engineId }
  history.add(item)
  return item
}

// 流式版：边生成边通过 onDelta 回吐；完成后写历史，返回最终 item。
// opts: { signal 中断信号, target 用户手动指定的目标语言（覆盖自动方向） }
async function translateStream(text, onDelta, opts = {}) {
  text = (text || '').trim()
  if (!text) return { original: '', translated: '', source: '', target: '', engine: '' }

  const s = settings.get()
  const direction = pickDirection(text, s.primaryLanguage, s.secondaryLanguage)
  const engineId = s.engine || 'google'
  const cfg = (s.providers && s.providers[engineId]) || {}

  // 手动指定了有效目标语言 → 强制翻成它（不走词典、不按自动方向）。
  const forced = opts.target && isLanguageCode(opts.target) ? opts.target : ''
  const target = forced || direction.target
  const dict = !forced && isDictLookup(s, engineId, text)

  const { translated, source } = await translateStreamWith(
    engineId,
    cfg,
    text,
    target,
    {
      systemPrompt: forced ? '' : promptFor(s, engineId, text),
      forceTarget: !!forced,
      dict,
      primaryLanguage: s.primaryLanguage,
      secondaryLanguage: s.secondaryLanguage,
      source: direction.source,
      signal: opts.signal,
    },
    onDelta
  )

  const item = { original: text, translated, source, target, engine: engineId }
  history.add(item)
  return item
}

module.exports = { translate, pickTarget, translateStream }
