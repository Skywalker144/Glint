'use strict'

const { app, BrowserWindow, ipcMain, nativeTheme } = require('electron')
const assert = require('node:assert/strict')
const fs = require('node:fs')
const path = require('node:path')
const http = require('node:http')
const root = path.resolve(__dirname, '..')
fs.mkdirSync(path.join(root, '.cache'), { recursive: true })
const dataPath = fs.mkdtempSync(path.join(root, '.cache/vocabulary-ui-'))
app.setPath('userData', dataPath)
const settings = require('../src/main/settings')
const { translateStream } = require('../src/main/translate')
const { vocabulary, registerVocabularyIPC } = require('../src/main/vocabulary')
const { VocabularyStore } = require('../src/main/vocabulary-store')
const { renderMarkdown } = require('../src/main/markdown')
require('../src/main/vocabulary-window')
registerVocabularyIPC()
let win
let active
let failNext = false
let partial = false
const errors = []
const server = http.createServer(async (req, res) => {
  let body = ''
  for await (const chunk of req) body += chunk
  const request = JSON.parse(body)
  if (failNext) {
    failNext = false
    res.writeHead(500)
    res.end('failure')
    return
  }
  const word = request.messages[1].content
  const headword = word.startsWith('book') ? 'book' : 'apple'
  const output = word.includes('sentence') ? '这是一个句子。' : `**${headword}** /test/\nn. ${headword === 'apple' ? '苹果' : '书'}\n\n---\n\n例句 A ${headword}. — 示例。`
  res.writeHead(200, { 'Content-Type': 'text/event-stream' })
  res.write('data: ' + JSON.stringify({ choices: [{ delta: { content: output } }] }) + '\n\n')
  const timer = setTimeout(() => res.end('data: [DONE]\n\n'), partial ? 1500 : 120)
  res.on('close', () => clearTimeout(timer))
})

ipcMain.handle('settings:get', () => settings.get())
ipcMain.handle('settings:languages', () => require('../src/main/languages').LANGUAGES)
ipcMain.handle('render-markdown', (_event, text) => renderMarkdown(text))
ipcMain.on('translate:stop', () => active?.abort())
ipcMain.on('translate:stream', async (event, payload) => {
  active?.abort()
  const controller = new AbortController()
  active = controller
  const send = message => event.sender.send('translate:event', { token: payload.token, ...message })
  try {
    const item = await translateStream(payload.text, delta => send({ type: 'delta', delta }), {
      ...payload, signal: controller.signal, onMeta: meta => send({ type: 'meta', ...meta }),
    })
    send({ type: 'done', item })
  } catch (cause) {
    if (!controller.signal.aborted) send({ type: 'error', error: cause.message })
  }
})

async function until(expression, target = win) {
  const deadline = Date.now() + 6000
  while (Date.now() < deadline) {
    if (await target.webContents.executeJavaScript(expression)) return
    await new Promise(resolve => setTimeout(resolve, 20))
  }
  throw new Error('Timed out: ' + expression)
}

async function click(selector, target = win) {
  await target.webContents.executeJavaScript(`document.querySelector(${JSON.stringify(selector)}).click()`)
}

async function lookup(text) {
  win.webContents.send('translate-text', text)
  await until(`document.querySelector('#input').value === ${JSON.stringify(text)} && !document.querySelector('#resultbar').hidden && document.querySelector('#stop').hidden`)
}

app.on('web-contents-created', (_event, contents) => {
  contents.on('console-message', (_event, level, message) => { if (level === 3) errors.push(message) })
})

