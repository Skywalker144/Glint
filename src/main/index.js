'use strict'

const path = require('path')
const {
  app,
  BrowserWindow,
  globalShortcut,
  ipcMain,
  Tray,
  Menu,
  nativeImage,
  screen,
  desktopCapturer,
  systemPreferences,
  clipboard,
  shell,
} = require('electron')

const { translate } = require('./translate')
const { recognize, prepare: prepareOCR } = require('./ocr')
const { getSelectedText } = require('./platform')
const settings = require('./settings')
const { translateWith, listModels } = require('./engines')
const { listProviders } = require('./engines/providers')

const PRELOAD = path.join(__dirname, '..', 'preload', 'index.js')
const RENDERER = path.join(__dirname, '..', 'renderer')

const WIN_WIDTH = 420 // 主窗口固定宽度
const WIN_MAX_HEIGHT = 600 // 主窗口高度自适应上限
const SETTINGS_W = 540
const SETTINGS_H = 560
const REPO_URL = 'https://github.com/Skywalker144/Glint'

let translatorWin = null
let captureWin = null
let settingsWin = null
let tray = null
let isQuitting = false
let captureState = null // { image, scaleFactor }

/* ------------------------------------------------------------------ */
/* 主翻译窗口                                                          */
/* ------------------------------------------------------------------ */

function createTranslatorWindow() {
  translatorWin = new BrowserWindow({
    width: WIN_WIDTH,
    height: 182, // 初始紧凑高度（仅输入框）；之后由渲染层按内容自动调整
    show: false,
    frame: false,
    resizable: false, // 高度自动贴合内容
    transparent: true, // 透明窗口 + CSS 圆角卡片，得到可控半径的 G2 圆角和原生阴影
    hasShadow: true,
    roundedCorners: false,
    minimizable: false,
    maximizable: false,
    fullscreenable: false,
    skipTaskbar: true,
    alwaysOnTop: true,
    backgroundColor: '#00000000',
    webPreferences: { preload: PRELOAD, contextIsolation: true, nodeIntegration: false },
  })

  translatorWin.setVisibleOnAllWorkspaces(true, { visibleOnFullScreen: true })
  translatorWin.loadFile(path.join(RENDERER, 'translator.html'))

  translatorWin.on('close', (e) => {
    if (!isQuitting) {
      e.preventDefault()
      translatorWin.hide()
    }
  })
}

function positionNearCursor(win) {
  const cursor = screen.getCursorScreenPoint()
  const area = screen.getDisplayNearestPoint(cursor).workArea
  const [w] = win.getSize()
  const x = Math.round(area.x + (area.width - w) / 2)
  const y = Math.round(area.y + area.height * 0.18)
  win.setPosition(x, y)
}

function showTranslator() {
  if (!translatorWin || translatorWin.isDestroyed()) createTranslatorWindow()
  positionNearCursor(translatorWin)
  translatorWin.show()
  translatorWin.focus()
  if (process.platform === 'darwin') app.focus({ steal: true })
}

function sendToTranslator(channel, payload) {
  if (translatorWin && !translatorWin.isDestroyed()) {
    translatorWin.webContents.send(channel, payload)
  }
}

/* ------------------------------------------------------------------ */
/* 功能 1：输入翻译                                                    */
/* ------------------------------------------------------------------ */

function onInputTranslate() {
  showTranslator()
  sendToTranslator('focus-input')
}

/* ------------------------------------------------------------------ */
/* 功能 2：划词翻译                                                    */
/* ------------------------------------------------------------------ */

async function onSelectionTranslate() {
  if (
    process.platform === 'darwin' &&
    !systemPreferences.isTrustedAccessibilityClient(false)
  ) {
    systemPreferences.isTrustedAccessibilityClient(true)
    showTranslator()
    sendToTranslator(
      'show-message',
      '划词翻译需要「辅助功能」权限。\n请在 系统设置 → 隐私与安全性 → 辅助功能 中勾选本应用（Electron），然后重试。'
    )
    return
  }

  const text = await getSelectedText()
  if (!text) {
    showTranslator()
    sendToTranslator('show-message', '没有检测到选中的文字。先用鼠标选中文字，再按划词快捷键。')
    return
  }
  showTranslator()
  sendToTranslator('translate-text', text)
}

/* ------------------------------------------------------------------ */
/* 功能 3：截图翻译                                                    */
/* ------------------------------------------------------------------ */

async function onScreenshotTranslate() {
  if (
    process.platform === 'darwin' &&
    ['denied', 'restricted'].includes(systemPreferences.getMediaAccessStatus('screen'))
  ) {
    showTranslator()
    sendToTranslator(
      'show-message',
      '截图翻译需要「屏幕录制」权限。\n请在 系统设置 → 隐私与安全性 → 屏幕录制 中勾选本应用（Electron），然后重启 App。'
    )
    shell.openExternal('x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture')
    return
  }
  await startCapture()
}

