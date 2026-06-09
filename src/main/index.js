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
  net,
  session,
} = require('electron')

const { translate, translateStream } = require('./translate')
const { recognize, prepare: prepareOCR } = require('./ocr')
const { getSelectedText } = require('./platform')
const settings = require('./settings')
const history = require('./history')
const { translateWith, listModels } = require('./engines')
const { listProviders, getProvider } = require('./engines/providers')
const { LANGUAGES, pickDirection, isWordLookup, isLanguageCode } = require('./languages')
const { renderMarkdown } = require('./markdown')
const { CHANGELOG } = require('./changelog')
const { isNewer } = require('./version')
const tts = require('./tts')
const updater = require('./updater')

const PRELOAD = path.join(__dirname, '..', 'preload', 'index.js')
const RENDERER = path.join(__dirname, '..', 'renderer')

const WIN_WIDTH = 420 // 主窗口默认宽度
const WIN_MIN_WIDTH = 360 // 横向拖拽下限
const WIN_MAX_WIDTH = 820 // 横向拖拽上限
const WIN_MAX_HEIGHT = 600 // 主窗口高度自适应上限
const SETTINGS_W = 640
const SETTINGS_H = 460 // 初始高度；之后由渲染层按当前栏内容自适应
const REPO_URL = 'https://github.com/Skywalker144/Glint'

let translatorWin = null
let captureWin = null
let settingsWin = null
let tray = null
let isQuitting = false
let captureState = null // { image, scaleFactor }
let suppressBlurHide = false // 刚显示窗口的瞬间不触发失焦自动隐藏
let translatorPositioned = false // 主窗口是否已摆过位置（钉住时只在首次摆放）
let latestUpdate = null // 可用更新 { latest, url, assets }
let updateReady = false // 新版已下载就绪
let updateDownloading = false
let updateProgress = 0
let updateError = ''
let activeStream = null // 当前在途的流式请求 AbortController（发起新请求或点停止时取消）

/* ------------------------------------------------------------------ */
/* 主翻译窗口                                                          */
/* ------------------------------------------------------------------ */

