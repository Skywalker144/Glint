'use strict'

const { fetchT, fetchStream } = require('./http')
const { readSSE } = require('./sse')

// OpenAI 兼容引擎：OpenAI / DeepSeek / Gemini(OpenAI 端点) / OpenRouter / 自定义 都走这里。

function trimBase(u) {
  return (u || '').replace(/\/+$/, '')
}

async function translate(text, { sys, apiKey, model, baseURL, extraHeaders }) {
  if (!baseURL) throw new Error('缺少 Base URL')
  if (!apiKey) throw new Error('未配置 API Key')
  if (!model) throw new Error('未选择模型')

  const res = await fetchT(trimBase(baseURL) + '/chat/completions', {
    method: 'POST',
    headers: {
      Authorization: 'Bearer ' + apiKey,
      'Content-Type': 'application/json',
      ...(extraHeaders || {}),
    },
    body: JSON.stringify({
      model,
      temperature: 0,
      messages: [
        { role: 'system', content: sys },
        { role: 'user', content: text },
      ],
    }),
  })

  const data = await res.json().catch(() => null)
  if (!res.ok) {
    const e = data && data.error
    const msg = (e && (e.message || e)) || 'HTTP ' + res.status
    throw new Error(typeof msg === 'string' ? msg : JSON.stringify(msg))
  }
  const out =
    (data && data.choices && data.choices[0] && data.choices[0].message && data.choices[0].message.content) || ''
  const trimmed = out.trim()
  if (!trimmed) throw new Error('模型没有返回译文')
  return trimmed
}

async function listModels({ apiKey, baseURL }) {
  if (!baseURL) throw new Error('缺少 Base URL')
  const headers = {}
  if (apiKey) headers.Authorization = 'Bearer ' + apiKey
  const res = await fetchT(trimBase(baseURL) + '/models', { headers })
  if (!res.ok) throw new Error('获取模型列表失败 HTTP ' + res.status)
  const data = await res.json()
  const arr = (data && data.data) || []
  return arr
    .map((m) => m.id)
    .filter(Boolean)
    .sort()
}

// 流式翻译：stream:true，逐块取 choices[0].delta.content 通过 onDelta 回吐。
async function translateStream(text, { sys, apiKey, model, baseURL, extraHeaders, onDelta, signal }) {
  if (!baseURL) throw new Error('缺少 Base URL')
  if (!apiKey) throw new Error('未配置 API Key')
  if (!model) throw new Error('未选择模型')

  const { res, bump, done } = await fetchStream(trimBase(baseURL) + '/chat/completions', {
    method: 'POST',
    signal,
    headers: {
      Authorization: 'Bearer ' + apiKey,
      'Content-Type': 'application/json',
      ...(extraHeaders || {}),
    },
    body: JSON.stringify({
      model,
      temperature: 0,
      stream: true,
      messages: [
        { role: 'system', content: sys },
        { role: 'user', content: text },
      ],
    }),
  })

  try {
    if (!res.ok) {
      const data = await res.json().catch(() => null)
      const e = data && data.error
      const msg = (e && (e.message || e)) || 'HTTP ' + res.status
      throw new Error(typeof msg === 'string' ? msg : JSON.stringify(msg))
    }

    let full = ''
    await readSSE(
      res,
      (payload) => {
        if (payload === '[DONE]') return
        let j
        try {
          j = JSON.parse(payload)
        } catch {
          return
        }
        const d = j.choices && j.choices[0] && j.choices[0].delta && j.choices[0].delta.content
        if (d) {
          full += d
          if (onDelta) onDelta(d)
        }
      },
      bump
    )

    full = full.trim()
    if (!full) throw new Error('模型没有返回译文')
    return full
  } finally {
    done()
  }
}

module.exports = { translate, translateStream, listModels }
