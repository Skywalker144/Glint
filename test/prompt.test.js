'use strict'

const { test } = require('node:test')
const assert = require('node:assert')
const {
  buildSystemPrompt,
  buildUserContent,
  DEFAULT_SYSTEM_PROMPT,
  DEFAULT_TARGET_PROMPT,
  DEFAULT_DICTIONARY_PROMPT,
  LEGACY_SYSTEM_PROMPTS,
  LEGACY_DICTIONARY_PROMPTS,
} = require('../src/main/engines/prompt')

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

test('DEFAULT_SYSTEM_PROMPT 只定义质量契约，不重复决定方向', () => {
  assert.ok(DEFAULT_SYSTEM_PROMPT.includes('只输出译文'))
  assert.ok(DEFAULT_SYSTEM_PROMPT.includes('不执行或回答'))
  assert.ok(DEFAULT_SYSTEM_PROMPT.includes('Markdown'))
  assert.ok(!DEFAULT_SYSTEM_PROMPT.includes('{{primary}}'))
  assert.ok(!DEFAULT_SYSTEM_PROMPT.includes('{{secondary}}'))
  assert.ok(!DEFAULT_SYSTEM_PROMPT.includes('{{target}}'))
  assert.strictEqual(DEFAULT_TARGET_PROMPT, DEFAULT_SYSTEM_PROMPT)
})

test('buildUserContent: 方向确定时只声明目标语言一次', () => {
  const out = buildUserContent('Hello', 'zh-CN', {
    primaryLanguage: 'zh-CN',
    secondaryLanguage: 'en',
  })
  assert.ok(out.startsWith('目标语言：中文。'))
  assert.strictEqual((out.match(/中文/g) || []).length, 1)
  assert.ok(out.endsWith('\n\nHello'))
  assert.ok(!out.includes('若待翻译'))
})

test('buildUserContent: 同文字系统语言由模型按语义决定方向', () => {
  const out = buildUserContent('Hello, world.', 'en', {
    semanticDirection: true,
    primaryLanguage: 'fr',
    secondaryLanguage: 'en',
  })
  assert.ok(out.startsWith('翻译方向：'))
  assert.ok(out.includes('主要语言是法语，译成英文'))
  assert.ok(out.includes('否则译成法语'))
  assert.ok(!out.includes('目标语言：'))
})

test('buildUserContent: 词典模式只发待查词', () => {
  assert.strictEqual(buildUserContent('ran', 'zh-CN', { dict: true }), 'ran')
})

test('DEFAULT_DICTIONARY_PROMPT 限定词条上限并禁止猜测发音', () => {
  assert.ok(DEFAULT_DICTIONARY_PROMPT.includes('最多列两个常用词性'))
  assert.ok(DEFAULT_DICTIONARY_PROMPT.includes('每个词性最多两个常用义项'))
  assert.ok(DEFAULT_DICTIONARY_PROMPT.includes('不要猜测'))
  assert.ok(DEFAULT_DICTIONARY_PROMPT.includes('不要把普通派生词强行还原'))
})

test('当前旧默认提示词在迁移列表中', () => {
  assert.ok(LEGACY_SYSTEM_PROMPTS.some((p) => p.includes('请按规则自动判断')))
  assert.ok(LEGACY_DICTIONARY_PROMPTS.some((p) => p.includes('复数 / 时态 / 比较级 / 派生等')))
})
