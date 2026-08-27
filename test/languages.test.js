'use strict'

const { test } = require('node:test')
const assert = require('node:assert')
const {
  pickDirection,
  isWordLookup,
  isProbablyLanguage,
  needsSemanticDirection,
} = require('../src/main/languages')

test('pickDirection: 中文输入 → 副语言（之前线上反过的方向）', () => {
  const d = pickDirection('迭代', 'zh-CN', 'en')
  assert.strictEqual(d.source, 'zh-CN')
  assert.strictEqual(d.target, 'en')
})

test('pickDirection: 英文输入 → 主语言', () => {
  const d = pickDirection('iterate', 'zh-CN', 'en')
  assert.strictEqual(d.target, 'zh-CN')

  const filename = pickDirection('meta_game_payoff_heatmap.png', 'zh-CN', 'en')
  assert.strictEqual(filename.target, 'zh-CN')
})

test('pickDirection: 其它语言（日语）→ 主语言', () => {
  const d = pickDirection('こんにちは', 'zh-CN', 'en')
  assert.strictEqual(d.source, 'auto')
  assert.strictEqual(d.target, 'zh-CN')
})

test('pickDirection: 自定义主/副语言（英↔日）', () => {
  const d = pickDirection('hello', 'en', 'ja')
  assert.strictEqual(d.source, 'en')
  assert.strictEqual(d.target, 'ja')
})

test('isWordLookup: 单词命中、整句不命中', () => {
  assert.ok(isWordLookup('apple'))
  assert.ok(isWordLookup('迭代'))
  assert.ok(isWordLookup('naïve'))
  assert.ok(isWordLookup("don't"))
  assert.ok(isWordLookup('人工智能')) // 4 字以内的中文词仍是词
  assert.ok(isWordLookup('C语言')) // 只夹单个字母的借词仍是词
  assert.ok(isWordLookup('食べる')) // 日文汉字+假名混写是单词常态
  assert.ok(!isWordLookup('hello world'))
  assert.ok(!isWordLookup('这是一个句子。'))
  assert.ok(!isWordLookup('一个基于LLM的快捷翻译软件')) // 中文整句无空格、又夹拉丁词，不该当成词
  assert.ok(!isWordLookup('用AI写代码')) // 中英混排（成段拉丁）→ 短语
  assert.ok(!isWordLookup('机器学习算法导论')) // 纯中文但字数过多 → 短语
  assert.ok(!isWordLookup(''))
  assert.ok(!isWordLookup('a'.repeat(50)))
})

test('pickDirection: 英文为主、夹少量中文词 → 仍判英文（修复「英译英」echo）', () => {
  const mostlyEnglish =
    'Done. Thumbnail lazy-loading is implemented and verified. Each thumbnail is its own ' +
    'encrypted blob, the meta only carries lightweight flags, so unlock only decrypts the slim ' +
    'metas → 秒开. There is still a pending Rust change (彻底删除此库), so do a full restart.'
  assert.ok(!isProbablyLanguage(mostlyEnglish, 'zh-CN'))
  const d = pickDirection(mostlyEnglish, 'zh-CN', 'en')
  assert.strictEqual(d.source, 'auto')
  assert.strictEqual(d.target, 'zh-CN')
})

test('pickDirection: 中文为主、夹外来词（LLM / app）→ 仍判中文', () => {
  assert.ok(isProbablyLanguage('我在用 LLM 写一个翻译 app', 'zh-CN'))
  const d = pickDirection('我在用 LLM 写一个翻译 app', 'zh-CN', 'en')
  assert.strictEqual(d.source, 'zh-CN')
  assert.strictEqual(d.target, 'en')
})

test('isProbablyLanguage: 文字系统判断', () => {
  assert.ok(isProbablyLanguage('hello', 'en'))
  assert.ok(!isProbablyLanguage('你好', 'en'))
  assert.ok(isProbablyLanguage('你好', 'zh-CN'))
  assert.ok(!isProbablyLanguage('こんにちは', 'zh-CN'))
  assert.ok(isProbablyLanguage('こんにちは', 'ja'))
  assert.ok(isProbablyLanguage('Привет', 'ru'))
})

test('needsSemanticDirection: 拉丁语系不由字母系统强制方向', () => {
  assert.ok(needsSemanticDirection('Hello, world.', 'fr'))
  assert.ok(needsSemanticDirection('Bonjour tout le monde.', 'en'))
  assert.ok(needsSemanticDirection('Hola, mundo.', 'en'))
  assert.ok(!needsSemanticDirection('你好世界', 'en'))
})

test('needsSemanticDirection: 纯汉字和西里尔文本保留语义判断', () => {
  assert.ok(needsSemanticDirection('你好世界', 'zh-CN'))
  assert.ok(needsSemanticDirection('東京', 'ja'))
  assert.ok(needsSemanticDirection('Привет', 'ru'))
  assert.ok(!needsSemanticDirection('안녕하세요', 'ko'))
})

test('pickDirection: 标记需要 AI 做语义方向判断的输入', () => {
  assert.strictEqual(pickDirection('hello', 'fr', 'en').semantic, true)
  assert.strictEqual(pickDirection('こんにちは', 'ja', 'en').semantic, false)
})
