'use strict'

const { app, BrowserWindow, ipcMain, clipboard, nativeTheme, systemPreferences } = require('electron')
const assert = require('node:assert/strict')
const fs = require('node:fs')
const path = require('node:path')
const root = path.resolve(__dirname, '..')
fs.mkdirSync(path.join(root, '.cache'), { recursive: true })
const dataPath = fs.mkdtempSync(path.join(root, '.cache/selection-test-'))
app.setPath('userData', dataPath)
const { SelectionPopup } = require('../src/main/selection-popup')
const settings = require('../src/main/settings')
const translations = []
const errors = []
let popup
let settingsWin
let platform = 'darwin'
let helperAccessibility = false

ipcMain.handle('settings:get', () => settings.get())
ipcMain.handle('settings:defaults', () => settings.DEFAULTS)
ipcMain.handle('settings:save', (_e, value) => ({ settings: settings.save(value), hotkeyErrors: [] }))
ipcMain.handle('settings:providers', () => require('../src/main/engines/providers').listProviders())
ipcMain.handle('settings:languages', () => require('../src/main/languages').LANGUAGES)
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
  popup = new SelectionPopup({
    translate: text => {
      translations.push(text)
      if (process.argv.includes('--interactive')) {
        fs.writeFileSync(path.join(dataPath, 'translations.json'), JSON.stringify(translations))
        console.log('translated selection:', text)
      }
    },
    isBlocked: () => false,
  })
  popup.setEnabled(true)
  await until(() => popup.nativeStatus)
  const ready = popup.nativeStatus
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
  await popup.window.webContents.executeJavaScript("document.querySelector('#translate-selection').click()")
  await until(() => translations.length === 1)
  assert.deepEqual(translations, ['cached selection'])
  assert.equal(popup.window.isVisible(), false)
  assert.equal(clipboard.readText(), originalClipboard)
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
    webPreferences: { preload: path.join(root, 'src/preload/index.js'), contextIsolation: true, nodeIntegration: false },
  })
  await settingsWin.loadFile(path.join(root, 'src/renderer/settings.html'))
  await until(() => settingsWin.webContents.executeJavaScript("document.querySelector('#provider').options.length > 0 && !document.querySelector('#selection-popup-setting').hidden"))
  assert.equal(await settingsWin.webContents.executeJavaScript("document.querySelector('#selection-popup').checked"), true)
  await until(() => settingsWin.webContents.executeJavaScript("document.querySelector('#perm-selection').textContent === '权限异常'"))
  assert.equal(await settingsWin.webContents.executeJavaScript("document.querySelector('#perm-accessibility').textContent"), '已授权')
  helperAccessibility = true
  await settingsWin.webContents.executeJavaScript("document.querySelector('#refresh-selection').click()")
  await until(() => settingsWin.webContents.executeJavaScript("document.querySelector('#perm-selection').textContent === '可用'"))
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
    app.quit()
  }
}).catch(error => {
  console.error(error)
  app.exit(1)
})

app.on('before-quit', () => popup?.dispose())
