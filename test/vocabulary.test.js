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

test('version 1 notebooks migrate once with an exact backup and retain favorites', (t) => {
  const { file, store } = fixture(t)
  const createdAt = '2026-09-01T00:00:00.000Z'
  const translated = '**run** /rʌn/\n\n**中文释义**\n跑'
  const original = JSON.stringify({ version: 1, entries: [{
    id: 'old-id', word: 'ran', original: 'ran', source: 'en', target: 'zh-CN',
    translated, createdAt, updatedAt: createdAt, mastered: false, attribution: 'ECDICT',
  }] }, null, 2)
  fs.writeFileSync(file, original)
  const [saved] = store.list()
  assert.equal(saved.headword, 'run')
  assert.equal(saved.id, entry('run').id)
  assert.equal(saved.translated, translated)
  assert.equal(saved.createdAt, createdAt)
  assert.equal(saved.queryCount, 0)
  assert.equal(fs.readFileSync(file + '.v1.bak', 'utf8'), original)
  assert.ok(Array.isArray(JSON.parse(fs.readFileSync(file, 'utf8'))))
  store.recordLookup(entry('run'))
  assert.equal(new VocabularyStore(file).list()[0].queryCount, 1)
  assert.equal(fs.readFileSync(file + '.v1.bak', 'utf8'), original)
})

test('empty version 1 notebooks migrate and accept new favorites', (t) => {
  const { file, store } = fixture(t)
  fs.writeFileSync(file, JSON.stringify({ version: 1, entries: [] }))
  assert.deepEqual(store.list(), [])
  store.add(entry())
  assert.equal(new VocabularyStore(file).list()[0].headword, 'apple')
})

test('invalid legacy data and failed migration writes preserve the original file', (t) => {
  const { file } = fixture(t)
  for (const data of [{ version: 2, entries: [] }, { version: 1, entries: [null] }]) {
    const raw = JSON.stringify(data)
    fs.writeFileSync(file, raw)
    assert.throws(() => new VocabularyStore(file).list())
    assert.equal(fs.readFileSync(file, 'utf8'), raw)
  }
  const raw = JSON.stringify({ version: 1, entries: [] })
  fs.writeFileSync(file, raw)
  fs.mkdirSync(file + '.tmp')
  const store = new VocabularyStore(file)
  assert.throws(() => store.list())
  assert.equal(fs.readFileSync(file, 'utf8'), raw)
  fs.rmdirSync(file + '.tmp')
  assert.deepEqual(store.list(), [])
})

test('migration merges canonical duplicates and does not overwrite an existing backup', (t) => {
  const { file, store } = fixture(t)
  const saved = {
    id: 'old-id', word: 'apples', source: 'en', target: 'zh-CN',
    translated: '**apple**\nn. 苹果', createdAt: '2026-09-02T00:00:00.000Z',
  }
  const raw = JSON.stringify({ version: 1, entries: [saved, { ...saved, id: 'other-id', word: 'apple', createdAt: '2026-09-01T00:00:00.000Z' }] })
  fs.writeFileSync(file, raw)
  fs.writeFileSync(file + '.v1.bak', 'Existing backup')
  assert.throws(() => store.list())
  assert.equal(fs.readFileSync(file + '.v1.bak', 'utf8'), 'Existing backup')
  assert.equal(fs.readFileSync(file, 'utf8'), raw)
  fs.unlinkSync(file + '.v1.bak')
  assert.equal(store.list().length, 1)
  assert.equal(store.list()[0].createdAt, '2026-09-01T00:00:00.000Z')
})
