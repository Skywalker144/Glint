// 把 KaTeX 的 css + 字体复制到渲染层 vendor 目录（postinstall 自动跑；vendor 不入 git，打包时由 files 带上）。
const fs = require('fs')
const path = require('path')

const root = path.join(__dirname, '..')
const src = path.join(root, 'node_modules', 'katex', 'dist')
const dst = path.join(root, 'src', 'renderer', 'vendor', 'katex')

try {
  fs.mkdirSync(dst, { recursive: true })
  fs.copyFileSync(path.join(src, 'katex.min.css'), path.join(dst, 'katex.min.css'))
  fs.cpSync(path.join(src, 'fonts'), path.join(dst, 'fonts'), { recursive: true })
  console.log('copy-vendor: katex css/fonts -> src/renderer/vendor/katex')
} catch (e) {
  console.warn('copy-vendor 跳过（katex 未安装？）：', e.message)
}
