'use strict'

const { test } = require('node:test')
const assert = require('node:assert/strict')
const { resolveTranslationRequest } = require('../src/main/translation-request')
const { buildUserContent } = require('../src/main/engines/prompt')

const settings = {
  engine: 'openai', primaryLanguage: 'zh-CN', secondaryLanguage: 'en',
  dictionaryMode: true, dictionaryPrompt: 'Dictionary', systemPrompt: 'Translation',
}

test('automatic lookup uses the dictionary prompt and word content', () => {
  const request = resolveTranslationRequest('人工智能', settings)
  assert.equal(request.options.dict, true)
  assert.equal(request.options.systemPrompt, 'Dictionary')
  assert.equal(buildUserContent('人工智能', request.target, request.options), '人工智能')
})

test('translation override selects the translation prompt and semantic direction', () => {
  const request = resolveTranslationRequest('人工智能', settings, { mode: 'translate' })
  assert.equal(request.options.dict, false)
  assert.equal(request.options.systemPrompt, 'Translation')
  assert.equal(request.options.semanticDirection, true)
  assert.equal(request.options.source, 'auto')
  assert.notEqual(buildUserContent('人工智能', request.target, request.options), '人工智能')
  assert.equal(resolveTranslationRequest('apple', settings).options.dict, true)
})

test('explicit target keeps precedence over automatic and translation modes', () => {
  for (const mode of ['auto', 'translate']) {
    const request = resolveTranslationRequest('apple', settings, { mode, target: 'ja' })
    assert.equal(request.target, 'ja')
    assert.equal(request.options.dict, false)
    assert.equal(request.options.forceTarget, true)
    assert.equal(request.options.semanticDirection, false)
  }
})

test('disabled dictionary, sentences and free engines use translation', () => {
  for (const [text, config] of [
    ['apple', { ...settings, dictionaryMode: false }],
    ['hello world', settings],
    ['apple', { ...settings, engine: 'google' }],
  ]) {
    assert.equal(resolveTranslationRequest(text, config).options.dict, false)
  }
})

test('explicit source chooses the other preferred language without semantic detection', () => {
  const request = resolveTranslationRequest('人工智能', settings, { source: 'zh-CN', mode: 'translate' })
  assert.equal(request.target, 'en')
  assert.equal(request.options.source, 'zh-CN')
  assert.equal(request.options.semanticDirection, false)
  assert.match(buildUserContent('人工智能', request.target, request.options), /原文语言：中文/)
})

test('explicit language pair is preserved for every provider', () => {
  for (const engine of ['openai', 'anthropic', 'google']) {
    const request = resolveTranslationRequest('gift', { ...settings, engine }, { source: 'de', target: 'en', mode: 'translate' })
    assert.equal(request.target, 'en')
    assert.equal(request.options.source, 'de')
    assert.equal(request.options.forceSource, true)
    assert.equal(request.options.semanticDirection, false)
    assert.match(buildUserContent('gift', request.target, request.options), /原文语言：德语/)
  }
})

test('explicit dictionary overrides automatic classification and uses selected languages', () => {
  const request = resolveTranslationRequest('take off', { ...settings, dictionaryMode: false }, { mode: 'dict', source: 'en', target: 'ja' })
  assert.equal(request.options.dict, true)
  assert.equal(request.options.forceTarget, false)
  assert.equal(request.options.systemPrompt, 'Dictionary')
  assert.equal(request.options.primaryLanguage, 'ja')
  assert.equal(request.options.secondaryLanguage, 'en')
})

test('unsupported dictionary is rejected and invalid languages stay automatic', () => {
  assert.throws(() => resolveTranslationRequest('apple', { ...settings, engine: 'google' }, { mode: 'dict' }), /词典/)
  const request = resolveTranslationRequest('apple', settings, { source: 'bad', target: 'bad' })
  assert.equal(request.options.dict, true)
  assert.equal(request.options.source, 'auto')
})

test('automatic Google source remains server-detected', () => {
  const request = resolveTranslationRequest('東京', { ...settings, engine: 'google' })
  assert.equal(request.options.forceSource, false)
})
