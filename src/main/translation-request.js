'use strict'

const { getProvider } = require('./engines/providers')
const { DEFAULT_DICTIONARY_PROMPT } = require('./engines/prompt')
const { pickDirection, isWordLookup, isLanguageCode } = require('./languages')

function resolveTranslationRequest(text, settings, overrides = {}) {
  const engine = settings.engine || 'google'
  const provider = getProvider(engine)
  const direction = pickDirection(text, settings.primaryLanguage, settings.secondaryLanguage)
  const forced = isLanguageCode(overrides.target) ? overrides.target : ''
  const ai = !!provider && provider.kind !== 'free'
  const dict = !forced && overrides.mode !== 'translate' && settings.dictionaryMode !== false && ai && isWordLookup(text)
  const semanticDirection = !forced && !dict && ai && direction.semantic
  return {
    engine,
    config: (settings.providers && settings.providers[engine]) || {},
    target: forced || direction.target,
    options: {
      systemPrompt: forced ? '' : dict ? settings.dictionaryPrompt || DEFAULT_DICTIONARY_PROMPT : settings.systemPrompt,
      forceTarget: !!forced,
      dict,
      semanticDirection,
      primaryLanguage: settings.primaryLanguage,
      secondaryLanguage: settings.secondaryLanguage,
      source: semanticDirection ? 'auto' : direction.source,
    },
  }
}

module.exports = { resolveTranslationRequest }