async function startCapture() {
  const cursor = screen.getCursorScreenPoint()
  const display = screen.getDisplayNearestPoint(cursor)
  const sf = display.scaleFactor

  const sources = await desktopCapturer.getSources({
    types: ['screen'],
    thumbnailSize: {
      width: Math.round(display.size.width * sf),
      height: Math.round(display.size.height * sf),
    },
  })

  const source =
    sources.find((s) => String(s.display_id) === String(display.id)) || sources[0]
  const image = source && source.thumbnail

  if (!image || image.isEmpty()) {
    showTranslator()
    sendToTranslator(
      'show-message',
      '截屏失败，可能未授予「屏幕录制」权限。\n请在 系统设置 → 隐私与安全性 → 屏幕录制 中允许后重启 App。'
    )
    shell.openExternal('x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture')
    return
  }

  captureState = { image, scaleFactor: sf }
  openCaptureOverlay(display, image.toDataURL())
}

function openCaptureOverlay(display, dataURL) {
  if (captureWin && !captureWin.isDestroyed()) captureWin.close()

  captureWin = new BrowserWindow({
    x: display.bounds.x,
    y: display.bounds.y,
    width: display.bounds.width,
    height: display.bounds.height,
    frame: false,
    transparent: true,
    hasShadow: false,
    resizable: false,
    movable: false,
    skipTaskbar: true,
    enableLargerThanScreen: true,
    fullscreenable: false,
    webPreferences: { preload: PRELOAD, contextIsolation: true, nodeIntegration: false },
  })

  captureWin.setAlwaysOnTop(true, 'screen-saver')
  captureWin.setVisibleOnAllWorkspaces(true, { visibleOnFullScreen: true })
  captureWin.loadFile(path.join(RENDERER, 'capture.html'))
  captureWin.webContents.once('did-finish-load', () => {
    captureWin.webContents.send('capture:init', {
      dataURL,
      width: display.bounds.width,
      height: display.bounds.height,
    })
  })
  captureWin.on('closed', () => {
    captureWin = null
  })
  captureWin.show()
  captureWin.focus()
  if (process.platform === 'darwin') app.focus({ steal: true })
}

/* ------------------------------------------------------------------ */
/* 设置窗口                                                            */
/* ------------------------------------------------------------------ */

function createSettingsWindow() {
  settingsWin = new BrowserWindow({
    width: SETTINGS_W,
    height: SETTINGS_H,
    show: false,
    frame: false,
    transparent: true,
    hasShadow: true,
    roundedCorners: false,
    resizable: false,
    minimizable: false,
    maximizable: false,
    fullscreenable: false,
    skipTaskbar: true,
    backgroundColor: '#00000000',
    webPreferences: { preload: PRELOAD, contextIsolation: true, nodeIntegration: false },
  })

  settingsWin.loadFile(path.join(RENDERER, 'settings.html'))

  settingsWin.on('close', (e) => {
    if (!isQuitting) {
      e.preventDefault()
      settingsWin.hide()
    }
  })

  // 配置期间禁用全局快捷键，避免录制时被它们拦截；离开设置窗口后恢复。
  settingsWin.on('focus', () => globalShortcut.unregisterAll())
  settingsWin.on('blur', () => registerHotkeys())
  settingsWin.on('hide', () => registerHotkeys())
}

function openSettings() {
  if (!settingsWin || settingsWin.isDestroyed()) createSettingsWindow()
  const area = screen.getDisplayNearestPoint(screen.getCursorScreenPoint()).workArea
  settingsWin.setPosition(
    Math.round(area.x + (area.width - SETTINGS_W) / 2),
    Math.round(area.y + (area.height - SETTINGS_H) / 2)
  )
  settingsWin.show()
  settingsWin.focus()
  if (process.platform === 'darwin') app.focus({ steal: true })
  settingsWin.webContents.send('settings:data', settings.get())
}

/* ------------------------------------------------------------------ */
/* IPC                                                                 */
/* ------------------------------------------------------------------ */

ipcMain.handle('translate', async (_e, text) => translate(text))

ipcMain.on('hide-window', () => {
  if (translatorWin && !translatorWin.isDestroyed()) translatorWin.hide()
})

ipcMain.on('copy-text', (_e, text) => {
  clipboard.writeText(text || '')
})

// 渲染层上报内容高度 -> 调整窗口高度，使其紧贴内容（没结果时收起底部空白）。
ipcMain.on('resize-height', (_e, h) => {
  if (!translatorWin || translatorWin.isDestroyed()) return
  const height = Math.max(120, Math.min(WIN_MAX_HEIGHT, Math.round(h)))
  const [w] = translatorWin.getContentSize()
  translatorWin.setContentSize(w, height)
})

ipcMain.on('capture:cancel', () => {
  if (captureWin && !captureWin.isDestroyed()) captureWin.close()
})

ipcMain.on('capture:selected', async (_e, rect) => {
  const state = captureState
  if (captureWin && !captureWin.isDestroyed()) captureWin.close()
  captureState = null

  if (!state || !rect || rect.width < 3 || rect.height < 3) return

  const sf = state.scaleFactor
  const cropped = state.image.crop({
    x: Math.round(rect.x * sf),
    y: Math.round(rect.y * sf),
    width: Math.round(rect.width * sf),
    height: Math.round(rect.height * sf),
  })

  showTranslator()
  sendToTranslator('show-message', '正在识别文字…（首次使用会下载识别引擎，请稍候）')

  try {
    const text = await recognize(cropped.toPNG())
    if (!text) {
      sendToTranslator('show-message', '没有识别到文字，换个区域再试试。')
      return
    }
    sendToTranslator('translate-text', text)
  } catch (err) {
    sendToTranslator('show-message', 'OCR 失败：' + err.message)
  }
})

