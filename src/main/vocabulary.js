'use strict'

const path = require('node:path')
const { app, ipcMain, BrowserWindow } = require('electron')
const { VocabularyStore } = require('./vocabulary-store')

const vocabulary = new VocabularyStore(path.join(app.getPath('userData'), 'vocabulary.json'))

function registerVocabularyIPC() {
  ipcMain.handle('vocabulary:list', () => vocabulary.list())
  ipcMain.handle('vocabulary:add', (_event, entry) => vocabulary.add(entry))
  ipcMain.handle('vocabulary:remove', (_event, id) => vocabulary.remove(id))
  vocabulary.on('changed', (items) => {
    for (const win of BrowserWindow.getAllWindows()) {
      if (!win.webContents.isDestroyed()) win.webContents.send('vocabulary:changed', items)
    }
  })
}

module.exports = { vocabulary, registerVocabularyIPC }
