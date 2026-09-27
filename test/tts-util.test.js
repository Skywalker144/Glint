'use strict'

const { test } = require('node:test')
const assert = require('node:assert')
const { ttsLang, splitText } = require('../src/main/tts-util')

test('ttsLang: 映射到 Google tl 码', () => {
  assert.strictEqual(ttsLang('zh-CN'), 'zh-CN')
  assert.strictEqual(ttsLang('en'), 'en')
  assert.strictEqual(ttsLang('ja'), 'ja')
  assert.strictEqual(ttsLang('xx'), 'en') // 未知回退 en
})

test('splitText: 短文本单段、原样返回', () => {
  assert.deepStrictEqual(splitText('hello'), ['hello'])
  assert.deepStrictEqual(splitText('查个词'), ['查个词'])
})

test('splitText: 长文本切片，每段不超上限且不丢字', () => {
  const input = ('word '.repeat(60)).trim() // 300+ 字符
  const parts = splitText(input, 190)
  assert.ok(parts.length > 1)
  for (const p of parts) assert.ok(p.length <= 190, '段超长：' + p.length)
  // 在空白处断、两端 trim，去掉空白后内容应完全保留
  assert.strictEqual(parts.join(' ').replace(/\s+/g, ''), input.replace(/\s+/g, ''))
})

test('splitText: 无断点的超长连写也能硬切', () => {
  const parts = splitText('x'.repeat(500), 190)
  assert.ok(parts.length >= 3)
  for (const p of parts) assert.ok(p.length <= 190)
})

test('splitText: 空串返回空数组', () => {
  assert.deepStrictEqual(splitText(''), [])
  assert.deepStrictEqual(splitText('   '), [])
})
