'use strict'

const { app, BrowserWindow, globalShortcut, dialog, session } = require('electron')
const fs = require('node:fs')
const path = require('node:path')
const assert = require('node:assert/strict')
const http = require('node:http')
const root = path.resolve(__dirname, '..')
const scratch = path.join(root, '.cache', 'dictionary-smoke')
fs.mkdirSync(scratch, { recursive: true })
const profile = fs.mkdtempSync(path.join(scratch, 'profile-'))
app.setPath('userData', profile)
app.setPath('appData', profile)
app.setPath('sessionData', profile)
app.setLoginItemSettings = () => {}
globalShortcut.register = () => true
require('../src/main/ocr').prepare = () => {}
const requests = []
let failModel = false
const server = http.createServer((request, response) => {
  let body = ''
  request.on('data', (chunk) => { body += chunk })
  request.on('end', () => {
    requests.push(JSON.parse(body))
    if (failModel) {
      response.writeHead(503, { 'Content-Type': 'application/json' })
      response.end(JSON.stringify({ error: { message: 'Smoke provider unavailable' } }))
      return
    }
    response.writeHead(200, { 'Content-Type': 'text/event-stream' })
    response.write('data: ' + JSON.stringify({ choices: [{ delta: { content: '测试译文：保持完整原文。' } }] }) + '\n\n')
    response.end('data: [DONE]\n\n')
  })
})
const errors = []
app.on('web-contents-created', (_event, contents) => {
  contents.on('console-message', (_event, level, message) => { if (level >= 3) errors.push(message) })
})

async function until(check, label) {
  const deadline = Date.now() + 15000
  while (Date.now() < deadline) {
    if (await check()) return
    await new Promise((resolve) => setTimeout(resolve, 40))
  }
  throw new Error('Timeout: ' + label)
}

const evaluate = (win, code) => win.webContents.executeJavaScript(code, true)

async function query(win, text) {
  win.webContents.send('translate-text', text)
  await until(() => evaluate(win, '!!completedItem && completedItem.original === ' + JSON.stringify(text)), 'translation ' + text.slice(0, 25))
}

