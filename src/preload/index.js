'use strict'

const { contextBridge, ipcRenderer } = require('electron')

contextBridge.exposeInMainWorld('api', {
  // 翻译窗口
  translate: (text) => ipcRenderer.invoke('translate', text),
  renderMarkdown: (text) => ipcRenderer.invoke('render-markdown', text),
  translateStream: (text, token, target) => ipcRenderer.send('translate:stream', { text, token, target }),
  stopStream: () => ipcRenderer.send('translate:stop'),
  speak: (text, code) => ipcRenderer.invoke('tts:speak', { text, code }),
  onTranslateEvent: (cb) => ipcRenderer.on('translate:event', (_e, msg) => cb(msg)),
  hide: () => ipcRenderer.send('hide-window'),
  openSettings: () => ipcRenderer.send('open-settings'),
  setPinned: (val) => ipcRenderer.send('pin:set', val),
  onPinState: (cb) => ipcRenderer.on('pin:state', (_e, v) => cb(v)),
  copyText: (text) => ipcRenderer.send('copy-text', text),
  resizeHeight: (height) => ipcRenderer.send('resize-height', height),
  onFocusInput: (cb) => ipcRenderer.on('focus-input', () => cb()),
  onTranslateText: (cb) => ipcRenderer.on('translate-text', (_e, text) => cb(text)),
  onShowMessage: (cb) => ipcRenderer.on('show-message', (_e, msg) => cb(msg)),

  // 截图选区遮罩
  onCaptureInit: (cb) => ipcRenderer.on('capture:init', (_e, data) => cb(data)),
  captureSelect: (rect) => ipcRenderer.send('capture:selected', rect),
  captureCancel: () => ipcRenderer.send('capture:cancel'),

  // 设置页
  getSettings: () => ipcRenderer.invoke('settings:get'),
  getSettingDefaults: () => ipcRenderer.invoke('settings:defaults'),
  getProviders: () => ipcRenderer.invoke('settings:providers'),
  getLanguages: () => ipcRenderer.invoke('settings:languages'),
  getPermissions: () => ipcRenderer.invoke('settings:permissions'),
  getAppInfo: () => ipcRenderer.invoke('app:info'),
  getChangelog: () => ipcRenderer.invoke('changelog:get'),
  checkUpdate: () => ipcRenderer.invoke('update:check'),
  applyUpdate: () => ipcRenderer.send('update:apply'),
  onUpdateState: (cb) => ipcRenderer.on('update:state', (_e, s) => cb(s)),
  saveSettings: (partial) => ipcRenderer.invoke('settings:save', partial),
  testEngine: (cfg) => ipcRenderer.invoke('settings:test', cfg),
  fetchModels: (cfg) => ipcRenderer.invoke('settings:fetch-models', cfg),
  testProxy: (cfg) => ipcRenderer.invoke('settings:test-proxy', cfg),
  getHistory: () => ipcRenderer.invoke('history:list'),
  clearHistory: () => ipcRenderer.invoke('history:clear'),
  resizeSettings: (height) => ipcRenderer.send('settings:resize-height', height),
  closeSettings: () => ipcRenderer.send('settings:close'),
  openExternal: (url) => ipcRenderer.send('open-external', url),
  openPermissionSettings: (kind) => ipcRenderer.send('settings:open-permission', kind),
  onSettingsData: (cb) => ipcRenderer.on('settings:data', (_e, data) => cb(data)),
})
