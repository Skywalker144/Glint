'use strict'

const { test } = require('node:test')
const assert = require('node:assert/strict')
const { lookup, renderEntry } = require('../src/main/dictionary')

test('real dictionary provides bilingual definitions and pronunciation without a model', async () => {
  const entry = await lookup('APPLE')
  assert.equal(entry.word, 'apple')
  assert.match(entry.translation, /苹果/)
  assert.ok(entry.phonetic)
  assert.ok(entry.definition)
  assert.match(renderEntry(entry), /ECDICT/)
})

test('dictionary resolves inflections, preserves derivations and looks up phrases', async () => {
  assert.equal((await lookup('ran')).word, 'run')
  assert.equal((await lookup('happiness')).word, 'happiness')
  assert.ok(await lookup('look up'))
  assert.equal(await lookup('this is a complete sentence that should be translated'), null)
  assert.equal(await lookup('zxqvnonexistentword'), null)
  assert.equal(await lookup('../../settings'), null)
})
