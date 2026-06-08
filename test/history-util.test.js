'use strict'

const { test } = require('node:test')
const assert = require('node:assert')
const { normalizeItem, dedupe } = require('../src/main/history-util')

test('normalizeItem: 缺原文或译文时返回 null', () => {
  assert.strictEqual(normalizeItem(null), null)
  assert.strictEqual(normalizeItem({ original: 'a' }), null)
  assert.strictEqual(normalizeItem({ translated: 'b' }), null)
  const ok = normalizeItem({ original: 'a', translated: 'b' })
  assert.ok(ok)
  assert.strictEqual(ok.source, 'auto')
})

test('dedupe: 去掉原文+译文都相同的旧条目', () => {
  const a = { original: 'x', translated: 'y', id: '1' }
  const b = { original: 'x', translated: 'y', id: '2' }
  const list = dedupe([a], b, 100)
  assert.strictEqual(list.length, 1)
  assert.strictEqual(list[0].id, '2') // 新的在前
})

test('dedupe: 同原文不同译文都保留', () => {
  const list = dedupe([{ original: 'x', translated: 'y1' }], { original: 'x', translated: 'y2' }, 100)
  assert.strictEqual(list.length, 2)
})

test('dedupe: 截断到上限', () => {
  const big = []
  for (let i = 0; i < 150; i++) big.push({ original: 'o' + i, translated: 't' + i })
  const capped = dedupe(big, { original: 'new', translated: 'new' }, 100)
  assert.strictEqual(capped.length, 100)
  assert.strictEqual(capped[0].original, 'new')
})
