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
const dictionaryOutput = '**词条** /ˈæbstrækt/\nadj. 抽象的\nn. 摘要；梗概'
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
  res.write('data: ' + JSON.stringify({ choices: [{ delta: { content: dict ? dictionaryOutput + (request.messages[0].content.includes('例句：只给一条') ? '\n\n---\n\n例句 An abstract idea. — 一个抽象的想法。' : '') : normalOutput } }] }) + '\n\n')
  const timer = setTimeout(() => res.end('data: [DONE]\n\n'), dict ? 600 : 30)
  res.on('close', () => clearTimeout(timer))
})

ipcMain.handle('settings:get', () => settings.get())
ipcMain.handle('settings:defaults', () => settings.DEFAULTS)
ipcMain.handle('settings:save', (_event, value) => settings.save(value))
ipcMain.handle('settings:providers', () => require('../src/main/engines/providers').listProviders())
ipcMain.handle('settings:permissions', () => ({}))
ipcMain.handle('app:info', () => ({ version: 'test', repo: '' }))
ipcMain.handle('changelog:get', () => [])
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
  await win.webContents.executeJavaScript(`
    window.inputHeights = [document.querySelector('#input').getBoundingClientRect().height]
    new ResizeObserver(entries => window.inputHeights.push(entries[0].target.getBoundingClientRect().height)).observe(document.querySelector('#input'))
  `)
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
  assert.match(requests.at(-1).messages[0].content, /禁止输出例句/)
  assert.equal(await win.webContents.executeJavaScript("document.querySelectorAll('#result hr').length"), 0)
  settings.save({ dictionaryExtras: { examples: true, synonyms: true, related: true } })
  await click('#dictionary-mode')
  await until("!document.querySelector('#resultbar').hidden && document.querySelector('#result hr') !== null")
  await click('#copy')
  await until("document.querySelector('#copy').textContent === '已复制'")
  assert.ok(!copiedText.includes('---'))
  assert.ok(copiedText.includes('例句'))
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
  await win.webContents.executeJavaScript("document.querySelector('#input').value = 'Long original text\\n'.repeat(30); document.querySelector('#input').dispatchEvent(new Event('input'))")
  await win.webContents.executeJavaScript("new Promise(resolve => setTimeout(resolve, 200))")
  const heights = await win.webContents.executeJavaScript('window.inputHeights')
  assert.ok(heights.every(height => Math.abs(height - heights[0]) < 1), 'Input height changed across translation phases: ' + heights.join(', '))
  assert.equal(await win.webContents.executeJavaScript("document.querySelector('#input').scrollHeight > document.querySelector('#input').clientHeight"), true)
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
  settings.save({ engine: 'custom', dictionaryExtras: { examples: false, synonyms: false, related: false } })
  const { DEFAULT_DICTIONARY_PROMPT, LEGACY_DICTIONARY_PROMPTS } = require('../src/main/engines/prompt')
  assert.equal(settings.migrate({ dictionaryPrompt: LEGACY_DICTIONARY_PROMPTS[0] }).dictionaryPrompt, DEFAULT_DICTIONARY_PROMPT)
  assert.equal(settings.migrate({ dictionaryPrompt: 'My custom dictionary' }).dictionaryPrompt, 'My custom dictionary')
  await win.loadFile(path.join(root, 'src/renderer/settings.html'))
  await until("document.querySelector('#ai-dictionary-prompt').value.includes('n.、adj.')")
  assert.equal(await win.webContents.executeJavaScript("[...document.querySelectorAll('[data-dictionary-extra]')].every(input => !input.checked)"), true)
  for (const key of ['examples', 'synonyms', 'related']) await click('[data-dictionary-extra="' + key + '"]')
  await until("document.querySelector('#save-status').textContent.includes('已自动保存')")
  assert.deepEqual(JSON.parse(fs.readFileSync(path.join(dataPath, 'settings.json'), 'utf8')).dictionaryExtras, { examples: true, synonyms: true, related: true })
  await win.reload()
  await until("[...document.querySelectorAll('[data-dictionary-extra]')].every(input => input.checked)")
  console.log('PASS: dictionary defaults, prompt migration, extras persistence, divider rendering and copy')
  console.log('Screenshots: ' + dataPath)
  console.log('PASS: bidirectional modes, explicit source, language swap, pure-text copy, abort/history, retry, auto reset, Google source, 360px light/dark layout')
  app.exit(0)
}).catch((error) => {
  console.error(error)
  app.exit(1)
})
