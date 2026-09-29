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
