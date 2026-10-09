'use strict'

const { contextBridge, ipcRenderer } = require('electron')

contextBridge.exposeInMainWorld('selectionPopup', {
  translate: () => ipcRenderer.send('selection-popup:translate'),
})