// 设置相关
ipcMain.handle('settings:get', () => settings.get())
ipcMain.handle('settings:providers', () => listProviders())
ipcMain.handle('app:info', () => ({ version: app.getVersion(), repo: REPO_URL }))

ipcMain.on('open-external', (_e, url) => {
  if (typeof url === 'string' && /^https?:\/\//.test(url)) shell.openExternal(url)
})

ipcMain.handle('settings:save', (_e, partial) => {
  const s = settings.save(partial)
  // 设置窗口此时聚焦、全局快捷键已禁用，这里只做注册校验（之后关窗会真正注册）。
  const hotkeyErrors = validateHotkeys(s.hotkeys)
  rebuildTray()
  return { settings: s, hotkeyErrors }
})

ipcMain.handle('settings:test', async (_e, cfg) => {
  try {
    const { translated } = await translateWith(
      cfg.engine,
      { apiKey: cfg.apiKey, model: cfg.model, baseURL: cfg.baseURL },
      'Hello, world. This is a test.',
      'zh-CN'
    )
    return { ok: true, text: translated }
  } catch (e) {
    return { ok: false, error: e.message }
  }
})

ipcMain.handle('settings:fetch-models', async (_e, cfg) => {
  try {
    const models = await listModels(cfg.engine, { apiKey: cfg.apiKey, baseURL: cfg.baseURL })
    return { ok: true, models }
  } catch (e) {
    return { ok: false, error: e.message }
  }
})

ipcMain.on('settings:close', () => {
  if (settingsWin && !settingsWin.isDestroyed()) settingsWin.hide()
})

/* ------------------------------------------------------------------ */
/* 托盘 & 快捷键                                                       */
/* ------------------------------------------------------------------ */

const ACCEL_SYM = {
  Command: '⌘', Control: '⌃', Alt: '⌥', Shift: '⇧', CommandOrControl: '⌘',
  Return: '⏎', Space: '␣',
}
function accelSymbol(accel) {
  if (!accel) return ''
  return accel.split('+').map((p) => ACCEL_SYM[p] || p).join('')
}

function buildTrayMenu() {
  const hk = settings.get().hotkeys
  return Menu.buildFromTemplate([
    { label: '输入翻译   ' + accelSymbol(hk.input), click: onInputTranslate },
    { label: '截图翻译   ' + accelSymbol(hk.screenshot), click: onScreenshotTranslate },
    { label: '划词翻译   ' + accelSymbol(hk.selection), click: onSelectionTranslate },
    { type: 'separator' },
    { label: '设置…', click: openSettings },
    { type: 'separator' },
    {
      label: '退出',
      click: () => {
        isQuitting = true
        app.quit()
      },
    },
  ])
}

function rebuildTray() {
  if (tray) tray.setContextMenu(buildTrayMenu())
}

function createTray() {
  tray = new Tray(nativeImage.createEmpty())
  if (process.platform === 'darwin') tray.setTitle(' 译')
  tray.setToolTip('闪译 · Glint')
  rebuildTray()
}

function registerHotkeys() {
  globalShortcut.unregisterAll()
  const hk = settings.get().hotkeys
  const handlers = {
    input: onInputTranslate,
    screenshot: onScreenshotTranslate,
    selection: onSelectionTranslate,
  }
  for (const key of Object.keys(handlers)) {
    const accel = hk[key]
    if (!accel) continue
    try {
      if (!globalShortcut.register(accel, handlers[key])) {
        console.warn('快捷键注册失败（可能被占用）：', accel)
      }
    } catch (e) {
      console.warn('快捷键注册异常：', accel, e.message)
    }
  }
}

// 校验一组快捷键是否可注册（不留下注册状态），返回失败的键名数组。
function validateHotkeys(hk) {
  globalShortcut.unregisterAll()
  const failed = []
  for (const key of Object.keys(hk)) {
    const accel = hk[key]
    let ok = false
    try {
      ok = !!accel && globalShortcut.register(accel, () => {})
    } catch {
      ok = false
    }
    if (!ok) failed.push(key)
  }
  globalShortcut.unregisterAll()
  return failed
}

/* ------------------------------------------------------------------ */
/* 应用生命周期                                                        */
/* ------------------------------------------------------------------ */

if (!app.requestSingleInstanceLock()) {
  app.quit()
} else {
  app.whenReady().then(() => {
    if (process.platform === 'darwin') app.dock.hide()
    createTranslatorWindow()
    createTray()
    registerHotkeys()
    prepareOCR() // 后台预编译 Vision OCR 二进制（仅 Mac）
  })

  app.on('window-all-closed', () => {})
  app.on('will-quit', () => globalShortcut.unregisterAll())
}
