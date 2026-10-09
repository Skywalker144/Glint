'use strict'

const fs = require('node:fs')
const path = require('node:path')
const crypto = require('node:crypto')
const { execFile } = require('node:child_process')
const { app } = require('electron')

const builds = new Map()

function resolveNativeHelper(name, frameworks) {
  if (process.platform !== 'darwin') return Promise.resolve(null)
  if (app.isPackaged) {
    const binary = path.join(process.resourcesPath, name)
    return Promise.resolve(fs.existsSync(binary) ? binary : null)
  }
  if (builds.has(name)) return builds.get(name)
  const build = new Promise(resolve => {
    const source = path.join(__dirname, 'native', name + '.swift')
    let output
    try {
      const hash = crypto.createHash('sha256').update(fs.readFileSync(source)).update(process.arch)
        .update(frameworks.join(',')).digest('hex').slice(0, 12)
      fs.mkdirSync(app.getPath('userData'), { recursive: true })
      output = path.join(app.getPath('userData'), name + '-' + hash)
      if (fs.existsSync(output)) return resolve(output)
    } catch (error) {
      console.warn(name + ' 准备失败：', error.message)
      return resolve(null)
    }
    execFile('swiftc', ['-O', source, '-o', output, ...frameworks.flatMap(f => ['-framework', f])], error => {
      if (error) console.warn(name + ' 编译失败：', error.message)
      resolve(error ? null : output)
    })
  })
  builds.set(name, build)
  return build
}

module.exports = { resolveNativeHelper }
