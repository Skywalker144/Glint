'use strict'

// 引擎调度：按服务商 kind 选择具体实现。

const { translateGoogle } = require('./google')
const oai = require('./openai-compat')
const anthropic = require('./anthropic')
const { getProvider } = require('./providers')
const { buildSystemPrompt, DEFAULT_TARGET_PROMPT, targetName } = require('./prompt')

function resolveBaseURL(p, cfg) {
  return p.needsBaseURL ? cfg.baseURL || '' : p.baseURL
}

// 词典模式直接发原词；普通整句翻译时，把「翻成 {target}」的指令贴在原文前一起发给模型。
// 方向（target）已由 pickDirection 算好，光靠系统提示词让弱模型（如 deepseek flash）自判方向时，
// 偶尔会把英文整段原样吐回（echo）——在 user 消息里点明确切目标语言能稳住方向、消除 echo。
function buildUserContent(text, target, dict) {
  if (dict) return text
  return '请把下面的文本翻译成' + targetName(target) + '，只输出译文本身：\n\n' + text
}

// 统一翻译入口，返回 { translated, source }
async function translateWith(engineId, cfg, text, target, options = {}) {
  const p = getProvider(engineId)
  if (!p) throw new Error('未知翻译引擎：' + engineId)

  if (p.kind === 'free') {
    return translateGoogle(text, target) // { translated, source }
  }

  const sys = buildSystemPrompt(target, options.systemPrompt, {
    primaryLanguage: options.primaryLanguage,
    secondaryLanguage: options.secondaryLanguage,
  })
  const source = options.source || 'auto'
  const baseURL = resolveBaseURL(p, cfg)
  const user = buildUserContent(text, target, options.dict)

  if (p.kind === 'anthropic') {
    const translated = await anthropic.translate(user, { sys, apiKey: cfg.apiKey, model: cfg.model, baseURL })
    return { translated, source }
  }

  const translated = await oai.translate(user, {
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

// 流式翻译：openai/anthropic 边生成边通过 onDelta 回吐；google 无流式，一次性回吐。
async function translateStreamWith(engineId, cfg, text, target, options = {}, onDelta) {
  const p = getProvider(engineId)
  if (!p) throw new Error('未知翻译引擎：' + engineId)

  if (p.kind === 'free') {
    const r = await translateGoogle(text, target)
    if (onDelta && r.translated) onDelta(r.translated)
    return r
  }

  // 用户手动指定目标语言时，忽略自定义提示词、直接翻成该目标语言。
  const template = options.forceTarget ? DEFAULT_TARGET_PROMPT : options.systemPrompt
  const sys = buildSystemPrompt(target, template, {
    primaryLanguage: options.primaryLanguage,
    secondaryLanguage: options.secondaryLanguage,
  })
  const source = options.source || 'auto'
  const baseURL = resolveBaseURL(p, cfg)
  const user = buildUserContent(text, target, options.dict)

  if (p.kind === 'anthropic') {
    const translated = await anthropic.translateStream(user, {
      sys,
      apiKey: cfg.apiKey,
      model: cfg.model,
      baseURL,
      onDelta,
      signal: options.signal,
    })
    return { translated, source }
  }

  const translated = await oai.translateStream(user, {
    sys,
    apiKey: cfg.apiKey,
    model: cfg.model,
    baseURL,
    extraHeaders: p.extraHeaders,
    onDelta,
    signal: options.signal,
  })
  return { translated, source }
}

module.exports = { translateWith, translateStreamWith, listModels }
