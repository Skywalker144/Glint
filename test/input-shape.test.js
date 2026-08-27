'use strict'

const test = require('node:test')
const assert = require('node:assert/strict')
const { prepareTranslationInput, restoreTranslationInput } = require('../src/main/engines/input-shape')

test('snake_case filename is translated as words and keeps its extension', () => {
  const prepared = prepareTranslationInput('meta_game_payoff_heatmap.png')
  assert.deepEqual(prepared, { text: 'meta game payoff heatmap', suffix: '.png' })
  assert.equal(restoreTranslationInput('元游戏收益热力图', prepared), '元游戏收益热力图.png')
})

test('kebab-case filename and compound extension are supported', () => {
  const prepared = prepareTranslationInput('quarterly-sales-report.tar.gz')
  assert.deepEqual(prepared, { text: 'quarterly sales report', suffix: '.tar.gz' })
  assert.equal(restoreTranslationInput('季度销售报告', prepared), '季度销售报告.tar.gz')
})

test('ordinary text and domain-like names are left unchanged', () => {
  assert.deepEqual(prepareTranslationInput('hello world'), { text: 'hello world', suffix: '' })
  assert.deepEqual(prepareTranslationInput('openai.com'), { text: 'openai.com', suffix: '' })
})
