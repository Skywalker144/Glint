'use strict'

const { lookup, renderEntry } = require('./dictionary')
const { getProvider } = require('./engines/providers')
const { pickDirection, isWordLookup, isLanguageCode } = require('./languages')

async function resolveTranslation(text, settings, options = {}) {
  const engine = settings.engine || 'google'
  const provider = getProvider(engine)
  if (!provider) throw new Error('未知翻译引擎：' + engine)
  const ai = provider.kind !== 'free'
  const direction = pickDirection(text, settings.primaryLanguage, settings.secondaryLanguage)
  const forced = isLanguageCode(options.target) ? options.target : ''
  const enabled = !forced && options.mode !== 'translate' && (options.mode === 'dict' || settings.dictionaryMode !== false)
  const pair = [settings.primaryLanguage || 'zh-CN', settings.secondaryLanguage || 'en']
  const englishChinese = pair.includes('en') && pair.some((code) => code.startsWith('zh'))
  const entry = enabled && (englishChinese || options.mode === 'dict') ? await lookup(text) : null
  const dict = enabled && (entry || (ai && isWordLookup(text)) || options.mode === 'dict')
  if (dict && !entry && !ai) throw new Error('词库未收录该词，请切换翻译模式或配置 AI 引擎')
  if (dict && text.length > 100) throw new Error('词典模式仅支持单词和短语，请切换翻译模式')
  const semantic = !forced && !dict && ai && direction.semantic
  return {
    engine, ai, entry, forced, semantic,
    mode: dict ? 'dict' : 'translate',
    source: entry ? 'en' : semantic ? 'auto' : direction.source,
    target: entry ? 'zh-CN' : semantic ? '' : forced || direction.target,
    engineTarget: forced || direction.target,
    word: dict ? entry?.word || text : '',
    attribution: entry ? 'ECDICT' : dict ? 'AI 生成 · 未经词库验证' : '',
    base: entry ? renderEntry(entry, text) : '',
    canSupplement: !!entry && ai,
  }
}

module.exports = { resolveTranslation }
