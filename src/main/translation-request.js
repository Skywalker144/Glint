'use strict'

const { getProvider } = require('./engines/providers')
const { DEFAULT_DICTIONARY_PROMPT } = require('./engines/prompt')
const { pickDirection, isWordLookup, isLanguageCode } = require('./languages')

function resolveTranslationRequest(text, settings, overrides = {}) {
  const engine = settings.engine || 'google'
  const provider = getProvider(engine)
  const primary = settings.primaryLanguage || 'zh-CN'
  const secondary = settings.secondaryLanguage || 'en'
  const source = isLanguageCode(overrides.source) ? overrides.source : ''
  const direction = source
    ? { source, target: source === primary ? secondary : primary, semantic: false }
    : pickDirection(text, primary, secondary)
  const forced = isLanguageCode(overrides.target) ? overrides.target : ''
  const ai = !!provider && provider.kind !== 'free'
  if (overrides.mode === 'dict' && !ai) throw new Error('当前引擎不支持词典，请在设置中选择 AI 引擎')
  const dict = ai && (overrides.mode === 'dict' ||
    (overrides.mode !== 'translate' && !forced && settings.dictionaryMode !== false && isWordLookup(text)))
  const target = forced || direction.target
  const dictionaryPrimary = (source || forced) ? target : primary
  const dictionarySecondary = source || (forced && target === secondary ? primary : secondary)
  const semanticDirection = !forced && !dict && ai && direction.semantic
  return {
    engine,
    config: (settings.providers && settings.providers[engine]) || {},
    target,
    options: {
      systemPrompt: dict ? settings.dictionaryPrompt || DEFAULT_DICTIONARY_PROMPT : forced ? '' : settings.systemPrompt,
      forceTarget: !!forced && !dict,
      forceSource: !!source,
      dict,
      semanticDirection,
      primaryLanguage: dict ? dictionaryPrimary : primary,
      secondaryLanguage: dict ? dictionarySecondary : secondary,
      source: semanticDirection ? 'auto' : direction.source,
    },
  }
}

module.exports = { resolveTranslationRequest }
