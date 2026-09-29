'use strict'

const { app, BrowserWindow, ipcMain, nativeTheme, protocol } = require('electron')
const assert = require('node:assert/strict')
const fs = require('node:fs')
const path = require('node:path')
const http = require('node:http')
const root = path.resolve(__dirname, '..')
fs.mkdirSync(path.join(root, '.cache'), { recursive: true })
const dataPath = fs.mkdtempSync(path.join(root, '.cache/translator-test-'))
app.setPath('userData', dataPath)
const settings = require('../src/main/settings')
const history = require('../src/main/history')
const { translateStream } = require('../src/main/translate')
const { renderMarkdown } = require('../src/main/markdown')
const { LANGUAGES } = require('../src/main/languages')
const requests = []
const payloads = []
let active
let win
let failNext = false
let copiedText = ''
const normalOutput = '**普通译文**\n\n- [链接](https://example.com)\n\n`code`'
const googleRequests = []
const server = http.createServer(async (req, res) => {
  let body = ''
  for await (const chunk of req) body += chunk
  const request = JSON.parse(body)
  requests.push(request)
  if (failNext) {
    failNext = false
    res.writeHead(500, { 'Content-Type': 'application/json' })
    res.end(JSON.stringify({ error: { message: 'Test failure' } }))
    return
  }
  res.writeHead(200, { 'Content-Type': 'text/event-stream' })
  const dict = request.messages[0].content.includes('双语词典')
  res.write('data: ' + JSON.stringify({ choices: [{ delta: { content: dict ? '**词条**\n\n*n.*\n\n- 简明释义' : normalOutput } }] }) + '\n\n')
  const timer = setTimeout(() => res.end('data: [DONE]\n\n'), dict ? 600 : 30)
  res.on('close', () => clearTimeout(timer))
})

ipcMain.handle('settings:languages', () => LANGUAGES)
ipcMain.handle('render-markdown', (_event, text) => renderMarkdown(text))
ipcMain.on('translate:stream', async (event, payload) => {
  payloads.push(payload)
  if (active) active.abort()
  const controller = new AbortController()
  active = controller
  const send = (message) => event.sender.send('translate:event', { token: payload.token, ...message })
  try {
    const item = await translateStream(payload.text, (delta) => send({ type: 'delta', delta }), {
      ...payload, signal: controller.signal, onMeta: (meta) => send({ type: 'meta', ...meta }),
    })
    send({ type: 'done', item })
  } catch (error) {
    if (!controller.signal.aborted) send({ type: 'error', error: error.message })
  }
})
ipcMain.on('translate:stop', () => active?.abort())
ipcMain.on('copy-text', (_event, text) => { copiedText = text })

async function until(expression) {
  const deadline = Date.now() + 5000
  while (Date.now() < deadline) {
    if (await win.webContents.executeJavaScript(expression)) return
    await new Promise((resolve) => setTimeout(resolve, 20))
  }
  throw new Error('Timed out: ' + expression)
}

async function click(selector) {
  await win.webContents.executeJavaScript(`document.querySelector(${JSON.stringify(selector)}).click()`)
}

