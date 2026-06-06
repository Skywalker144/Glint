'use strict'

const { net } = require('electron')
const { readSSE } = require('./sse')

// Anthropic Messages API（和 OpenAI 格式不同：x-api-key 头、system 顶层字段、必须 max_tokens）。

function trimBase(u) {
  return (u || '').replace(/\/+$/, '')
}

async function translate(text, { sys, apiKey, model, baseURL }) {
  if (!apiKey) throw new Error('未配置 API Key')
  if (!model) throw new Error('未选择模型')

  const res = await net.fetch(trimBase(baseURL) + '/messages', {
    method: 'POST',
    headers: {
      'x-api-key': apiKey,
      'anthropic-version': '2023-06-01',
      'content-type': 'application/json',
    },
    body: JSON.stringify({
      model,
      max_tokens: 4096,
      temperature: 0,
      system: sys,
      messages: [{ role: 'user', content: text }],
    }),
  })

  const data = await res.json().catch(() => null)
  if (!res.ok) {
    const msg = (data && data.error && data.error.message) || 'HTTP ' + res.status
    throw new Error(msg)
  }
  const out = (data && data.content && data.content[0] && data.content[0].text) || ''
  const trimmed = out.trim()
  if (!trimmed) throw new Error('模型没有返回译文')
  return trimmed
}

async function listModels({ apiKey, baseURL }) {
  const res = await net.fetch(trimBase(baseURL) + '/models', {
    headers: { 'x-api-key': apiKey, 'anthropic-version': '2023-06-01' },
  })
  if (!res.ok) throw new Error('获取模型列表失败 HTTP ' + res.status)
  const data = await res.json()
  const arr = (data && data.data) || []
  return arr
    .map((m) => m.id)
    .filter(Boolean)
    .sort()
}

// 流式翻译：stream:true，取 content_block_delta 的 delta.text 通过 onDelta 回吐。
async function translateStream(text, { sys, apiKey, model, baseURL, onDelta }) {
  if (!apiKey) throw new Error('未配置 API Key')
  if (!model) throw new Error('未选择模型')

  const res = await net.fetch(trimBase(baseURL) + '/messages', {
    method: 'POST',
    headers: {
      'x-api-key': apiKey,
      'anthropic-version': '2023-06-01',
      'content-type': 'application/json',
    },
    body: JSON.stringify({
      model,
      max_tokens: 4096,
      temperature: 0,
      stream: true,
      system: sys,
      messages: [{ role: 'user', content: text }],
    }),
  })

  if (!res.ok) {
    const data = await res.json().catch(() => null)
    const msg = (data && data.error && data.error.message) || 'HTTP ' + res.status
    throw new Error(msg)
  }

  let full = ''
  await readSSE(res, (payload) => {
    let j
    try {
      j = JSON.parse(payload)
    } catch {
      return
    }
    if (j.type === 'content_block_delta' && j.delta && typeof j.delta.text === 'string') {
      full += j.delta.text
      if (onDelta) onDelta(j.delta.text)
    } else if (j.type === 'error' && j.error) {
      throw new Error(j.error.message || '流式响应错误')
    }
  })

  full = full.trim()
  if (!full) throw new Error('模型没有返回译文')
  return full
}

module.exports = { translate, translateStream, listModels }
