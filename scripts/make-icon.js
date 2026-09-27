// 渲染 1024×1024 图标母图到 build/icon.png（透明背景）。
const { app, BrowserWindow } = require('electron')
const fs = require('fs')
const path = require('path')
app.setPath('userData', '/tmp/iconrender')

app.whenReady().then(async () => {
  const win = new BrowserWindow({
    show: true,
    x: -5000,
    y: 0,
    width: 1024,
    height: 1024,
    frame: false,
    transparent: true,
    backgroundColor: '#00000000',
    webPreferences: {},
  })
  await win.loadFile(path.join(__dirname, 'icon.html'))
  await new Promise((r) => setTimeout(r, 600))
  let img = await win.webContents.capturePage()
  if (img.getSize().width !== 1024) {
    img = img.resize({ width: 1024, height: 1024, quality: 'best' })
  }
  fs.writeFileSync(path.join(__dirname, '..', 'build', 'icon.png'), img.toPNG())
  console.log('ICON_PNG ' + img.getSize().width + 'x' + img.getSize().height)
  app.exit(0)
})
