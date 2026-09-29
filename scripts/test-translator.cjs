'use strict'

const { app, BrowserWindow, ipcMain } = require('electron')
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
  res.write('data: ' + JSON.stringify({ choices: [{ delta: { content: dict ? '**词条**' : '普通译文' } }] }) + '\n\n')
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
  await until("!document.querySelector('#dictionary-mode').hidden && document.querySelector('#result').textContent.includes('词条')")
  fs.writeFileSync(path.join(dataPath, 'dictionary.png'), (await win.webContents.capturePage()).toPNG())
  await click('#dictionary-mode')
  await until("document.querySelector('#result').textContent.includes('普通译文') && !document.querySelector('#resultbar').hidden")
  assert.equal(payloads.at(-1).mode, 'translate')
  assert.ok(!requests.at(-1).messages[0].content.includes('双语词典'))
  assert.equal(history.list().length, 1)
  assert.equal(history.list()[0].translated, '普通译文')
  await until("document.querySelector('#dictionary-mode').hidden && !document.querySelector('.arrow').hidden")
  failNext = true
  await click('#translate')
  await until("!document.querySelector('#retry').hidden")
  await click('#retry')
  await until("!document.querySelector('#resultbar').hidden")
  assert.equal(payloads.at(-1).mode, 'translate')
  await win.webContents.executeJavaScript("document.querySelector('#input').value = 'apple'; document.querySelector('#input').dispatchEvent(new Event('input')); document.querySelector('#translate').click()")
  await until("!document.querySelector('#dictionary-mode').hidden && !document.querySelector('#resultbar').hidden")
  assert.equal(payloads.at(-1).mode, 'auto')
  await click('#dictionary-mode')
  await until("!document.querySelector('#resultbar').hidden")
  assert.equal(payloads.at(-1).mode, 'translate')
  win.webContents.send('translate-text', 'apple')
  await until("!document.querySelector('#dictionary-mode').hidden")
  assert.equal(payloads.at(-1).mode, 'auto')
  await win.webContents.executeJavaScript("document.querySelector('#target-lang').value = 'ja'; document.querySelector('#target-lang').dispatchEvent(new Event('change'))")
  await until("!document.querySelector('#resultbar').hidden && document.querySelector('#dictionary-mode').hidden")
  assert.equal(payloads.at(-1).target, 'ja')
  win.webContents.send('focus-input')
  await until("document.querySelector('#input').value === '' && document.querySelector('#dictionary-mode').hidden")
  console.log('Screenshot: ' + path.join(dataPath, 'dictionary.png'))
  console.log('PASS: streaming/completed switch, prompts, abort/history, retry, edited/new input, target, reset')
  app.exit(0)
}).catch((error) => {
  console.error(error)
  app.exit(1)
})
