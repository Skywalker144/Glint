'use strict'

const settings = require('./settings')
const { translateWith } = require('./engines')

// 自动决定翻译方向：只有「是中文」才翻成英文，其余语言一律翻成中文。
//   - 含汉字、且不含日文假名 / 韩文谚文  -> 判定为中文 -> 翻成英文
//   - 其它（英文、日文、韩文、法文…）    -> 翻成中文
function pickTarget(text) {
  const hasHan = /[㐀-鿿豈-﫿]/.test(text) // 汉字
  const hasKana = /[぀-ヿ]/.test(text) // 日文假名
  const hasHangul = /[ᄀ-ᇿ㄰-㆏가-힯]/.test(text) // 韩文谚文
  return hasHan && !hasKana && !hasHangul ? 'en' : 'zh-CN'
}

// 统一入口：根据设置里选中的服务商分发。返回 {original, translated, source, target, engine}
async function translate(text) {
  text = (text || '').trim()
  if (!text) return { original: '', translated: '', source: '', target: '', engine: '' }

  const target = pickTarget(text)
  const s = settings.get()
  const engineId = s.engine || 'google'
  const cfg = (s.providers && s.providers[engineId]) || {}

  const { translated, source } = await translateWith(engineId, cfg, text, target)
  return { original: text, translated, source, target, engine: engineId }
}

module.exports = { translate, pickTarget }
