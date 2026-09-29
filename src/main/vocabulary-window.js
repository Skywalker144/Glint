'use strict'

const path = require('node:path')
const { app, BrowserWindow, ipcMain, screen } = require('electron')

let window = null

function openVocabulary() {
  if (!window || window.isDestroyed()) {
    const area = screen.getDisplayNearestPoint(screen.getCursorScreenPoint()).workArea
    window = new BrowserWindow({
      width: Math.min(760, area.width), height: Math.min(560, area.height),
      minWidth: 480, minHeight: 360, show: false, frame: false,
      transparent: true, hasShadow: true, roundedCorners: false,
      fullscreenable: false, backgroundColor: '#00000000',
      webPreferences: { preload: path.join(__dirname, '../preload/index.js'), contextIsolation: true, nodeIntegration: false },
    })
    window.loadFile(path.join(__dirname, '../renderer/vocabulary.html'))
    window.once('ready-to-show', () => {
      if (!window || window.isDestroyed()) return
      window.show()
      window.focus()
    })
  } else {
    if (window.isMinimized()) window.restore()
    window.show()
    window.focus()
  }
  if (process.platform === 'darwin') app.focus({ steal: true })
}

ipcMain.on('vocabulary:open', openVocabulary)
ipcMain.on('vocabulary:close', (event) => {
  if (window && !window.isDestroyed() && window.webContents === event.sender) window.close()
})

module.exports = { openVocabulary }
