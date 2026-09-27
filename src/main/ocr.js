'use strict'

const path = require('path')
const fs = require('fs')
const crypto = require('crypto')
const { execFile } = require('child_process')
const { app } = require('electron')
const { createWorker } = require('tesseract.js')

/* ------------------------------------------------------------------ */
/* 文本清洗（两种引擎都用）                                            */
/* ------------------------------------------------------------------ */

// 中日韩字符（含标点、假名、谚文、全角）—— 用来去掉它们之间多余的空格。
const CJK = '\\u3000-\\u303f\\u3040-\\u30ff\\u3400-\\u9fff\\uac00-\\ud7af\\uff00-\\uffef'
const CJK_GAP = new RegExp('([' + CJK + '])[ \\t]+(?=[' + CJK + '])', 'g')
const IS_CJK = new RegExp('[' + CJK + ']')

function cleanText(raw) {
  const lines = (raw || '').split(/\r?\n/).map((line) =>
    line.replace(CJK_GAP, '$1').replace(/[ \t]{2,}/g, ' ').trim()
  )

  const out = []
  let para = ''
  for (const line of lines) {
    if (!line) {
      if (para) out.push(para)
      para = ''
      continue
    }
    if (!para) {
      para = line
    } else {
      const joinTight = IS_CJK.test(para[para.length - 1]) && IS_CJK.test(line[0])
      para += joinTight ? line : ' ' + line
    }
  }
  if (para) out.push(para)
  return out.join('\n')
}

/* ------------------------------------------------------------------ */
/* Tesseract（跨平台兜底）                                            */
/* ------------------------------------------------------------------ */

let workerPromise = null
function getWorker() {
  if (!workerPromise) {
    workerPromise = createWorker(['eng', 'chi_sim'], 1, {
      cachePath: path.join(app.getPath('userData'), 'tessdata'),
    })
  }
  return workerPromise
}

async function recognizeTesseract(image) {
  const worker = await getWorker()
  const { data } = await worker.recognize(image)
  return data.text || ''
}

/* ------------------------------------------------------------------ */
/* macOS Vision（更准、离线、免费）                                    */
/* ------------------------------------------------------------------ */

const SWIFT_SRC = path.join(__dirname, 'native', 'macocr.swift')
let macBinaryPromise = null

// 首次使用时用 swiftc 编译 Swift 识别程序，并按源码哈希缓存（改源码会自动重编）。
function buildMacOCR() {
  if (macBinaryPromise) return macBinaryPromise
  macBinaryPromise = new Promise((resolve) => {
    let out
    try {
      const src = fs.readFileSync(SWIFT_SRC)
      const hash = crypto.createHash('sha1').update(src).digest('hex').slice(0, 8)
      out = path.join(app.getPath('userData'), 'macocr-' + hash)
    } catch {
      return resolve(null)
    }
    if (fs.existsSync(out)) return resolve(out)
    execFile(
      'swiftc',
      ['-O', SWIFT_SRC, '-o', out, '-framework', 'Vision', '-framework', 'AppKit'],
      (err) => {
        if (err) {
          console.warn('Vision OCR 编译失败，回退 Tesseract：', err.message)
          resolve(null)
        } else {
          resolve(out)
        }
      }
    )
  })
  return macBinaryPromise
}

function recognizeMac(binary, pngBuffer) {
  return new Promise((resolve, reject) => {
    const child = execFile(
      binary,
      [],
      { maxBuffer: 16 * 1024 * 1024, encoding: 'utf8' },
      (err, stdout) => {
        if (err) return reject(err)
        resolve(stdout || '')
      }
    )
    child.stdin.on('error', () => {}) // 避免 EPIPE 直接崩
    child.stdin.write(pngBuffer)
    child.stdin.end()
  })
}

/* ------------------------------------------------------------------ */
/* 统一入口                                                            */
/* ------------------------------------------------------------------ */

// 打包后用随 App 内置的预编译二进制（用户机无需 Xcode）；开发时为 null（走现编译）。
function bundledMacBinary() {
  if (!app.isPackaged) return null
  const p = path.join(process.resourcesPath, 'macocr')
  return fs.existsSync(p) ? p : null
}

// image 是 PNG Buffer。Mac 优先 Vision，失败或非 Mac 退回 Tesseract。
async function recognize(image) {
  if (process.platform === 'darwin') {
    const bin = bundledMacBinary() || (await buildMacOCR())
    if (bin) {
      try {
        return cleanText(await recognizeMac(bin, image))
      } catch (e) {
        console.warn('Vision OCR 运行失败，回退 Tesseract：', e.message)
      }
    }
  }
  return cleanText(await recognizeTesseract(image))
}

// 启动时预热：开发模式下提前把 Vision 二进制编译好（打包版已内置，无需编译）。
function prepare() {
  if (process.platform === 'darwin' && !app.isPackaged) buildMacOCR()
}

module.exports = { recognize, cleanText, prepare }
