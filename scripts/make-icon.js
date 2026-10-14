'use strict'

const { app, BrowserWindow } = require('electron')
const assert = require('node:assert/strict')
const fs = require('node:fs')
const path = require('node:path')
const { executeAppBuilder } = require('builder-util')

const root = path.resolve(__dirname, '..')
const cache = path.join(root, '.cache')
fs.mkdirSync(cache, { recursive: true })
const output = fs.mkdtempSync(path.join(cache, 'icon-build-'))
app.setPath('userData', path.join(output, 'electron-data'))

app.whenReady().then(async () => {
  const win = new BrowserWindow({
    show: false,
    width: 1024,
    height: 1024,
    frame: false,
    transparent: true,
    backgroundColor: '#00000000',
    webPreferences: { offscreen: true },
  })
  await win.loadFile(path.join(__dirname, 'icon.html'))
  await win.webContents.executeJavaScript('document.fonts.ready.then(() => new Promise(resolve => requestAnimationFrame(() => requestAnimationFrame(resolve))))')
  const capture = await win.webContents.capturePage({ x: 0, y: 0, width: 1024, height: 1024 })
  const { width, height } = capture.getSize()
  assert.equal(width, height, 'Icon capture must preserve square geometry')
  const image = capture.resize({ width: 1024, height: 1024, quality: 'best' })
  const png = path.join(output, 'icon.png')
  fs.writeFileSync(png, image.toPNG())
  for (const format of ['icns', 'ico']) {
    const result = JSON.parse(await executeAppBuilder([
      'icon', '--format', format, '--root', root,
      '--input', png, '--out', path.join(output, format),
    ]))
    if (result.error) throw new Error(result.error)
    assert.equal(result.icons.length, 1)
    fs.copyFileSync(result.icons[0].file, path.join(output, 'icon.' + format))
  }
  for (const format of ['png', 'icns', 'ico']) {
    fs.copyFileSync(path.join(output, 'icon.' + format), path.join(root, 'build', 'icon.' + format))
  }
  console.log('Generated PNG, ICNS and ICO from one 1024×1024 master')
  app.exit(0)
}).catch(error => {
  console.error(error)
  app.exit(1)
})
