'use strict'

// 引擎调度：按服务商 kind 选择具体实现。

const { translateGoogle } = require('./google')
const oai = require('./openai-compat')
const anthropic = require('./anthropic')
const { getProvider } = require('./providers')

const TARGET_NAME = {
  en: 'English',
  'zh-CN': 'Simplified Chinese (简体中文)',
}

function systemPrompt(target) {
  const lang = TARGET_NAME[target] || TARGET_NAME['zh-CN']
  return (
    `You are a professional translation engine. Translate the user's text into ${lang}. ` +
    'Output ONLY the translated text — no quotes, no explanations, no notes. Preserve line breaks and formatting.'
  )
}

function resolveBaseURL(p, cfg) {
  return p.needsBaseURL ? cfg.baseURL || '' : p.baseURL
}

// 统一翻译入口，返回 { translated, source }
async function translateWith(engineId, cfg, text, target) {
  const p = getProvider(engineId)
  if (!p) throw new Error('未知翻译引擎：' + engineId)

  if (p.kind === 'free') {
    return translateGoogle(text, target) // { translated, source }
  }

  const sys = systemPrompt(target)
  const source = target === 'en' ? 'zh-CN' : 'auto' // AI 拿不到精确源语言，按方向粗标
  const baseURL = resolveBaseURL(p, cfg)

  if (p.kind === 'anthropic') {
    const translated = await anthropic.translate(text, { sys, apiKey: cfg.apiKey, model: cfg.model, baseURL })
    return { translated, source }
  }

  const translated = await oai.translate(text, {
    sys,
    apiKey: cfg.apiKey,
    model: cfg.model,
    baseURL,
    extraHeaders: p.extraHeaders,
  })
  return { translated, source }
}

// 拉取某服务商的模型列表
async function listModels(engineId, cfg) {
  const p = getProvider(engineId)
  if (!p || p.kind === 'free') return []
  const baseURL = resolveBaseURL(p, cfg)
  if (p.kind === 'anthropic') return anthropic.listModels({ apiKey: cfg.apiKey, baseURL })
  return oai.listModels({ apiKey: cfg.apiKey, baseURL })
}

module.exports = { translateWith, listModels }
