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
  assert.ok(!isWordLookup('hello world'))
  assert.ok(!isWordLookup('这是一个句子。'))
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
