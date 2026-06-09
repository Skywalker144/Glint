'use strict'

const { test } = require('node:test')
const assert = require('node:assert')
const { pickDirection, isWordLookup, isProbablyLanguage } = require('../src/main/languages')

test('pickDirection: 中文输入 → 副语言（之前线上反过的方向）', () => {
  const d = pickDirection('迭代', 'zh-CN', 'en')
  assert.strictEqual(d.source, 'zh-CN')
  assert.strictEqual(d.target, 'en')
})

test('pickDirection: 英文输入 → 主语言', () => {
  const d = pickDirection('iterate', 'zh-CN', 'en')
  assert.strictEqual(d.target, 'zh-CN')
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

test('isProbablyLanguage: 文字系统判断', () => {
  assert.ok(isProbablyLanguage('hello', 'en'))
  assert.ok(!isProbablyLanguage('你好', 'en'))
  assert.ok(isProbablyLanguage('你好', 'zh-CN'))
  assert.ok(!isProbablyLanguage('こんにちは', 'zh-CN'))
  assert.ok(isProbablyLanguage('こんにちは', 'ja'))
  assert.ok(isProbablyLanguage('Привет', 'ru'))
})
