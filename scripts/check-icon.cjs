'use strict'

const { app, nativeImage } = require('electron')
const assert = require('node:assert/strict')
const fs = require('node:fs')
const path = require('node:path')

const root = path.resolve(__dirname, '..')
const cache = path.join(root, '.cache')
fs.mkdirSync(cache, { recursive: true })
app.setPath('userData', fs.mkdtempSync(path.join(cache, 'icon-check-')))

function checkTile(image, name) {
  const { width, height } = image.getSize()
  assert.equal(width, height, name + ': square canvas')
  const pixels = image.toBitmap()
  let left = width, top = height, right = 0, bottom = 0
  for (let y = 0; y < height; y++) {
    for (let x = 0; x < width; x++) {
      if (pixels[(y * width + x) * 4 + 3] < 128) continue
      left = Math.min(left, x)
      top = Math.min(top, y)
      right = Math.max(right, x)
      bottom = Math.max(bottom, y)
    }
  }
  const tolerance = width < 256 ? 2 : 1
  assert.ok(Math.abs((right - left) - (bottom - top)) <= tolerance, name + ': square tile')
  assert.ok(Math.abs(left - (width - 1 - right)) <= 1, name + ': centered horizontally')
  assert.ok(Math.abs(top - (height - 1 - bottom)) <= 1, name + ': centered vertically')
  assert.ok(left >= width * 0.07 && left <= width * 0.12, name + ': transparent margin')
}

app.whenReady().then(() => {
  const master = nativeImage.createFromPath(path.join(root, 'build/icon.png'))
  assert.deepEqual(master.getSize(), { width: 1024, height: 1024 })
  checkTile(master, 'PNG')
  const icns = fs.readFileSync(path.join(root, 'build/icon.icns'))
  assert.equal(icns.toString('ascii', 0, 4), 'icns')
  assert.equal(icns.readUInt32BE(4), icns.length)
  const sizes = new Set()
  for (let offset = 8; offset < icns.length;) {
    const length = icns.readUInt32BE(offset + 4)
    assert.ok(length > 8 && offset + length <= icns.length)
    const content = icns.subarray(offset + 8, offset + length)
    if (content.subarray(0, 8).toString('hex') === '89504e470d0a1a0a') {
      const image = nativeImage.createFromBuffer(content)
      checkTile(image, icns.toString('ascii', offset, offset + 4))
      const { width } = image.getSize()
      sizes.add(width)
      if (width === 1024) assert.deepEqual(image.toBitmap(), master.toBitmap())
    }
    offset += length
  }
  for (const size of [32, 64, 128, 256, 512, 1024]) assert.ok(sizes.has(size), 'ICNS size ' + size)
  const ico = fs.readFileSync(path.join(root, 'build/icon.ico'))
  assert.equal(ico.readUInt16LE(2), 1)
  const icoSizes = new Set()
  for (let i = 0; i < ico.readUInt16LE(4); i++) {
    const offset = 6 + i * 16
    const width = ico[offset] || 256
    assert.equal(width, ico[offset + 1] || 256)
    const start = ico.readUInt32LE(offset + 12)
    const end = start + ico.readUInt32LE(offset + 8)
    assert.ok(end <= ico.length)
    const content = ico.subarray(start, end)
    if (content.subarray(0, 8).toString('hex') === '89504e470d0a1a0a') {
      checkTile(nativeImage.createFromBuffer(content), 'ICO ' + width)
    }
    icoSizes.add(width)
  }
  assert.ok(icoSizes.has(256), 'ICO includes a high resolution image')
  console.log('PASS: square centered tiles, transparent margins, ICNS master consistency and platform sizes')
  app.quit()
}).catch(error => {
  console.error(error)
  app.exit(1)
})
