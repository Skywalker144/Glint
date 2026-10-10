'use strict'

const { app, BrowserWindow, ipcMain, clipboard, nativeTheme, systemPreferences, screen } = require('electron')
const assert = require('node:assert/strict')
const fs = require('node:fs')
const path = require('node:path')
const root = path.resolve(__dirname, '..')
fs.mkdirSync(path.join(root, '.cache'), { recursive: true })
const dataPath = fs.mkdtempSync(path.join(root, '.cache/selection-test-'))
app.setPath('userData', dataPath)
const { SelectionPopup } = require('../src/main/selection-popup')
const settings = require('../src/main/settings')
require('../src/main/vocabulary').registerVocabularyIPC()
const translations = []
const errors = []
let popup
let settingsWin
let translatorWin
let platform = 'darwin'
let helperAccessibility = false

ipcMain.handle('settings:get', () => settings.get())
ipcMain.handle('settings:defaults', () => settings.DEFAULTS)
ipcMain.handle('settings:save', (_e, value) => {
  const saved = settings.save(value)
  popup?.setEnabled(saved.selectionPopup, saved.selectionPopupOptions)
  return { settings: saved, hotkeyErrors: [] }
})
ipcMain.handle('settings:providers', () => require('../src/main/engines/providers').listProviders())
ipcMain.handle('settings:languages', () => require('../src/main/languages').LANGUAGES)
ipcMain.handle('render-markdown', (_event, text) => require('../src/main/markdown').renderMarkdown(text))
ipcMain.on('translate:stream', (event, payload) => {
  event.sender.send('translate:event', {
    type: 'done', token: payload.token,
    item: { original: payload.text, translated: '译文：' + payload.text, source: 'en', target: 'zh-CN' },
  })
})
ipcMain.on('pin:set', (_event, value) => {
  settings.save({ pinned: !!value })
  translatorWin.webContents.send('pin:state', !!value)
})
ipcMain.handle('settings:permissions', () => ({
  platform, accessibility: true, screen: 'granted',
  selectionPopup: { enabled: settings.get().selectionPopup, running: true, accessibility: helperAccessibility },
}))
ipcMain.handle('changelog:get', () => [])
ipcMain.handle('app:info', () => ({ version: 'test', repo: '' }))
ipcMain.on('settings:resize-height', (_e, height) => settingsWin?.setSize(640, Math.min(height, 800)))

async function until(check) {
  const deadline = Date.now() + 45000
  while (Date.now() < deadline) {
    if (await check()) return
    await new Promise(resolve => setTimeout(resolve, 30))
  }
  throw new Error('Timed out waiting for selection popup')
}

