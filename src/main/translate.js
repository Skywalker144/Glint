'use strict'

const settings = require('./settings')
const { translateWith, translateStreamWith } = require('./engines')
const history = require('./history')
const { pickDirection } = require('./languages')
const { resolveTranslationRequest } = require('./translation-request')

function pickTarget(text, primaryLanguage = 'zh-CN', secondaryLanguage = 'en') {
  return pickDirection(text, primaryLanguage, secondaryLanguage).target
}

async function translate(text) {
  return runTranslation(text, translateWith)
}

async function translateStream(text, onDelta, opts = {}) {
  return runTranslation(text, translateStreamWith, onDelta, opts)
}

async function runTranslation(text, run, onDelta, opts = {}) {
  text = (text || '').trim()
  if (!text) return { original: '', translated: '', source: '', target: '', engine: '' }

  const { engine, config, target, options } = resolveTranslationRequest(text, settings.get(), opts)
  const resultTarget = options.semanticDirection ? '' : target
  if (opts.onMeta) opts.onMeta({
    source: options.source,
    target: resultTarget,
    mode: options.dict ? 'dict' : 'translate',
    word: options.dict ? text : '',
  })
  const { translated, source } = await run(engine, config, text, target, { ...options, signal: opts.signal }, onDelta)
  if (opts.signal) opts.signal.throwIfAborted()
  const item = { original: text, translated, source, target: resultTarget, engine }
  history.add(item)
  return item
}

module.exports = { translate, pickTarget, translateStream }
