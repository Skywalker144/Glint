'use strict'

const { test } = require('node:test')
const assert = require('node:assert/strict')
const fs = require('node:fs')
const vm = require('node:vm')
const path = require('node:path')

test('shared speech selects a usable language for saved entries with auto source', async () => {
  const calls = []
  const utterances = []
  const window = {
    api: { speak: async (text, code) => { calls.push({ text, code }); return { ok: false } } },
    speechSynthesis: { cancel() {}, speak: (utterance) => utterances.push(utterance) },
  }
  vm.runInNewContext(fs.readFileSync(path.join(__dirname, '../src/renderer/speech.js'), 'utf8'), {
    window, SpeechSynthesisUtterance: class { constructor(text) { this.text = text } },
  })
  await window.GlintSpeech.speak('apple', 'auto')
  await window.GlintSpeech.speak('你好', 'auto')
  assert.equal(calls[0].code, 'en')
  assert.equal(calls[1].code, 'zh-CN')
  assert.equal(utterances[0].lang, 'en-US')
  assert.equal(utterances[1].lang, 'zh-CN')
})
