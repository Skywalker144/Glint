// 生成菜单栏模板图标 src/main/assets/trayTemplate.png(@2x)：
// 纯黑「译」、透明底。模板图标由系统按浅/深色菜单栏自动反色。
const { app, BrowserWindow } = require('electron')
const fs = require('fs')
const path = require('path')
app.setPath('userData', '/tmp/trayrender')

const HTML = `<!doctype html><html><head><meta charset="utf-8"><style>
*{margin:0;padding:0;box-sizing:border-box}
html,body{width:320px;height:320px;background:transparent;overflow:hidden}
.wrap{width:320px;height:320px;display:grid;place-items:center}
.glyph{font-family:'PingFang SC',-apple-system,sans-serif;font-weight:600;font-size:264px;line-height:1;color:#000}
</style></head><body><div class="wrap"><span class="glyph">译</span></div></body></html>`

app.whenReady().then(async () => {
  const win = new BrowserWindow({
    show: true,
    x: -2000,
    y: 0,
    width: 320,
    height: 320,
    frame: false,
    transparent: true,
    backgroundColor: '#00000000',
    webPreferences: {},
  })
  await win.loadURL('data:text/html;charset=utf-8,' + encodeURIComponent(HTML))
  await new Promise((r) => setTimeout(r, 500))
  const img = await win.webContents.capturePage()
  const outDir = path.join(__dirname, '..', 'src', 'main', 'assets')
  fs.mkdirSync(outDir, { recursive: true })
  fs.writeFileSync(path.join(outDir, 'trayTemplate@2x.png'), img.resize({ width: 32, height: 32, quality: 'best' }).toPNG())
  fs.writeFileSync(path.join(outDir, 'trayTemplate.png'), img.resize({ width: 16, height: 16, quality: 'best' }).toPNG())
  console.log('TRAY_OK ' + img.getSize().width + 'x' + img.getSize().height)
  app.exit(0)
})
