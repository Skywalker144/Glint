'use strict'

// 自定义更新器（绕过 Squirrel，给未签名的 ad-hoc 包用）。
// Mac：下载 -mac.zip → ditto 解压 → xattr 去隔离 → 应用时由脱离进程的脚本替换 .app 并重启。
// Win：下载 .exe 安装器 → 应用时直接运行它。

const fs = require('fs')
const path = require('path')
const { spawn } = require('child_process')
const { app, net } = require('electron')

let staged = null // 已下载就绪的新版路径（Mac: .app；Win: .exe）

function workDir() {
  return path.join(app.getPath('temp'), 'glint-update')
}

function run(cmd, args) {
  return new Promise((resolve, reject) => {
    const p = spawn(cmd, args, { stdio: 'ignore' })
    p.on('error', reject)
    p.on('close', (code) => (code === 0 ? resolve() : reject(new Error(cmd + ' 退出码 ' + code))))
  })
}

async function downloadTo(url, dest, onProgress) {
  const res = await net.fetch(url, { headers: { 'User-Agent': 'Glint' } })
  if (!res.ok) throw new Error('下载失败 HTTP ' + res.status)
  const total = Number(res.headers.get('content-length')) || 0
  const reader = res.body.getReader()
  const out = fs.createWriteStream(dest)
  let received = 0
  try {
    for (;;) {
      const { done, value } = await reader.read()
      if (done) break
      if (!out.write(Buffer.from(value))) {
        await new Promise((r) => out.once('drain', r))
      }
      received += value.length
      if (onProgress && total) onProgress(Math.min(1, received / total))
    }
  } finally {
    out.end()
  }
  await new Promise((r, j) => {
    out.on('finish', r)
    out.on('error', j)
  })
  return dest
}

// 下载并准备好新版（解压/去隔离）。assets: [{name,url,size}]
async function downloadUpdate(assets, onProgress) {
  staged = null
  const dir = workDir()
  fs.rmSync(dir, { recursive: true, force: true })
  fs.mkdirSync(dir, { recursive: true })

  if (process.platform === 'darwin') {
    const asset = (assets || []).find((a) => /-mac\.zip$/.test(a.name))
    if (!asset) throw new Error('未找到 Mac 更新包（-mac.zip）')
    const zip = path.join(dir, asset.name)
    await downloadTo(asset.url, zip, onProgress)
    await run('ditto', ['-x', '-k', zip, dir]) // 解压（ditto 正确处理 .app）
    const appBundle = path.join(dir, 'Glint.app')
    if (!fs.existsSync(appBundle)) throw new Error('解压后未找到 Glint.app')
    await run('xattr', ['-cr', appBundle]) // 去下载隔离
    staged = appBundle
    return
  }

  if (process.platform === 'win32') {
    const asset = (assets || []).find((a) => /\.exe$/.test(a.name))
    if (!asset) throw new Error('未找到 Windows 安装包（.exe）')
    const exe = path.join(dir, asset.name)
    await downloadTo(asset.url, exe, onProgress)
    staged = exe
    return
  }
  throw new Error('当前平台不支持自动更新')
}

function isReady() {
  return !!staged
}

function sh(s) {
  return "'" + String(s).replace(/'/g, "'\\''") + "'"
}

// 应用更新：Mac 派发脱离脚本替换 .app 并重启；Win 运行安装器。调用后应立即 app.quit()。
function applyUpdate() {
  if (!staged) return false

  if (process.platform === 'darwin') {
    const target = process.execPath.replace(/\/Contents\/MacOS\/[^/]+$/, '')
    if (!/\.app$/.test(target)) return false // dev 模式下不替换
    const pid = process.pid
    const script = [
      '#!/bin/bash',
      `while kill -0 ${pid} 2>/dev/null; do sleep 0.3; done`,
      'sleep 0.5',
      `if mv ${sh(target)} ${sh(target + '.old')} 2>/dev/null; then`,
      `  if mv ${sh(staged)} ${sh(target)} 2>/dev/null; then`,
      `    xattr -cr ${sh(target)}`,
      `    rm -rf ${sh(target + '.old')}`,
      `  else`,
      `    mv ${sh(target + '.old')} ${sh(target)}`, // 回滚
      `  fi`,
      'fi',
      `open ${sh(target)}`,
    ].join('\n')
    const file = path.join(workDir(), 'apply.sh')
    fs.writeFileSync(file, script, { mode: 0o755 })
    spawn('/bin/bash', [file], { detached: true, stdio: 'ignore' }).unref()
    return true
  }

  if (process.platform === 'win32') {
    spawn(staged, [], { detached: true, stdio: 'ignore' }).unref() // 运行 NSIS 安装器
    return true
  }
  return false
}

module.exports = { downloadUpdate, applyUpdate, isReady }
