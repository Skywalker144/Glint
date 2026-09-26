'use strict'

const { test } = require('node:test')
const assert = require('node:assert/strict')
const fs = require('node:fs')
const path = require('node:path')
const { Vocabulary } = require('../src/main/vocabulary')

function fixture(t) {
  fs.mkdirSync(path.join(__dirname, '../.cache'), { recursive: true })
  const directory = fs.mkdtempSync(path.join(__dirname, '../.cache/vocabulary-test-'))
  t.after(() => fs.rmSync(directory, { recursive: true, force: true }))
  return path.join(directory, 'vocabulary.json')
}

const item = { word: 'run', original: 'ran', translated: '**run**\n跑', source: 'en', target: 'zh-CN', mode: 'dict', attribution: 'ECDICT' }

test('saved entries survive restart, deduplicate by language and headword, preserve mastery', (t) => {
  const file = fixture(t)
  const store = new Vocabulary(file)
  const first = store.add(item)
  store.update(first.id, true)
  store.add({ ...item, original: 'RUN', word: 'RUN' })
  const reopened = new Vocabulary(file)
  assert.equal(reopened.list().length, 1)
  assert.equal(reopened.list()[0].mastered, true)
  assert.equal(reopened.list()[0].createdAt, first.createdAt)
  reopened.remove(first.id)
  assert.deepEqual(new Vocabulary(file).list(), [])
})

test('vocabulary is not capped like history and exports a portable JSON backup', (t) => {
  const store = new Vocabulary(fixture(t))
  for (let i = 0; i < 105; i++) store.add({ ...item, word: 'word' + i })
  assert.equal(store.list().length, 105)
  assert.equal(JSON.parse(store.export()).entries.length, 105)
  assert.throws(() => store.add({ ...item, translated: '' }))
  assert.throws(() => store.add({ ...item, mode: 'translate' }))
})

test('corrupt files and failed writes report errors and preserve stored data', (t) => {
  const file = fixture(t)
  fs.writeFileSync(file, 'broken')
  assert.throws(() => new Vocabulary(file).add(item))
  assert.equal(fs.readFileSync(file, 'utf8'), 'broken')
  fs.unlinkSync(file)
  const store = new Vocabulary(file)
  store.add(item)
  fs.mkdirSync(file + '.tmp')
  assert.throws(() => store.remove(store.list()[0].id))
  assert.equal(store.list().length, 1)
})
