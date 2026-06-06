'use strict'

const settings = require('./settings')
const { translateWith, translateStreamWith } = require('./engines')
const { getProvider } = require('./engines/providers')
const { DEFAULT_DICTIONARY_PROMPT } = require('./engines/prompt')
const history = require('./history')
const { pickDirection, isWordLookup } = require('./languages')

function pickTarget(text, primaryLanguage = 'zh-CN', secondaryLanguage = 'en') {
  return pickDirection(text, primaryLanguage, secondaryLanguage).target
}

// 单词时（且为 AI 引擎、开启词典）用词典提示词，否则用翻译提示词。
function promptFor(s, engineId, text) {
  const p = getProvider(engineId)
  const isDict = s.dictionaryMode !== false && p && p.kind !== 'free' && isWordLookup(text)
  return isDict ? s.dictionaryPrompt || DEFAULT_DICTIONARY_PROMPT : s.systemPrompt
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
    primaryLanguage: s.primaryLanguage,
    secondaryLanguage: s.secondaryLanguage,
    source: direction.source,
  })
  const item = { original: text, translated, source, target: direction.target, engine: engineId }
  history.add(item)
  return item
}

// 流式版：边生成边通过 onDelta 回吐；完成后写历史，返回最终 item。
async function translateStream(text, onDelta) {
  text = (text || '').trim()
  if (!text) return { original: '', translated: '', source: '', target: '', engine: '' }

  const s = settings.get()
  const direction = pickDirection(text, s.primaryLanguage, s.secondaryLanguage)
  const engineId = s.engine || 'google'
  const cfg = (s.providers && s.providers[engineId]) || {}

  const { translated, source } = await translateStreamWith(
    engineId,
    cfg,
    text,
    direction.target,
    {
      systemPrompt: promptFor(s, engineId, text),
      primaryLanguage: s.primaryLanguage,
      secondaryLanguage: s.secondaryLanguage,
      source: direction.source,
    },
    onDelta
  )

  const item = { original: text, translated, source, target: direction.target, engine: engineId }
  history.add(item)
  return item
}

module.exports = { translate, pickTarget, translateStream }
