'use strict'

const { test } = require('node:test')
const assert = require('node:assert/strict')
const fs = require('node:fs')
const path = require('node:path')
const { dictionaryEntry } = require('../src/main/dictionary-entry')
const { VocabularyStore } = require('../src/main/vocabulary-store')

const options = { dict: true, secondaryLanguage: 'en', primaryLanguage: 'zh-CN' }
const entry = (word = 'apple', language = 'en') => dictionaryEntry(`**${word}** /test/\nn. 释义`, { ...options, secondaryLanguage: language })

function fixture(t) {
  fs.mkdirSync(path.join(__dirname, '../.cache'), { recursive: true })
  const dir = fs.mkdtempSync(path.join(__dirname, '../.cache/vocabulary-test-'))
  t.after(() => fs.rmSync(dir, { recursive: true, force: true }))
  const file = path.join(dir, 'vocabulary.json')
  return { file, store: new VocabularyStore(file) }
}

test('dictionary entry uses the LLM headword and preserves lexical case and language', () => {
  assert.equal(entry().headword, 'apple')
  assert.notEqual(entry('Polish').id, entry('polish').id)
  assert.notEqual(entry('gift', 'en').id, entry('gift', 'de').id)
  assert.equal(entry('café').id, entry('cafe\u0301').id)
  assert.equal(entry('take off').headword, 'take off')
  for (const text of ['普通句子译文', '**hello**', '# hello\nn. 你好', '```\n**hello**\nn. 你好\n```']) {
    assert.equal(dictionaryEntry(text, options), null)
  }
  assert.equal(dictionaryEntry('**apple**\nn. 苹果', { ...options, dict: false }), null)
})

test('favorites persist, deduplicate, count only subsequent lookups and reset after removal', (t) => {
  const { store, file } = fixture(t)
  store.recordLookup(entry())
  assert.deepEqual(store.list(), [])
  store.add(entry())
  store.add(entry())
  assert.equal(store.list().length, 1)
  assert.equal(store.list()[0].queryCount, 0)
  store.recordLookup(entry())
  store.recordLookup(entry())
  store.recordLookup(entry('pear'))
  const reloaded = new VocabularyStore(file)
  assert.equal(reloaded.list()[0].queryCount, 2)
  assert.ok(reloaded.list()[0].lastQueriedAt)
  reloaded.remove(entry().id)
  assert.deepEqual(new VocabularyStore(file).list(), [])
  reloaded.add(entry())
  assert.equal(reloaded.list()[0].queryCount, 0)
})

test('failed writes do not change in-memory favorites and damaged files are not overwritten', (t) => {
  const { store, file } = fixture(t)
  store.add(entry())
  fs.mkdirSync(file + '.tmp')
  assert.throws(() => store.recordLookup(entry()))
  assert.equal(store.list()[0].queryCount, 0)
  assert.throws(() => store.remove(entry().id))
  assert.equal(store.list().length, 1)
  fs.writeFileSync(file, '{broken')
  assert.throws(() => new VocabularyStore(file).add(entry('pear')))
  assert.equal(fs.readFileSync(file, 'utf8'), '{broken')
})
