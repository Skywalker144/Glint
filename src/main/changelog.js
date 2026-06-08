'use strict'

// 更新日志（面向用户，最新在上）。关于页渲染本数组，发布新版时同步在此加一条。
const CHANGELOG = [
  {
    version: '0.2.8',
    date: '2026-06-08',
    items: [
      '词典查变形词时自动显示原形（ran → run、dogs → dog）',
      '全大写的普通词转小写（APPLE → apple），专有名词 / 国家名保留大写',
    ],
  },
  {
    version: '0.2.7',
    date: '2026-06-08',
    items: ['翻译窗口可横向拖宽，并记住上次的宽度'],
  },
  {
    version: '0.2.6',
    date: '2026-06-07',
    items: [
      '设置页改版：拨动开关、分组卡片、侧边栏图标',
      '单词词典输出更精简',
      '长文本翻译时输入框高度自适应',
    ],
  },
  {
    version: '0.2.5',
    date: '2026-06-07',
    items: ['查中文词改为给出英文词头 + 音标（修正之前方向反了的问题）'],
  },
  {
    version: '0.2.4',
    date: '2026-06-07',
    items: ['内置自动更新：发现新版后台下载，一键「重启以更新」'],
  },
  {
    version: '0.2.3',
    date: '2026-06-07',
    items: [
      '单词词典支持 Markdown（音标 / 释义 / 例句）',
      '报错提示更易懂，请求加超时保护',
    ],
  },
  {
    version: '0.2.2',
    date: '2026-06-07',
    items: [
      '网络代理（支持填 Clash 端口）',
      'Markdown 与数学公式渲染',
      '⌥R 翻译剪贴板、检查更新',
    ],
  },
  {
    version: '0.2.1',
    date: '2026-06-07',
    items: ['改为菜单栏常驻，不再占用 Dock；新增应用图标'],
  },
  {
    version: '0.2.0',
    date: '2026-06-07',
    items: [
      '首个版本：划词 / 截图 / 输入翻译',
      '接入 OpenAI / DeepSeek / Claude / Gemini / OpenRouter 与免费 Google',
      'AI 流式输出、单词词典、翻译历史、钉住窗口',
    ],
  },
]

module.exports = { CHANGELOG }
