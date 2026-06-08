'use strict'

const { test } = require('node:test')
const assert = require('node:assert')
const { buildSystemPrompt, DEFAULT_SYSTEM_PROMPT } = require('../src/main/engines/prompt')

test('buildSystemPrompt: 替换 {{primary}} / {{secondary}}', () => {
  const out = buildSystemPrompt('en', '从 {{primary}} 译到 {{secondary}}', {
    primaryLanguage: 'zh-CN',
    secondaryLanguage: 'en',
  })
  assert.ok(out.includes('中文'))
  assert.ok(out.includes('英文'))
  assert.ok(!out.includes('{{'))
})

test('buildSystemPrompt: 三种 target 占位符写法都替换', () => {
  for (const tpl of ['{{target}}', '{target}', '${target}']) {
    const out = buildSystemPrompt('ja', '翻译成 ' + tpl, {})
    assert.ok(out.includes('日语'), '未替换：' + tpl)
    assert.ok(!out.includes('target'), '残留：' + tpl)
  }
})

test('buildSystemPrompt: 模板为空时回退默认提示词', () => {
  const out = buildSystemPrompt('en', '', { primaryLanguage: 'zh-CN', secondaryLanguage: 'en' })
  assert.ok(out.length > 0)
  assert.ok(!out.includes('{{primary}}'))
  assert.ok(!out.includes('{{secondary}}'))
})

test('DEFAULT_SYSTEM_PROMPT 用的是 primary/secondary 占位符', () => {
  assert.ok(DEFAULT_SYSTEM_PROMPT.includes('{{primary}}'))
  assert.ok(DEFAULT_SYSTEM_PROMPT.includes('{{secondary}}'))
})