function createTranslatorWindow() {
  const s = settings.get()
  const startW = Math.max(WIN_MIN_WIDTH, Math.min(WIN_MAX_WIDTH, s.windowWidth || WIN_WIDTH))
  // 钉住且记住的位置仍落在某个显示器内 → 在该位置开窗（否则首次 show 时跟随光标）
  const useSaved = !!s.pinned && isPositionVisible(s.windowX, s.windowY, startW)
  if (useSaved) translatorPositioned = true
  translatorWin = new BrowserWindow({
    width: startW,
    height: 182, // 初始紧凑高度（仅输入框）；之后由渲染层按内容自动调整
    ...(useSaved ? { x: s.windowX, y: s.windowY } : {}),
    show: false,
    frame: false,
    resizable: true, // 仅横向可拖宽；高度始终随内容自适应（resize-height 里 min==max 锁死纵向）
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

  // 初始锁死纵向（之后每次 resize-height 会按内容高度重设这两个上下限）
  translatorWin.setMinimumSize(WIN_MIN_WIDTH, 182)
  translatorWin.setMaximumSize(WIN_MAX_WIDTH, 182)

  // 用户横向拖拽后记住宽度（防抖 400ms；只在宽度真变了时写，高度变化不触发保存）
  let widthSaveTimer = null
  translatorWin.on('resize', () => {
    if (!translatorWin || translatorWin.isDestroyed()) return
    if (widthSaveTimer) clearTimeout(widthSaveTimer)
    widthSaveTimer = setTimeout(() => {
      if (!translatorWin || translatorWin.isDestroyed()) return
      const [cw] = translatorWin.getContentSize()
      if (cw !== (settings.get().windowWidth || WIN_WIDTH)) settings.save({ windowWidth: cw })
    }, 400)
  })

  // 钉住时记住用户拖动窗口后的位置（防抖 400ms；未钉住时跟随光标、不保存）
  let posSaveTimer = null
  translatorWin.on('move', () => {
    if (!translatorWin || translatorWin.isDestroyed() || !settings.get().pinned) return
    if (posSaveTimer) clearTimeout(posSaveTimer)
    posSaveTimer = setTimeout(() => {
      if (!translatorWin || translatorWin.isDestroyed()) return
      const [x, y] = translatorWin.getPosition()
      settings.save({ windowX: x, windowY: y })
    }, 400)
  })

  translatorWin.setVisibleOnAllWorkspaces(true, { visibleOnFullScreen: true })
  translatorWin.loadFile(path.join(RENDERER, 'translator.html'))

  translatorWin.on('close', (e) => {
    if (!isQuitting) {
      e.preventDefault()
      translatorWin.hide()
    }
  })

  // 未钉住时，窗口失焦（切到别的应用）就自动收起。
  translatorWin.on('blur', () => {
    if (suppressBlurHide || isQuitting) return
    if (settings.get().pinned) return
    if (!translatorWin || translatorWin.isDestroyed() || !translatorWin.isVisible()) return
    // 失焦瞬间若光标仍落在窗口范围内（含边缘外一圈余量）→ 多半是拖边缘缩放这类「假失焦」
    // 误触，而不是真的点了别处，此时不收起。真正切到别的应用时光标会远离本窗口，照常收起。
    // 这解决了「光标停在可见边缘外、macOS 原生缩放光标(↔)出现、一拖窗口却被收起」的问题：
    // 原生缩放热区会探出窗口外几像素，落在那条缝里按下会穿透到后面的窗口 → 失焦 → 收起。
    const p = screen.getCursorScreenPoint()
    const b = translatorWin.getBounds()
    const m = 12 // 边缘外余量（px），覆盖原生缩放热区
    if (p.x >= b.x - m && p.x <= b.x + b.width + m && p.y >= b.y - m && p.y <= b.y + b.height + m) return
    translatorWin.hide()
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

// 保存的坐标是否还落在某个显示器内（换显示器/改分辨率后就当无效，回退跟随光标）。
// 以标题栏中点判断，确保可拖动区域可达。
function isPositionVisible(x, y, w) {
  if (typeof x !== 'number' || typeof y !== 'number') return false
  const px = x + Math.min(w, 220) / 2
  const py = y + 12
  return screen.getAllDisplays().some((d) => {
    const a = d.workArea
    return px >= a.x && px < a.x + a.width && py >= a.y && py < a.y + a.height
  })
}

function showTranslator() {
  if (!translatorWin || translatorWin.isDestroyed()) createTranslatorWindow()
  // 未钉住：每次跟随光标。钉住：保持上次摆放的位置；仅首次（还没摆过）放到光标附近。
  if (!settings.get().pinned || !translatorPositioned) {
    positionNearCursor(translatorWin)
    translatorPositioned = true
  }
  suppressBlurHide = true // 显示瞬间的焦点抖动不触发自动隐藏
  translatorWin.show()
  translatorWin.focus()
  if (process.platform === 'darwin') app.focus({ steal: true })
  sendToTranslator('pin:state', !!settings.get().pinned)
  setTimeout(() => {
    suppressBlurHide = false
  }, 300)
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

// 功能 4：翻译剪贴板当前文本
function onClipboardTranslate() {
  const text = (clipboard.readText() || '').trim()
  showTranslator()
  if (!text) {
    sendToTranslator('show-message', '剪贴板里没有文本。先复制一段文字，再按快捷键。')
    return
  }
  sendToTranslator('translate-text', text)
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
ipcMain.handle('render-markdown', (_e, text) => renderMarkdown(text))

// 朗读：取在线自然语音的 MP3（base64）回渲染层播放；失败渲染层回退本地语音。
ipcMain.handle('tts:speak', async (_e, payload) => {
  try {
    const audio = await tts.speak(payload && payload.text, payload && payload.code)
    return audio ? { ok: true, audio } : { ok: false, error: 'empty' }
  } catch (e) {
    return { ok: false, error: e.message }
  }
})
ipcMain.handle('update:check', () => checkForUpdate())
ipcMain.on('update:apply', () => applyUpdateAndQuit())

// 流式翻译：渲染层发起，主进程把 meta/delta/done/error 逐步推回。token 用于忽略过期请求。
// payload.target 为用户在窗口里手动指定的目标语言（空 = 自动方向）。
ipcMain.on('translate:stream', async (event, payload) => {
  const token = payload && payload.token
  const text = ((payload && payload.text) || '').trim()
  const send = (m) => {
    if (!event.sender.isDestroyed()) event.sender.send('translate:event', { token, ...m })
  }
  if (!text) {
    send({ type: 'done', item: { original: '', translated: '', source: '', target: '', engine: '' } })
    return
  }

  // 取消上一条还在跑的流（连按两次 / 切换方向时不白烧 token）
  if (activeStream) activeStream.abort()
  const ac = new AbortController()
  activeStream = ac

  const s = settings.get()
  const engineId = s.engine || 'google'
  const p = getProvider(engineId)
  const forced = payload && payload.target && isLanguageCode(payload.target) ? payload.target : ''
  const dir = pickDirection(text, s.primaryLanguage, s.secondaryLanguage)
  const target = forced || dir.target
  // 手动指定目标语言时按整句翻译处理，不进词典
  const isDict = !forced && s.dictionaryMode !== false && p && p.kind !== 'free' && isWordLookup(text)
  send({ type: 'meta', source: dir.source, target, mode: isDict ? 'dict' : 'translate', word: isDict ? text : '' })
  try {
    const item = await translateStream(text, (delta) => send({ type: 'delta', delta }), { signal: ac.signal, target: forced })
    if (activeStream === ac) activeStream = null
    send({ type: 'done', item })
  } catch (e) {
    if (activeStream === ac) activeStream = null
    // 用户主动停止 / 发起新请求导致的中断：渲染层已自行收尾，这里不再报错
    if (e && (e.name === 'AbortError' || /abort/i.test(e.message || ''))) return
    send({ type: 'error', error: friendlyError(e, engineId) })
  }
})

// 用户点「停止」：中断在途的流式请求（渲染层会保留已生成的部分）。
ipcMain.on('translate:stop', () => {
  if (activeStream) {
    activeStream.abort()
    activeStream = null
  }
})

ipcMain.on('hide-window', () => {
  if (translatorWin && !translatorWin.isDestroyed()) translatorWin.hide()
})

// 主窗口标题栏的齿轮 → 打开设置
ipcMain.on('open-settings', () => openSettings())

// 切换钉住状态（持久化），并回推给渲染层同步按钮高亮。
ipcMain.on('pin:set', (_e, val) => {
  settings.save({ pinned: !!val })
  sendToTranslator('pin:state', !!val)
})

ipcMain.on('copy-text', (_e, text) => {
  clipboard.writeText(text || '')
})

// 渲染层上报内容高度 -> 调整窗口高度，使其紧贴内容（没结果时收起底部空白）。
ipcMain.on('resize-height', (_e, h) => {
  if (!translatorWin || translatorWin.isDestroyed()) return
  const height = Math.max(120, Math.min(WIN_MAX_HEIGHT, Math.round(h)))
  const [w] = translatorWin.getContentSize()
  // 高度随内容自适应；同时把纵向 min==max 锁到该高度 → 拖不动高度，只能横向拖宽
  translatorWin.setMinimumSize(WIN_MIN_WIDTH, height)
  translatorWin.setMaximumSize(WIN_MAX_WIDTH, height)
  translatorWin.setContentSize(w, height)
})

// 自定义右边缘宽度拖拽（渲染层手柄）：比原生 ~3px 边框好抓，且整段拖动期间抑制失焦
// 自动收起——避免「够边缘没够准 → 点到窗外 → 窗口被收起」的误触。
let resizeStartWidth = 0
ipcMain.on('win:resize-start', () => {
  if (!translatorWin || translatorWin.isDestroyed()) return
  resizeStartWidth = translatorWin.getContentSize()[0]
  suppressBlurHide = true
})
ipcMain.on('win:resize-move', (_e, dx) => {
  if (!translatorWin || translatorWin.isDestroyed()) return
  const h = translatorWin.getContentSize()[1]
  const w = Math.max(WIN_MIN_WIDTH, Math.min(WIN_MAX_WIDTH, Math.round(resizeStartWidth + (dx || 0))))
  translatorWin.setContentSize(w, h)
})
ipcMain.on('win:resize-end', () => {
  suppressBlurHide = false
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
  sendToTranslator(
    'show-message',
    process.platform === 'darwin' ? '正在识别文字…' : '正在识别文字…（首次使用会下载识别引擎，请稍候）'
  )

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
ipcMain.handle('settings:defaults', () => settings.DEFAULTS)
ipcMain.handle('settings:providers', () => listProviders())
ipcMain.handle('settings:languages', () => LANGUAGES)
ipcMain.handle('app:info', () => ({ version: app.getVersion(), repo: REPO_URL }))
ipcMain.handle('changelog:get', () => CHANGELOG)
ipcMain.handle('settings:permissions', () => ({
  platform: process.platform,
  accessibility:
    process.platform === 'darwin'
      ? systemPreferences.isTrustedAccessibilityClient(false)
      : true,
  screen:
    process.platform === 'darwin'
      ? systemPreferences.getMediaAccessStatus('screen')
      : 'granted',
}))

ipcMain.on('settings:open-permission', (_e, kind) => {
  if (process.platform !== 'darwin') return
  if (kind === 'accessibility') {
    systemPreferences.isTrustedAccessibilityClient(true)
    shell.openExternal('x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility')
  } else if (kind === 'screen') {
    shell.openExternal('x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture')
  }
})

ipcMain.on('open-external', (_e, url) => {
  if (typeof url === 'string' && /^https?:\/\//.test(url)) shell.openExternal(url)
})

ipcMain.handle('settings:save', (_e, partial) => {
  const s = settings.save(partial)
  // 设置窗口此时聚焦、全局快捷键已禁用，这里只做注册校验（之后关窗会真正注册）。
  const hotkeyErrors = validateHotkeys(s.hotkeys)
  rebuildTray()
  applyLoginItem()
  applyProxy()
  sendToTranslator('pin:state', !!s.pinned) // 同步主窗口图钉
  return { settings: s, hotkeyErrors }
})

ipcMain.handle('settings:test', async (_e, cfg) => {
  try {
    const { translated } = await translateWith(
      cfg.engine,
      { apiKey: cfg.apiKey, model: cfg.model, baseURL: cfg.baseURL },
      'Hello, world. This is a test.',
      'zh-CN',
      { systemPrompt: cfg.systemPrompt }
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

// 用给定代理临时连一次 204 连通性端点，测完恢复已保存的代理。
ipcMain.handle('settings:test-proxy', async (_e, cfg) => {
  const url = ((cfg && cfg.url) || '').trim()
  try {
    await session.defaultSession.setProxy(url ? { proxyRules: url, proxyBypassRules: '<local>' } : { mode: 'direct' })
    const ac = new AbortController()
    const timer = setTimeout(() => ac.abort(), 8000)
    const t0 = Date.now()
    const res = await net.fetch('https://www.gstatic.com/generate_204', { signal: ac.signal })
    clearTimeout(timer)
    const ms = Date.now() - t0
    applyProxy()
    if (res.status === 204 || res.ok) return { ok: true, ms }
    return { ok: false, error: 'HTTP ' + res.status }
  } catch (e) {
    applyProxy()
    return { ok: false, error: e.name === 'AbortError' ? '超时（8s），代理可能不通' : e.message }
  }
})

ipcMain.handle('history:list', () => history.list())
ipcMain.handle('history:clear', () => history.clear())

// 设置窗口高度随当前栏内容自适应。
ipcMain.on('settings:resize-height', (_e, h) => {
  if (!settingsWin || settingsWin.isDestroyed()) return
  const area = screen.getDisplayNearestPoint(screen.getCursorScreenPoint()).workArea
  const maxH = Math.min(area.height - 60, 720)
  const height = Math.max(360, Math.min(maxH, Math.round(h)))
  const [w] = settingsWin.getContentSize()
  settingsWin.setContentSize(w, height)
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
  const items = []
  if (updateReady && latestUpdate) {
    items.push(
      { label: '↻ 重启以更新到 v' + latestUpdate.latest, click: applyUpdateAndQuit },
      { type: 'separator' }
    )
  } else if (latestUpdate) {
    items.push(
      {
        label: '↓ 有新版 v' + latestUpdate.latest + (updateDownloading ? '（下载中…）' : ''),
        click: () => shell.openExternal(latestUpdate.url),
      },
      { type: 'separator' }
    )
  }
  items.push(
    { label: '输入翻译   ' + accelSymbol(hk.input), click: onInputTranslate },
    { label: '截图翻译   ' + accelSymbol(hk.screenshot), click: onScreenshotTranslate },
    { label: '划词翻译   ' + accelSymbol(hk.selection), click: onSelectionTranslate },
    { label: '剪贴板翻译 ' + accelSymbol(hk.clipboard), click: onClipboardTranslate },
    { type: 'separator' },
    { label: '设置…', click: openSettings },
    { type: 'separator' },
    {
      label: '退出',
      click: () => {
        isQuitting = true
        app.quit()
      },
    }
  )
  return Menu.buildFromTemplate(items)
}

function rebuildTray() {
  if (tray) tray.setContextMenu(buildTrayMenu())
}

// 菜单栏模板图标（黑色「译」，系统按浅/深色自动反色）；自带 @2x 适配 Retina。
function trayImage() {
  try {
    const img = nativeImage.createFromPath(path.join(__dirname, 'assets', 'trayTemplate.png'))
    if (!img.isEmpty()) {
      img.setTemplateImage(true)
      return img
    }
  } catch {}
  return null
}

function createTray() {
  const img = trayImage()
  tray = new Tray(img || nativeImage.createEmpty())
  if (!img && process.platform === 'darwin') tray.setTitle(' 译') // 没读到图标时退回文字
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
    clipboard: onClipboardTranslate,
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
    if (!accel) continue // 空 = 用户主动不设该快捷键（仍可从菜单栏触发），不算错误
    let ok = false
    try {
      ok = globalShortcut.register(accel, () => {})
    } catch {
      ok = false
    }
    if (!ok) failed.push(key)
  }
  globalShortcut.unregisterAll()
  return failed
}

// 开机自启（macOS / Windows）。注意：dev 模式下登录项指向 Electron 本体，
// 打包成 .app 后才真正可用；openAsHidden 让它登录后静默到菜单栏。
function applyLoginItem() {
  if (process.platform === 'linux') return
  try {
    app.setLoginItemSettings({ openAtLogin: !!settings.get().launchAtLogin, openAsHidden: true })
  } catch (e) {
    console.warn('设置开机自启失败：', e.message)
  }
}

// 网络代理：开启时让 net.fetch（走 defaultSession）经代理，关闭时直连。
function applyProxy() {
  const p = settings.get().proxy || {}
  const url = p.enabled ? (p.url || '').trim() : ''
  const config = url ? { proxyRules: url, proxyBypassRules: '<local>' } : { mode: 'direct' }
  session.defaultSession.setProxy(config).catch((e) => console.warn('设置代理失败：', e.message))
}

/* ---------------- 检查更新（对比 GitHub 最新 Release）---------------- */

const RELEASES_API = 'https://api.github.com/repos/Skywalker144/Glint/releases/latest'

function updateStateSummary(extra) {
  return {
    ok: true,
    current: app.getVersion(),
    latest: latestUpdate ? latestUpdate.latest : '',
    hasUpdate: !!latestUpdate,
    ready: updateReady,
    downloading: updateDownloading,
    progress: updateProgress,
    error: updateError,
    url: latestUpdate ? latestUpdate.url : REPO_URL + '/releases/latest',
    canAutoUpdate: app.isPackaged && (process.platform === 'darwin' || process.platform === 'win32'),
    ...(extra || {}),
  }
}

function broadcastUpdateState() {
  if (settingsWin && !settingsWin.isDestroyed()) {
    settingsWin.webContents.send('update:state', updateStateSummary())
  }
}

// 发现新版后后台自动下载（仅打包版、Mac/Win）。
function maybeAutoDownload() {
  if (!app.isPackaged || (process.platform !== 'darwin' && process.platform !== 'win32')) return
  if (updateReady || updateDownloading || !latestUpdate) return
  updateDownloading = true
  updateError = ''
  updateProgress = 0
  broadcastUpdateState()
  updater
    .downloadUpdate(latestUpdate.assets, (p) => {
      updateProgress = p
      broadcastUpdateState()
    })
    .then(() => {
      updateDownloading = false
      updateReady = true
      updateProgress = 1
      rebuildTray()
      broadcastUpdateState()
    })
    .catch((e) => {
      updateDownloading = false
      updateError = e.message
      broadcastUpdateState()
    })
}

async function checkForUpdate() {
  const current = app.getVersion()
  try {
    const res = await net.fetch(RELEASES_API, {
      headers: { 'User-Agent': 'Glint', Accept: 'application/vnd.github+json' },
    })
    if (!res.ok) return { ok: false, current, error: 'HTTP ' + res.status }
    const data = await res.json()
    const latest = (data.tag_name || '').replace(/^v/, '')
    if (latest && isNewer(latest, current)) {
      latestUpdate = {
        latest,
        url: data.html_url || REPO_URL + '/releases/latest',
        assets: (data.assets || []).map((a) => ({ name: a.name, url: a.browser_download_url, size: a.size })),
      }
      rebuildTray()
      maybeAutoDownload() // 后台自动下载新版
    }
    return updateStateSummary()
  } catch (e) {
    return { ok: false, current, error: e.message }
  }
}

function applyUpdateAndQuit() {
  if (!updateReady) return
  isQuitting = true
  updater.applyUpdate()
  app.quit()
}

function scheduleUpdateChecks() {
  setTimeout(() => checkForUpdate(), 5000) // 启动后台静默查一次
  setInterval(() => checkForUpdate(), 24 * 60 * 60 * 1000) // 每天一次
}

// 把底层报错（HTTP 状态 / 网络 / net::ERR_* / 超时）翻成人话 + 行动指引。
function friendlyError(e, engineId) {
  const msg = (e && e.message) || String(e || '未知错误')
  const p = getProvider(engineId)
  const isFree = !p || p.kind === 'free'
  if (/ERR_PROXY/i.test(msg)) return '代理连接失败，检查 设置→通用→网络代理 的地址'
  if (/abort|ERR_TIMED_OUT|ETIMEDOUT|timed?\s*out|超时/i.test(msg)) return '请求超时——网络或代理较慢，稍后再试'
  if (/ERR_NAME_NOT_RESOLVED|ERR_INTERNET_DISCONNECTED|ERR_CONNECTION|ERR_NETWORK|ENOTFOUND|EAI_AGAIN/i.test(msg))
    return isFree ? '网络不通——Google 在受限网络可能要开代理（设置→通用）' : '网络不通——可在 设置→通用 开代理'
  if (/\b401\b|\b403\b|unauthorized|invalid.*api.*key|permission/i.test(msg)) return 'API Key 无效或没权限，去 设置→AI 检查'
  if (/\b429\b|rate.?limit|quota|insufficient|exceeded|billing/i.test(msg)) return '请求太频繁或额度/账单用尽，稍后再试'
  if (/\b404\b/.test(msg)) return '模型或接口地址不对，去 设置→AI 检查模型 / Base URL'
  if (/\b5\d\d\b/.test(msg)) return '服务商暂时不可用，稍后再试'
  if (/未配置 API Key|未选择模型|缺少 Base URL/.test(msg)) return msg + '——去 设置→AI 配置'
  return msg
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
    applyLoginItem() // 按设置同步开机自启
    applyProxy() // 按设置同步网络代理
    scheduleUpdateChecks() // 启动 + 每日检查更新
  })

  app.on('window-all-closed', () => {})
  app.on('will-quit', () => globalShortcut.unregisterAll())
}
