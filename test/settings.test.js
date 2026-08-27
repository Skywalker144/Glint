'use strict'

const { test } = require('node:test')
const assert = require('node:assert')
const { migrate, DEFAULTS } = require('../src/main/settings')
const {
  DEFAULT_SYSTEM_PROMPT,
  DEFAULT_DICTIONARY_PROMPT,
  LEGACY_SYSTEM_PROMPTS,
  LEGACY_DICTIONARY_PROMPTS,
} = require('../src/main/engines/prompt')

test('migrate: 旧默认提示词升级，自定义提示词保留', () => {
  const oldDefaults = migrate({
    systemPrompt: LEGACY_SYSTEM_PROMPTS[0],
    dictionaryPrompt: LEGACY_DICTIONARY_PROMPTS[0],
  })
  assert.strictEqual(oldDefaults.systemPrompt, DEFAULT_SYSTEM_PROMPT)
  assert.strictEqual(oldDefaults.dictionaryPrompt, DEFAULT_DICTIONARY_PROMPT)

  const custom = migrate({ systemPrompt: '我的翻译风格', dictionaryPrompt: '我的词典格式' })
  assert.strictEqual(custom.systemPrompt, '我的翻译风格')
  assert.strictEqual(custom.dictionaryPrompt, '我的词典格式')
})

test('migrate: DeepSeek 旧默认模型升级到 V4 Flash', () => {
  const raw = migrate({ providers: { deepseek: { model: 'deepseek-chat' } } })
  assert.strictEqual(raw.providers.deepseek.model, 'deepseek-v4-flash')
  assert.strictEqual(DEFAULTS.providers.deepseek.model, 'deepseek-v4-flash')
})

test('migrate: 不覆盖用户手动选择的 DeepSeek 模型', () => {
  const raw = migrate({ providers: { deepseek: { model: 'deepseek-v4-pro' } } })
  assert.strictEqual(raw.providers.deepseek.model, 'deepseek-v4-pro')
})
