'use strict'

// 把（AI）译文里的 Markdown + LaTeX 公式渲染成安全 HTML。
// html:false 让 AI 输出里的裸 HTML 被转义（防 XSS）；texmath + katex 渲染 $...$ / $$...$$。

const MarkdownIt = require('markdown-it')
const texmath = require('markdown-it-texmath')
const katex = require('katex')

const md = MarkdownIt({ html: false, linkify: true, breaks: true }).use(texmath, {
  engine: katex,
  delimiters: 'dollars',
  katexOptions: { throwOnError: false },
})

function escapeHtml(s) {
  return String(s || '').replace(/[&<>]/g, (c) => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;' }[c]))
}

function renderMarkdown(text) {
  try {
    return md.render(text || '')
  } catch (e) {
    return '<p>' + escapeHtml(text) + '</p>' // 渲染异常兜底为纯文本
  }
}

module.exports = { renderMarkdown }
