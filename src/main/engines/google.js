'use strict'

const { fetchT } = require('./http')

// 免费 Google 翻译接口（非官方，无需 API Key）。
// 用 Electron 的 net.fetch（Chromium 网络栈，复用系统证书）。

async function translateGoogle(text, target) {
  const url =
    'https://translate.googleapis.com/translate_a/single' +
    '?client=gtx&sl=auto&tl=' +
    target +
    '&dt=t&q=' +
    encodeURIComponent(text)

  const res = await fetchT(url, { headers: { 'User-Agent': 'Mozilla/5.0' } })
  if (!res.ok) throw new Error('Google 翻译返回 HTTP ' + res.status)

  const data = await res.json()
  const translated = (data[0] || [])
    .map((seg) => (seg && seg[0]) || '')
    .join('')
    .trim()
  const source = data[2] || 'auto'
  return { translated, source }
}

module.exports = { translateGoogle }
