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
  assert.ok(DEFAULT_DICTIONARY_PROMPT.includes('n.、adj.、vt.、vi.'))
  assert.ok(DEFAULT_DICTIONARY_PROMPT.includes('每个词性最多三个常用义项'))
  assert.ok(DEFAULT_DICTIONARY_PROMPT.includes('不要猜测'))
  assert.ok(DEFAULT_DICTIONARY_PROMPT.includes('不要把普通派生词强行还原'))
})

test('当前旧默认提示词在迁移列表中', () => {
  assert.ok(LEGACY_SYSTEM_PROMPTS.some((p) => p.includes('请按规则自动判断')))
  assert.ok(LEGACY_DICTIONARY_PROMPTS.some((p) => p.includes('复数 / 时态 / 比较级 / 派生等')))
})

test('dictionary extras cover every toggle combination and override custom templates', () => {
  for (let mask = 0; mask < 8; mask++) {
    const dictionaryExtras = { examples: !!(mask & 1), synonyms: !!(mask & 2), related: !!(mask & 4) }
    const out = buildSystemPrompt('zh-CN', '自定义 {{primary}} 词典，必须给例句', { dict: true, dictionaryExtras })
    assert.ok(out.startsWith('自定义 中文'))
    assert.ok(out.includes(dictionaryExtras.examples ? '例句：只给一条' : '禁止输出例句'))
    assert.ok(out.includes(dictionaryExtras.synonyms ? '近义词和反义词：各最多三个' : '禁止输出近义词和反义词'))
    assert.ok(out.includes(dictionaryExtras.related ? '关联词：最多三个' : '禁止输出关联词'))
    assert.ok(out.includes(mask ? '单独一行的 ---' : '不输出分隔线'))
  }
  const out = buildSystemPrompt('en', '自定义翻译', { dictionaryExtras: { examples: true } })
  assert.equal(out, '自定义翻译')
  assert.ok(buildSystemPrompt('en', '', { dict: true }).includes('禁止输出例句'))
})

test('compact dictionary markdown separates supplements without extra definition paragraphs', () => {
  const { renderMarkdown } = require('../src/main/markdown')
  const html = renderMarkdown('**abstract** /ˈæbstrækt/\nadj. 抽象的；难以理解的\nn. 摘要；梗概\n\n---\n\n近义 adj. conceptual')
  assert.equal((html.match(/<p>/g) || []).length, 2)
  assert.ok(html.includes('<hr>'))
  assert.ok(html.includes('<br>'))
})