app.whenReady().then(async () => {
  await new Promise((resolve) => server.listen(0, '127.0.0.1', resolve))
  settings.save({
    engine: 'custom', dictionaryMode: true,
    providers: { custom: { apiKey: 'test', model: 'test', baseURL: `http://127.0.0.1:${server.address().port}` } },
  })
  win = new BrowserWindow({
    width: 420, height: 360, show: false,
    webPreferences: { preload: path.join(root, 'src/preload/index.js'), contextIsolation: true, nodeIntegration: false },
  })
  await win.loadFile(path.join(root, 'src/renderer/translator.html'))
  win.webContents.send('translate-text', '人工智能')
  await until("document.querySelector('#dictionary-mode').getAttribute('aria-pressed') === 'true' && document.querySelector('#result').textContent.includes('词条')")
  const oldToken = payloads.at(-1).token
  await click('#translate')
  await until("document.querySelector('#result').textContent.includes('普通译文') && !document.querySelector('#resultbar').hidden")
  assert.equal(payloads.at(-1).mode, 'translate')
  assert.ok(!requests.at(-1).messages[0].content.includes('双语词典'))
  assert.equal(history.list().length, 1)
  assert.equal(history.list()[0].translated, normalOutput)
  win.webContents.send('translate:event', { token: oldToken, type: 'delta', delta: 'STALE' })
  await until("!document.querySelector('#result').textContent.includes('STALE')")
  await click('#copy')
  await until("document.querySelector('#copy').textContent === '已复制'")
  assert.match(copiedText, /普通译文/)
  assert.match(copiedText, /链接/)
  assert.match(copiedText, /code/)
  assert.ok(!/[*`#]|https:\/\//.test(copiedText))
  assert.equal(await win.webContents.executeJavaScript("document.querySelectorAll('#resultbar button').length"), 2)
  failNext = true
  await click('#translate')
  await until("!document.querySelector('#retry').hidden")
  await click('#retry')
  await until("!document.querySelector('#resultbar').hidden")
  assert.equal(payloads.at(-1).mode, 'translate')
  await click('#dictionary-mode')
  await until("document.querySelector('#dictionary-mode').getAttribute('aria-pressed') === 'true' && !document.querySelector('#resultbar').hidden")
  assert.equal(payloads.at(-1).mode, 'dict')
  assert.ok(requests.at(-1).messages[0].content.includes('双语词典'))
  await win.webContents.executeJavaScript("document.querySelector('#source-lang').value = 'en'; document.querySelector('#source-lang').dispatchEvent(new Event('change'))")
  await until("!document.querySelector('#resultbar').hidden")
  assert.equal(payloads.at(-1).source, 'en')
  await win.webContents.executeJavaScript("document.querySelector('#target-lang').value = 'ja'; document.querySelector('#target-lang').dispatchEvent(new Event('change'))")
  await until("!document.querySelector('#resultbar').hidden && !document.querySelector('#swap-languages').disabled")
  assert.equal(payloads.at(-1).mode, 'dict')
  assert.match(requests.at(-1).messages[0].content, /日语–英文/)
  await click('#translate')
  await until("!document.querySelector('#resultbar').hidden")
  assert.match(requests.at(-1).messages[1].content, /原文语言：英文/)
  assert.match(requests.at(-1).messages[1].content, /目标语言：日语/)
  await click('#swap-languages')
  await until("!document.querySelector('#resultbar').hidden")
  assert.equal(payloads.at(-1).source, 'ja')
  assert.equal(payloads.at(-1).target, 'en')
  assert.equal(payloads.at(-1).text, '人工智能')
  assert.match(requests.at(-1).messages[1].content, /原文语言：日语/)
  assert.match(requests.at(-1).messages[1].content, /目标语言：英文/)
  await win.webContents.executeJavaScript("document.querySelector('#source-lang').value = ''; document.querySelector('#target-lang').value = ''; document.querySelector('#target-lang').dispatchEvent(new Event('change'))")
  await until("!document.querySelector('#resultbar').hidden")
  assert.equal(await win.webContents.executeJavaScript("document.querySelector('#swap-languages').disabled"), true)
  await win.webContents.executeJavaScript("document.querySelector('#input').value = 'apple'; document.querySelector('#input').dispatchEvent(new Event('input')); document.querySelector('#input').dispatchEvent(new KeyboardEvent('keydown', { key: 'Enter', bubbles: true }))")
  await until("document.querySelector('#dictionary-mode').getAttribute('aria-pressed') === 'true' && !document.querySelector('#resultbar').hidden")
  assert.equal(payloads.at(-1).mode, 'auto')
  for (const theme of ['light', 'dark']) {
    nativeTheme.themeSource = theme
    win.setSize(360, 480)
    await win.webContents.executeJavaScript("new Promise(resolve => requestAnimationFrame(() => requestAnimationFrame(resolve)))")
    const fits = await win.webContents.executeJavaScript(`(() => {
      const toolbar = document.querySelector('.toolbar').getBoundingClientRect()
      return [...document.querySelectorAll('.toolbar button, .toolbar select')].every(element => {
        const rect = element.getBoundingClientRect()
        return rect.left >= toolbar.left && rect.right <= toolbar.right + 1 && rect.width >= 20
      })
    })()`)
    assert.ok(fits, 'Toolbar must fit at 360px')
    fs.writeFileSync(path.join(dataPath, theme + '.png'), (await win.webContents.capturePage()).toPNG())
  }
  win.webContents.send('focus-input')
  await until("document.querySelector('#input').value === '' && document.querySelector('#swap-languages').disabled")
  settings.save({ engine: 'google' })
  await protocol.handle('https', (request) => {
    googleRequests.push(new URL(request.url))
    return new Response(JSON.stringify([[['gift', 'Gift']], null, 'de']), { headers: { 'Content-Type': 'application/json' } })
  })
  const googleResult = await translateStream('Gift', () => {}, { source: 'de', target: 'en', mode: 'translate' })
  assert.equal(googleRequests.at(-1).searchParams.get('sl'), 'de')
  assert.equal(googleRequests.at(-1).searchParams.get('tl'), 'en')
  assert.equal(googleResult.source, 'de')
  assert.equal(googleResult.translated, 'gift')
  await translateStream('東京', () => {}, { mode: 'translate' })
  assert.equal(googleRequests.at(-1).searchParams.get('sl'), 'auto')
  console.log('Screenshots: ' + dataPath)
  console.log('PASS: bidirectional modes, explicit source, language swap, pure-text copy, abort/history, retry, auto reset, Google source, 360px light/dark layout')
  app.exit(0)
}).catch((error) => {
  console.error(error)
  app.exit(1)
})