;(async () => {
  await new Promise((resolve) => server.listen(0, '127.0.0.1', resolve))
  const settings = require('../src/main/settings')
  settings.save({ pinned: true, hideTrayIcon: true, hotkeys: { input: '', screenshot: '', selection: '', clipboard: '' }, engine: 'google' })
  require('../src/main/index')
  await app.whenReady()
  const packaged = require(path.join(root, '.cache/glint-source.asar/main/dictionary.js'))
  assert.equal((await packaged.lookup('ran')).word, 'run')
  session.defaultSession.webRequest.onBeforeRequest((details, callback) => {
    callback({ cancel: !details.url.startsWith('file:') && !details.url.startsWith('http://127.0.0.1:') && !details.url.startsWith('devtools:') })
  })
  await until(() => BrowserWindow.getAllWindows().length, 'translator window')
  const translator = BrowserWindow.getAllWindows()[0]
  await until(() => !translator.webContents.isLoading(), 'renderer load')
  translator.show()
  await query(translator, 'ran')
  assert.equal(await evaluate(translator, 'completedItem.word'), 'run')
  assert.equal(await evaluate(translator, 'document.querySelector("#input").hidden'), true)
  assert.equal(await evaluate(translator, 'document.querySelector("#ai-supplement").hidden'), true)
  await evaluate(translator, 'document.querySelector("#save-word").click()')
  await until(() => evaluate(translator, 'document.querySelector("#save-word").textContent.includes("已收藏")'), 'save vocabulary')
  await evaluate(translator, 'document.querySelector("#vocabulary").click()')
  await until(() => BrowserWindow.getAllWindows().length === 2, 'vocabulary window')
  const preferences = BrowserWindow.getAllWindows().find((win) => win !== translator)
  await until(() => !preferences.webContents.isLoading(), 'preferences load')
  await until(() => evaluate(preferences, 'document.querySelectorAll(".vocabulary-entry").length === 1'), 'saved entry')
  assert.equal(await evaluate(preferences, 'document.querySelector("[data-panel=vocabulary]").hidden'), false)
  await evaluate(preferences, 'document.querySelector(".vocabulary-entry details").open = true')
  await until(() => evaluate(preferences, 'document.querySelector(".vocabulary-definition").textContent.includes("跑")'), 'entry definition')
  await evaluate(preferences, 'document.querySelectorAll(".vocabulary-actions button")[1].click()')
  await until(() => evaluate(preferences, 'document.querySelector(".vocabulary-heading").textContent.includes("已掌握")'), 'mastery persisted')
  await evaluate(preferences, 'document.querySelector("#vocabulary-search").value = "no match"; document.querySelector("#vocabulary-search").dispatchEvent(new Event("input"))')
  assert.equal(await evaluate(preferences, 'document.querySelectorAll(".vocabulary-entry").length'), 0)
  await evaluate(preferences, 'document.querySelector("#vocabulary-search").value = ""; document.querySelector("#vocabulary-search").dispatchEvent(new Event("input"))')
  const exportPath = path.join(profile, 'export.json')
  dialog.showSaveDialog = async () => ({ canceled: false, filePath: exportPath })
  await evaluate(preferences, 'document.querySelector("#vocabulary-export").click()')
  await until(() => fs.existsSync(exportPath), 'export')
  assert.equal(JSON.parse(fs.readFileSync(exportPath)).entries[0].mastered, true)
  fs.writeFileSync(path.join(scratch, 'vocabulary.png'), (await preferences.webContents.capturePage()).toPNG())
  settings.save({ engine: 'custom', providers: { custom: { apiKey: 'smoke-only', model: 'smoke', baseURL: 'http://127.0.0.1:' + server.address().port } } })
  await query(translator, 'apple')
  assert.equal(requests.length, 0)
  await evaluate(translator, 'document.querySelector("#ai-supplement").click()')
  await until(() => evaluate(translator, 'completedItem?.attribution === "ECDICT + AI 补充"'), 'AI supplement')
  assert.equal(JSON.parse(requests[0].messages[1].content).word, 'apple')
  assert.match(await evaluate(translator, 'document.querySelector("#result").textContent'), /苹果.*AI 补充/s)
  fs.writeFileSync(path.join(scratch, 'dictionary.png'), (await translator.webContents.capturePage()).toPNG())
  failModel = true
  await evaluate(translator, 'document.querySelector("#ai-supplement").click()')
  await until(() => evaluate(translator, 'document.querySelector("#status").textContent.includes("AI 补充失败")'), 'model failure')
  assert.match(await evaluate(translator, 'completedItem.translated'), /苹果/)
  assert.equal(await evaluate(translator, 'document.querySelector("#save-word").hidden'), false)
  failModel = false
  const longText = 'This is a very long selection with multiple lines.\n'.repeat(20)
  await query(translator, longText.trim())
  assert.ok(requests.at(-1).messages[1].content.includes(longText.trim()))
  const preview = await evaluate(translator, '({height: document.querySelector("#source-preview").offsetHeight, width: document.querySelector("#source-preview").offsetWidth, scroll: document.querySelector("#source-preview").scrollWidth, input: document.querySelector("#input").value})')
  assert.ok(preview.height < 50)
  assert.ok(preview.scroll > preview.width)
  assert.equal(preview.input, longText.trim())
  fs.writeFileSync(path.join(scratch, 'long-text.png'), (await translator.webContents.capturePage()).toPNG())
  await evaluate(translator, 'document.querySelector("#source-preview").click()')
  assert.equal(await evaluate(translator, 'document.querySelector("#input").hidden'), false)
  await evaluate(translator, 'document.querySelector("#lookup-mode").value = "translate"')
  await query(translator, 'apple')
  assert.equal(await evaluate(translator, 'completedItem.mode'), 'translate')
  await evaluate(translator, 'document.querySelector("#lookup-mode").value = "dict"')
  await query(translator, 'look up')
  assert.equal(await evaluate(translator, 'completedItem.mode'), 'dict')
  await query(translator, 'run')
  translator.setContentSize(360, translator.getContentSize()[1])
  await new Promise((resolve) => setTimeout(resolve, 200))
  assert.equal(await evaluate(translator, 'document.body.scrollWidth <= window.innerWidth'), true)
  await evaluate(translator, 'document.querySelector("#source-preview").click(); document.querySelector("#input").value = "long input ".repeat(200); document.querySelector("#input").dispatchEvent(new Event("input"))')
  await new Promise((resolve) => setTimeout(resolve, 250))
  assert.equal(await evaluate(translator, 'document.querySelector("#resultbar").getBoundingClientRect().bottom <= innerHeight'), true)
  fs.writeFileSync(path.join(scratch, 'expanded-narrow.png'), (await translator.webContents.capturePage()).toPNG())
  await evaluate(preferences, 'document.querySelectorAll(".vocabulary-actions button")[2].click()')
  await until(() => evaluate(preferences, 'document.querySelectorAll(".vocabulary-entry").length === 0'), 'delete')
  const { translateStream } = require('../src/main/translate')
  const canceled = new AbortController()
  canceled.abort()
  const beforeCancel = require('../src/main/history').list().length
  await assert.rejects(translateStream('apple', () => assert.fail('aborted stream emitted output'), { signal: canceled.signal }), { name: 'AbortError' })
  assert.equal(require('../src/main/history').list().length, beforeCancel)
  assert.deepEqual(errors, [])
  console.log('PASS: real Electron IPC, bundled dictionary, offline lookup, grounded SSE supplement, failure recovery, single-line full-text preservation, mode switching, vocabulary save/search/mastery/export/delete and narrow layout')
  app.exit(0)
})().catch((error) => { console.error(error); app.exit(1) }).finally(() => server.close())
