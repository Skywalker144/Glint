'use strict'

// 在线朗读：Google 免费 TTS（非官方），返回 MP3。神经网络音质，免安装、跨平台。
// 走 net.fetch（复用 defaultSession，吃用户配的代理，和免费 Google 翻译同一套网络）。
// 失败时由渲染层回退到本地 Web Speech 语音。

const { net } = require('electron')
const { ttsLang, splitText } = require('./tts-util')

// 用和免费翻译相同的 googleapis 主机，网络可达性一致（受限网络下经代理也能通）。
const TTS_HOST = 'https://translate.googleapis.com/translate_tts'

async function fetchPart(text, tl, idx, total) {
  const url =
    TTS_HOST +
    '?ie=UTF-8&client=tw-ob' +
    '&tl=' + encodeURIComponent(tl) +
    '&total=' + total + '&idx=' + idx +
    '&textlen=' + text.length +
    '&q=' + encodeURIComponent(text)
  const ac = new AbortController()
  const timer = setTimeout(() => ac.abort(), 10000)
  try {
    const res = await net.fetch(url, {
      signal: ac.signal,
      headers: { 'User-Agent': 'Mozilla/5.0', Referer: 'https://translate.google.com/' },
    })
    if (!res.ok) throw new Error('TTS HTTP ' + res.status)
    return Buffer.from(await res.arrayBuffer())
  } finally {
    clearTimeout(timer)
  }
}

// 取文本的朗读音频，返回拼接好的 MP3 的 base64（多段直接拼字节，播放器能连放）。
async function speak(text, code) {
  text = (text || '').trim()
  if (!text) return ''
  const tl = ttsLang(code)
  const parts = splitText(text).slice(0, 5) // 最多 5 段（~950 字），再长就只读前面
  const total = parts.length
  const bufs = []
  for (let i = 0; i < parts.length; i++) {
    bufs.push(await fetchPart(parts[i], tl, i, total))
  }
  return Buffer.concat(bufs).toString('base64')
}

module.exports = { speak }
