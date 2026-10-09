'use strict'

const path = require('node:path')
const { spawn } = require('node:child_process')
const { createInterface } = require('node:readline')
const { app, BrowserWindow, ipcMain, screen } = require('electron')
const { resolveNativeHelper } = require('./native-helper')
const { SelectionPopupState } = require('./selection-popup-state')

class SelectionPopup {
  constructor({ translate, isBlocked }) {
    this.window = null
    this.windowReady = null
    this.monitor = null
    this.nativeStatus = null
    this.generation = 0
    this.enabled = false
    this.state = new SelectionPopupState({
      show: bounds => {
        this.window.setBounds(bounds)
        this.window.showInactive()
      },
      hide: () => this.window?.hide(),
      getWorkArea: point => screen.getDisplayNearestPoint(point).workArea,
      isBlocked,
      translate,
    })
    this.onActivate = event => {
      if (this.window && event.sender === this.window.webContents) this.state.activate()
    }
    this.onWindowFocus = (_event, window) => {
      if (window !== this.window) this.dismiss()
    }
    app.on('browser-window-focus', this.onWindowFocus)
    ipcMain.on('selection-popup:translate', this.onActivate)
  }

  setEnabled(value) {
    const enabled = process.platform === 'darwin' && !!value
    if (enabled === this.enabled) return
    this.enabled = enabled
    this.nativeStatus = null
    this.state.setEnabled(enabled)
    const generation = ++this.generation
    if (!enabled) {
      this.monitor?.kill()
      this.monitor = null
      return
    }
    this.start(generation).catch(error => {
      if (generation === this.generation) this.dismiss()
      console.warn('自动划词图标启动失败：', error.message)
    })
  }

  async start(generation) {
    const binary = await resolveNativeHelper('macselection', ['AppKit', 'ApplicationServices'])
    if (!binary || generation !== this.generation) return
    if (!this.window) {
      this.window = new BrowserWindow({
        width: 40, height: 40, type: 'panel', show: false, frame: false, transparent: true,
        resizable: false, focusable: false, acceptFirstMouse: true, skipTaskbar: true,
        minimizable: false, maximizable: false, fullscreenable: false,
        hasShadow: false, alwaysOnTop: true, roundedCorners: false,
        webPreferences: {
          preload: path.join(__dirname, '..', 'preload', 'selection-popup.js'),
          contextIsolation: true, nodeIntegration: false,
        },
      })
      this.window.setVisibleOnAllWorkspaces(true, { visibleOnFullScreen: true })
      this.windowReady = this.window.loadFile(path.join(__dirname, '..', 'renderer', 'selection-popup.html'))
    }
    await this.windowReady
    if (generation !== this.generation) return
    const monitor = spawn(binary, [String(process.pid)], { stdio: ['ignore', 'pipe', 'pipe'] })
    this.monitor = monitor
    const lines = createInterface({ input: monitor.stdout })
    lines.on('line', line => {
      if (generation !== this.generation) return
      let event
      try { event = JSON.parse(line) } catch { return }
      if (event && typeof event === 'object') {
        if (event.type === 'ready') this.nativeStatus = event
        else this.state.handle(event)
      }
    })
    monitor.stderr.on('data', data => console.warn('自动划词监视器：', data.toString().trim()))
    monitor.on('error', error => console.warn('自动划词监视器失败：', error.message))
    monitor.on('close', () => {
      lines.close()
      if (this.monitor !== monitor) return
      this.monitor = null
      this.nativeStatus = null
      this.dismiss()
    })
  }

  dismiss() {
    this.state.dismiss()
  }

  dispose() {
    this.setEnabled(false)
    ipcMain.removeListener('selection-popup:translate', this.onActivate)
    app.removeListener('browser-window-focus', this.onWindowFocus)
    this.window?.destroy()
    this.window = null
    this.windowReady = null
  }
}

module.exports = { SelectionPopup }