app.whenReady().then(async () => {
  if (process.platform !== 'darwin') {
    console.log('macOS selection popup check skipped on this platform')
    app.quit()
    return
  }
  const originalClipboard = clipboard.readText()
  translatorWin = new BrowserWindow({
    width: 420, height: 360, show: false,
    webPreferences: { preload: path.join(root, 'src/preload/index.js'), contextIsolation: true, nodeIntegration: false },
  })
  await translatorWin.loadFile(path.join(root, 'src/renderer/translator.html'))
  popup = new SelectionPopup({
    translate: text => {
      translations.push(text)
      translatorWin.show()
      translatorWin.webContents.send('translate-text', text)
      if (process.argv.includes('--interactive')) {
        fs.writeFileSync(path.join(dataPath, 'translations.json'), JSON.stringify(translations))
        console.log('translated selection:', text)
      }
    },
    isBlocked: (activating = false) => {
      const focusedWindow = BrowserWindow.getFocusedWindow()
      return !!focusedWindow && !(activating && focusedWindow === translatorWin)
    },
  })
  popup.setEnabled(true)
  await until(() => popup.nativeStatus)
  const ready = popup.nativeStatus
  popup.monitor.stdout.pause()
  popup.window.webContents.setBackgroundThrottling(false)
  assert.equal(popup.window.isFocusable(), false)
  popup.window.webContents.on('console-message', details => {
    if (details.level === 'error') errors.push(details.message)
  })
  popup.state.handle({ type: 'selection', text: 'cached selection', x: 200, y: 200 })
  assert.equal(popup.window.isVisible(), true)
  assert.equal(popup.window.isFocused(), false)
  assert.deepEqual(translations, [])
  for (const theme of ['light', 'dark']) {
    nativeTheme.themeSource = theme
    await popup.window.webContents.executeJavaScript('new Promise(resolve => requestAnimationFrame(() => requestAnimationFrame(resolve)))')
    const image = await popup.window.webContents.capturePage()
    fs.writeFileSync(path.join(dataPath, theme + '.png'), image.toPNG())
  }
  popup.window.webContents.sendInputEvent({ type: 'mouseDown', x: 20, y: 20, button: 'left', clickCount: 1 })
  popup.window.webContents.sendInputEvent({ type: 'mouseUp', x: 20, y: 20, button: 'left', clickCount: 1 })
  await until(() => translations.length === 1)
  assert.deepEqual(translations, ['cached selection'])
  await until(() => translatorWin.webContents.executeJavaScript("document.querySelector('#input').value === 'cached selection'"))
  assert.equal(translatorWin.isVisible(), true)
  assert.equal(popup.window.isVisible(), false)
  assert.equal(clipboard.readText(), originalClipboard)
  await translatorWin.webContents.executeJavaScript("document.querySelector('#pin').click()")
  await until(() => settings.get().pinned)
  const pinnedBounds = translatorWin.getBounds()
  for (const text of ['second selection', 'third selection']) {
    translatorWin.blur()
    await until(() => !translatorWin.isFocused())
    popup.state.handle({ type: 'selection', text, x: 200, y: 200 })
    assert.equal(popup.window.isVisible(), true)
    const cursor = screen.getCursorScreenPoint
    screen.getCursorScreenPoint = () => ({ x: 232, y: 232 })
    try {
      translatorWin.show()
      await until(() => translatorWin.isFocused())
      assert.equal(popup.state.text, text, 'Restoring the pinned translator focus during an icon click must preserve the selection')
      popup.window.webContents.sendInputEvent({ type: 'mouseDown', x: 20, y: 20, button: 'left', clickCount: 1 })
      popup.window.webContents.sendInputEvent({ type: 'mouseUp', x: 20, y: 20, button: 'left', clickCount: 1 })
      await until(() => translatorWin.webContents.executeJavaScript(`document.querySelector('#input').value === ${JSON.stringify(text)} && document.querySelector('#result').textContent.includes(${JSON.stringify(text)})`))
      assert.equal(await translatorWin.webContents.executeJavaScript("document.activeElement === document.querySelector('#input')"), false)
      assert.deepEqual(translatorWin.getBounds(), pinnedBounds)
      assert.equal(settings.get().pinned, true)
      assert.equal(popup.window.isVisible(), false)
    } finally {
      screen.getCursorScreenPoint = cursor
    }
  }
  assert.deepEqual(translations, ['cached selection', 'second selection', 'third selection'])
  translatorWin.hide()
  popup.state.handle({ type: 'selection', text: 'another Glint window', x: 200, y: 200 })
  translatorWin.show()
  await until(() => translatorWin.isFocused() && !popup.window.isVisible())
  assert.equal(popup.state.text, '')
  translatorWin.hide()
  popup.state.handle({ type: 'selection', text: 'dismiss me', x: 200, y: 200 })
  popup.state.handle({ type: 'dismiss' })
  assert.equal(popup.window.isVisible(), false)
  popup.setEnabled(false)
  assert.equal(popup.monitor, null)
  popup.setEnabled(true)
  popup.setEnabled(false)
  popup.setEnabled(true)
  await until(() => popup.nativeStatus)
  assert.equal(popup.window.isVisible(), false)

  settingsWin = new BrowserWindow({
    width: 640, height: 800, show: false,
    webPreferences: { preload: path.join(root, 'src/preload/index.js'), contextIsolation: true, nodeIntegration: false, backgroundThrottling: false },
  })
  await settingsWin.loadFile(path.join(root, 'src/renderer/settings.html'))
  await until(() => settingsWin.webContents.executeJavaScript("document.querySelector('#provider').options.length > 0 && !document.querySelector('#selection-popup-setting').hidden"))
  assert.equal(await settingsWin.webContents.executeJavaScript("document.querySelector('#selection-popup').checked"), true)
  assert.deepEqual(await settingsWin.webContents.executeJavaScript(`({
    position: document.querySelector('#selection-popup-position').value,
    distance: Number(document.querySelector('#selection-popup-distance').value),
    delayMs: Number(document.querySelector('#selection-popup-delay').value),
  })`), settings.DEFAULTS.selectionPopupOptions)
  for (const [selector, value] of [
    ['#selection-popup-position', 'top-left'], ['#selection-popup-distance', '24'], ['#selection-popup-delay', '600'],
  ]) {
    await settingsWin.webContents.executeJavaScript(`
      document.querySelector('${selector}').value = '${value}'
      document.querySelector('${selector}').dispatchEvent(new Event('change'))
    `)
  }
  await until(() => settings.get().selectionPopupOptions.delayMs === 600 && popup.nativeStatus)
  assert.deepEqual(settings.get().selectionPopupOptions, { position: 'top-left', distance: 24, delayMs: 600 })
  assert.equal(popup.monitor.spawnargs.at(-1), '600')
  assert.deepEqual(JSON.parse(fs.readFileSync(path.join(dataPath, 'settings.json'), 'utf8')).selectionPopupOptions,
    settings.get().selectionPopupOptions)
  await settingsWin.reload()
  await until(() => settingsWin.webContents.executeJavaScript("document.querySelector('#selection-popup-delay').value === '600'"))
  assert.equal(await settingsWin.webContents.executeJavaScript("document.querySelector('#selection-popup-position').value"), 'top-left')
  assert.equal(await settingsWin.webContents.executeJavaScript("document.querySelector('#selection-popup-distance').value"), '24')
  for (const theme of ['light', 'dark']) {
    nativeTheme.themeSource = theme
    await settingsWin.webContents.executeJavaScript("document.querySelector('#selection-popup-setting').scrollIntoView(); new Promise(resolve => requestAnimationFrame(() => requestAnimationFrame(resolve)))")
    fs.writeFileSync(path.join(dataPath, 'settings-' + theme + '.png'), (await settingsWin.webContents.capturePage()).toPNG())
  }
  await settingsWin.webContents.executeJavaScript(`{
    const distance = document.querySelector('#selection-popup-distance')
    distance.value = '0'
    distance.dispatchEvent(new Event('input'))
  }`)
  await until(() => settings.get().selectionPopupOptions.distance === 0)
  await settingsWin.webContents.executeJavaScript(`{
    const distance = document.querySelector('#selection-popup-distance')
    distance.value = '101'
    distance.dispatchEvent(new Event('change'))
  }`)
  assert.equal(await settingsWin.webContents.executeJavaScript("document.querySelector('#selection-popup-distance').value"), '0')
  await settingsWin.webContents.executeJavaScript(`{
    const distance = document.querySelector('#selection-popup-distance')
    distance.value = '24'
    distance.dispatchEvent(new Event('input'))
  }`)
  await until(() => settings.get().selectionPopupOptions.distance === 24)
  settingsWin.hide()
  popup.state.handle({ type: 'selection', text: 'configured placement', x: 200, y: 200 })
  assert.deepEqual(popup.window.getBounds(), { x: 136, y: 136, width: 40, height: 40 })
  popup.dismiss()
  await until(() => settingsWin.webContents.executeJavaScript("document.querySelector('#perm-selection').textContent === '权限异常'"))
  assert.equal(await settingsWin.webContents.executeJavaScript("document.querySelector('#perm-accessibility').textContent"), '已授权')
  helperAccessibility = true
  await settingsWin.webContents.executeJavaScript("document.querySelector('#refresh-selection').click()")
  await until(() => settingsWin.webContents.executeJavaScript("document.querySelector('#perm-selection').textContent === '可用'"))
  await settingsWin.webContents.executeJavaScript("document.querySelector('#selection-popup').click()")
  await until(() => settings.get().selectionPopup === false)
  assert.equal(popup.monitor, null)
  assert.equal(await settingsWin.webContents.executeJavaScript("document.querySelector('#selection-popup-distance').disabled && document.querySelector('#selection-popup-delay').disabled && document.querySelector('#selection-popup-position').disabled"), true)
  await settingsWin.webContents.executeJavaScript("document.querySelector('#selection-popup').click()")
  await until(() => settings.get().selectionPopup === true && popup.nativeStatus)
  assert.equal(popup.monitor.spawnargs.at(-1), '600')
  assert.equal(await settingsWin.webContents.executeJavaScript("document.querySelector('#selection-popup-delay').disabled"), false)
  await settingsWin.webContents.executeJavaScript("document.querySelector('#selection-popup').click()")
  await until(() => settings.get().selectionPopup === false)
  assert.deepEqual(settings.get().hotkeys, settings.DEFAULTS.hotkeys)
  assert.equal(settings.get().engine, 'google')
  await settingsWin.webContents.executeJavaScript("document.querySelector('#refresh-selection').click()")
  await until(() => settingsWin.webContents.executeJavaScript("document.querySelector('#perm-selection').textContent === '已关闭'"))
  platform = 'win32'
  await settingsWin.webContents.executeJavaScript("document.querySelector('#refresh-permissions').click()")
  await until(() => settingsWin.webContents.executeJavaScript("getComputedStyle(document.querySelector('#selection-popup-setting')).display === 'none'"))
  assert.deepEqual(errors, [])
  settingsWin.destroy()
  settingsWin = null
  nativeTheme.themeSource = 'system'
  console.log(JSON.stringify({ ok: true, accessibility: ready.accessibility,
    electronAccessibility: systemPreferences.isTrustedAccessibilityClient(false), artifacts: dataPath }))
  if (process.argv.includes('--interactive')) {
    settings.save({ selectionPopup: true })
    popup.setEnabled(true, settings.get().selectionPopupOptions)
    await until(() => popup.nativeStatus)
    translations.length = 0
    popup.monitor.stdout.on('data', data => {
      fs.appendFileSync(path.join(dataPath, 'native-events.jsonl'), data)
      fs.writeFileSync(path.join(dataPath, 'popup-state.json'), JSON.stringify({
        text: popup.state.text, bounds: popup.state.bounds, visible: popup.window.isVisible(),
        focused: popup.window.isFocused(), clipboardUnchanged: clipboard.readText() === originalClipboard,
      }))
      console.log('native:', data.toString().trim())
    })
    console.log('Interactive selection monitor active for five minutes')
    setTimeout(() => app.quit(), 300000)
  } else {
    translatorWin.destroy()
    app.quit()
  }
}).catch(error => {
  console.error(error)
  app.exit(1)
})

app.on('before-quit', () => popup?.dispose())
