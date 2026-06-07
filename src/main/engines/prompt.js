'use strict'

const { promptLanguageName } = require('../languages')

const DEFAULT_SYSTEM_PROMPT =
  '你是一名专业翻译引擎。请按规则自动判断用户输入的语言：如果输入是{{primary}}，翻译成{{secondary}}；如果不是{{primary}}，翻译成{{primary}}。\n' +
  '只输出译文，不要添加引号、解释、注释或额外说明。保留原文的换行、段落和基本格式。'

const DEFAULT_DICTIONARY_PROMPT =
  '你是一部双语词典。用户发来一个单词或短语，用 Markdown 格式输出清晰的词条（不要用 ``` 代码块包裹整体）：\n' +
  '- 第一行：**词条** 后跟斜体音标/读音（英文用 IPA，中文用拼音），例如 **apple** */ˈæp.əl/*\n' +
  '- 按词性分组，词性用**粗体**（如 **n.**、**v.**、**adj.**）；释义用{{primary}}，多个义项用有序列表（1. 2. …）\n' +
  '- 例句放在「**例句**」小标题下，用无序列表，每条格式：- *原文例句* — {{primary}}译文\n' +
  '若输入其实是句子而非单词，就直接用{{primary}}翻译、不套词典格式。只输出词条内容本身。'

// 旧版词典提示词（没自定义过的用户会被迁移到上面的 Markdown 新版）
const LEGACY_DICTIONARY_PROMPTS = [
  '你是一部简明双语词典。用户会发来一个单词或短语，请用{{primary}}给出简洁词条：\n' +
    '- 第一行：词条本身（英文附 IPA 音标，中文附拼音）\n' +
    '- 词性 + 释义，可分多个义项，每项一行，用{{primary}}解释\n' +
    '- 1–2 个例句，每句附{{primary}}翻译\n' +
    '若它其实是句子而非单词，就直接翻译成{{primary}}。只输出词条内容，不要前后缀，不要 Markdown 代码块。',
]

const LEGACY_SYSTEM_PROMPTS = [
  '你是一名专业翻译引擎。请将用户输入的文本翻译为 {{target}}。\n' +
    '只输出译文，不要添加引号、解释、注释或额外说明。保留原文的换行、段落和基本格式。',
  '你是一名专业翻译引擎。请自动判断用户输入的语言：如果是中文，翻译成英文；如果不是中文，翻译成简体中文。\n' +
    '只输出译文，不要添加引号、解释、注释或额外说明。保留原文的换行、段落和基本格式。',
]

const TARGET_TOKEN_GLOBAL = /\{\{\s*target\s*\}\}|\{\s*target\s*\}|\$\{\s*target\s*\}/g
const PRIMARY_TOKEN_GLOBAL = /\{\{\s*primary\s*\}\}|\{\s*primary\s*\}|\$\{\s*primary\s*\}/g
const SECONDARY_TOKEN_GLOBAL = /\{\{\s*secondary\s*\}\}|\{\s*secondary\s*\}|\$\{\s*secondary\s*\}/g

function targetName(target) {
  return promptLanguageName(target || 'zh-CN')
}

function buildSystemPrompt(target, template, options = {}) {
  const lang = targetName(target)
  const primary = promptLanguageName(options.primaryLanguage || 'zh-CN')
  const secondary = promptLanguageName(options.secondaryLanguage || 'en')
  const raw = typeof template === 'string' && template.trim() ? template.trim() : DEFAULT_SYSTEM_PROMPT
  return raw
    .replace(TARGET_TOKEN_GLOBAL, lang)
    .replace(PRIMARY_TOKEN_GLOBAL, primary)
    .replace(SECONDARY_TOKEN_GLOBAL, secondary)
}

module.exports = {
  DEFAULT_SYSTEM_PROMPT,
  DEFAULT_DICTIONARY_PROMPT,
  LEGACY_SYSTEM_PROMPTS,
  LEGACY_DICTIONARY_PROMPTS,
  buildSystemPrompt,
  targetName,
}
