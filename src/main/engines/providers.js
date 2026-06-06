'use strict'

// 翻译服务商注册表。kind 决定调用方式：
//   'free'      免费 Google 翻译（无需 Key）
//   'openai'    OpenAI 兼容的 /chat/completions（OpenAI / DeepSeek / Gemini / OpenRouter / 自定义）
//   'anthropic' Anthropic Messages API
// 纯数据，渲染层也会拿去渲染设置界面。

const PROVIDERS = [
  {
    id: 'google',
    label: '免费 Google 翻译',
    kind: 'free',
    desc: '开箱即用、无需 API Key，质量一般',
    needsKey: false,
  },
  {
    id: 'openai',
    label: 'OpenAI',
    kind: 'openai',
    baseURL: 'https://api.openai.com/v1',
    defaultModel: 'gpt-4o-mini',
    models: ['gpt-4o-mini', 'gpt-4o', 'o4-mini'],
    keyHint: 'sk-...',
    keyURL: 'https://platform.openai.com/api-keys',
    needsKey: true,
  },
  {
    id: 'deepseek',
    label: 'DeepSeek',
    kind: 'openai',
    baseURL: 'https://api.deepseek.com/v1',
    defaultModel: 'deepseek-chat',
    models: ['deepseek-chat', 'deepseek-reasoner'],
    keyHint: 'sk-...',
    keyURL: 'https://platform.deepseek.com/api_keys',
    needsKey: true,
  },
  {
    id: 'anthropic',
    label: 'Anthropic Claude',
    kind: 'anthropic',
    baseURL: 'https://api.anthropic.com/v1',
    defaultModel: 'claude-3-5-haiku-latest',
    models: ['claude-3-5-haiku-latest', 'claude-3-5-sonnet-latest'],
    keyHint: 'sk-ant-...',
    keyURL: 'https://console.anthropic.com/settings/keys',
    needsKey: true,
  },
  {
    id: 'gemini',
    label: 'Google Gemini',
    kind: 'openai',
    baseURL: 'https://generativelanguage.googleapis.com/v1beta/openai',
    defaultModel: 'gemini-2.0-flash',
    models: ['gemini-2.0-flash', 'gemini-2.0-flash-lite', 'gemini-1.5-flash'],
    keyHint: 'AIza...',
    keyURL: 'https://aistudio.google.com/apikey',
    needsKey: true,
  },
  {
    id: 'openrouter',
    label: 'OpenRouter',
    kind: 'openai',
    baseURL: 'https://openrouter.ai/api/v1',
    defaultModel: 'openai/gpt-4o-mini',
    models: [],
    modelsPublic: true, // /models 公开，无需 Key
    extraHeaders: { 'X-Title': 'Translator' },
    keyHint: 'sk-or-...',
    keyURL: 'https://openrouter.ai/keys',
    needsKey: true,
  },
  {
    id: 'custom',
    label: '自定义（OpenAI 兼容）',
    kind: 'openai',
    baseURL: '',
    defaultModel: '',
    models: [],
    needsBaseURL: true,
    desc: '任意 OpenAI 兼容服务：Groq / xAI / Mistral / 本地 Ollama 等',
    keyHint: 'sk-...',
    needsKey: true,
  },
]

const BY_ID = Object.fromEntries(PROVIDERS.map((p) => [p.id, p]))

function getProvider(id) {
  return BY_ID[id] || null
}

function listProviders() {
  return PROVIDERS
}

module.exports = { PROVIDERS, getProvider, listProviders }
