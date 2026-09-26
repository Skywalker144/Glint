'use strict'

const { test } = require('node:test')
const assert = require('node:assert/strict')
const { resolveTranslation } = require('../src/main/translation-plan')
const settings = { engine: 'google', dictionaryMode: true, primaryLanguage: 'zh-CN', secondaryLanguage: 'en' }

test('free engines use real dictionary for words and known phrases', async () => {
  for (const text of ['apple', 'ran', 'look up']) {
    const plan = await resolveTranslation(text, settings)
    assert.equal(plan.mode, 'dict')
    assert.equal(plan.source, 'en')
    assert.equal(plan.attribution, 'ECDICT')
  }
})

test('explicit translation, forced target and disabled dictionary bypass lookup', async () => {
  for (const [state, options] of [[settings, { mode: 'translate' }], [settings, { target: 'ja' }], [{ ...settings, dictionaryMode: false }, {}]]) {
    assert.equal((await resolveTranslation('apple', state, options)).mode, 'translate')
  }
  assert.equal((await resolveTranslation('please translate this entire sentence', settings)).mode, 'translate')
  assert.equal((await resolveTranslation('apple', { ...settings, primaryLanguage: 'ja', secondaryLanguage: 'en' })).mode, 'translate')
})

test('manual dictionary overrides auto preference; unsupported lookup has an honest failure', async () => {
  assert.equal((await resolveTranslation('apple', { ...settings, dictionaryMode: false }, { mode: 'dict' })).mode, 'dict')
  await assert.rejects(resolveTranslation('zxqnonexistent', settings, { mode: 'dict' }), /未收录/)
  const plan = await resolveTranslation('zxqnonexistent', { ...settings, engine: 'deepseek' }, { mode: 'dict' })
  assert.equal(plan.attribution, 'AI 生成 · 未经词库验证')
})