app.whenReady().then(async () => {
  await new Promise(resolve => server.listen(0, '127.0.0.1', resolve))
  settings.save({ engine: 'custom', dictionaryMode: true, providers: { custom: {
    apiKey: 'test', model: 'test', baseURL: `http://127.0.0.1:${server.address().port}`,
  } } })
  win = new BrowserWindow({ width: 420, height: 380, show: false,
    webPreferences: { preload: path.join(root, 'src/preload/index.js'), contextIsolation: true, nodeIntegration: false },
  })
  await win.loadFile(path.join(root, 'src/renderer/translator.html'))
  await lookup('apples')
  await until("!document.querySelector('#favorite').disabled")
  await click('#favorite')
  await until("document.querySelector('#favorite').getAttribute('aria-pressed') === 'true'")
  assert.equal(vocabulary.list()[0].headword, 'apple')
  assert.equal(vocabulary.list()[0].queryCount, 0)
  await lookup('apple')
  await until("document.querySelector('#favorite').getAttribute('aria-pressed') === 'true'")
  await lookup('apples')
  assert.equal(vocabulary.list().length, 1)
  assert.equal(vocabulary.list()[0].queryCount, 2)
  await click('#favorite')
  await until("document.querySelector('#favorite').getAttribute('aria-pressed') === 'false'")
  assert.equal(vocabulary.list().length, 0)
  await click('#favorite')
  await until("document.querySelector('#favorite').getAttribute('aria-pressed') === 'true'")
  assert.equal(vocabulary.list()[0].queryCount, 0)
  await lookup('apple')
  await lookup('apples')
  fs.mkdirSync(path.join(dataPath, 'vocabulary.json.tmp'))
  await lookup('apple')
  assert.equal(vocabulary.list()[0].queryCount, 2)
  assert.ok(await win.webContents.executeJavaScript("document.querySelector('#status').textContent.includes('计数保存失败')"))
  fs.rmdirSync(path.join(dataPath, 'vocabulary.json.tmp'))
  failNext = true
  await click('#dictionary-mode')
  await until("!document.querySelector('#retry').hidden")
  assert.equal(vocabulary.list()[0].queryCount, 2)
  assert.equal(await win.webContents.executeJavaScript("document.querySelector('#favorite').hidden"), true)
  partial = true
  await click('#retry')
  await until("document.querySelector('#result').textContent.includes('apple') && !document.querySelector('#stop').hidden")
  await click('#stop')
  assert.equal(vocabulary.list()[0].queryCount, 2)
  assert.equal(await win.webContents.executeJavaScript("document.querySelector('#favorite').hidden"), true)
  partial = false
  await lookup('this is a sentence')
  assert.equal(await win.webContents.executeJavaScript("document.querySelector('#favorite').hidden"), true)
  await lookup('books')
  await click('#favorite')
  await until("document.querySelector('#favorite').getAttribute('aria-pressed') === 'true'")
  assert.equal(vocabulary.list().length, 2)
  await click('#vocabulary')
  let book
  const deadline = Date.now() + 6000
  while (!book && Date.now() < deadline) {
    book = BrowserWindow.getAllWindows().find(candidate => candidate !== win)
    if (!book) await new Promise(resolve => setTimeout(resolve, 20))
  }
  assert.ok(book)
  if (book.webContents.isLoading()) await new Promise(resolve => book.webContents.once('did-finish-load', resolve))
  await until("document.querySelectorAll('.word').length === 2 && document.querySelector('.definition').textContent.includes('书')", book)
  assert.equal(await book.webContents.executeJavaScript("document.querySelector('.word strong').textContent"), 'book')
  await book.webContents.executeJavaScript("document.querySelector('#sort').value = 'queries'; document.querySelector('#sort').dispatchEvent(new Event('change'))")
  assert.equal(await book.webContents.executeJavaScript("document.querySelector('.word strong').textContent"), 'apple')
  await click('.word', book)
  await until("document.querySelector('.definition').textContent.includes('苹果')", book)
  for (const theme of ['light', 'dark']) {
    nativeTheme.themeSource = theme
    await book.webContents.executeJavaScript('new Promise(resolve => requestAnimationFrame(() => requestAnimationFrame(resolve)))')
    fs.writeFileSync(path.join(dataPath, `vocabulary-${theme}.png`), (await book.webContents.capturePage()).toPNG())
    win.setSize(360, 400)
    await win.webContents.executeJavaScript('new Promise(resolve => requestAnimationFrame(() => requestAnimationFrame(resolve)))')
    const metrics = await win.webContents.executeJavaScript(`(() => {
      const star = document.querySelector('#favorite'); const copy = document.querySelector('#copy')
      return { fill: getComputedStyle(star.querySelector('svg')).fill, color: getComputedStyle(star).color, left: star.getBoundingClientRect().left, right: star.getBoundingClientRect().right, copy: copy.getBoundingClientRect().left }
    })()`)
    assert.equal(metrics.fill, metrics.color)
    assert.ok(metrics.left > 0 && metrics.right <= metrics.copy)
    fs.writeFileSync(path.join(dataPath, `translator-${theme}.png`), (await win.webContents.capturePage()).toPNG())
  }
  book.setSize(480, 360)
  await book.webContents.executeJavaScript('new Promise(resolve => requestAnimationFrame(() => requestAnimationFrame(resolve)))')
  assert.ok(await book.webContents.executeJavaScript("document.querySelector('.controls').scrollWidth <= document.querySelector('.controls').clientWidth && document.querySelector('#detail').scrollWidth <= document.querySelector('#detail').clientWidth"))
  await lookup('apple')
  await until("document.querySelector('.word small').textContent.includes('3 次')", book)
  await click('#remove', book)
  await until("document.querySelector('#favorite').getAttribute('aria-pressed') === 'false'")
  assert.equal(vocabulary.list().length, 1)
  await book.webContents.executeJavaScript("document.querySelector('#search').value = '书'; document.querySelector('#search').dispatchEvent(new Event('input'))")
  assert.equal(await book.webContents.executeJavaScript("document.querySelectorAll('.word').length"), 1)
  await book.webContents.executeJavaScript("document.querySelector('#search').value = 'missing'; document.querySelector('#search').dispatchEvent(new Event('input'))")
  assert.equal(await book.webContents.executeJavaScript("document.querySelector('.empty').textContent"), '没有匹配的词条')
  await book.webContents.executeJavaScript("document.querySelector('#search').value = ''; document.querySelector('#search').dispatchEvent(new Event('input'))")
  assert.equal(new VocabularyStore(path.join(dataPath, 'vocabulary.json')).list()[0].headword, 'book')
  book.close()
  await click('#vocabulary')
  const reopened = BrowserWindow.getAllWindows().find(candidate => candidate !== win)
  assert.ok(reopened && reopened !== book)
  if (reopened.webContents.isLoading()) await new Promise(resolve => reopened.webContents.once('did-finish-load', resolve))
  await until("document.querySelectorAll('.word').length === 1", reopened)
  await click('#remove', reopened)
  await until("document.querySelector('.empty').textContent.includes('收入生词本')", reopened)
  assert.deepEqual(errors, [])
  console.log('PASS: canonical forms, durable counts, toggle, failure/abort exclusion, window entry/reopen, cross-window sync, sorting/search, offline details, light/dark and minimum-width layout')
  console.log('Screenshots: ' + dataPath)
  app.exit(0)
}).catch(error => { console.error(error); app.exit(1) })
