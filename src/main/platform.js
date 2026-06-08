'use strict'

// 平台相关能力都收敛在这个文件里。以后要支持 Windows / Linux，主要改这里。

const { clipboard } = require('electron')
const { exec } = require('child_process')

function delay(ms) {
  return new Promise((resolve) => setTimeout(resolve, ms))
}

// 模拟一次「复制」按键（Cmd+C / Ctrl+C）。
function simulateCopy() {
  return new Promise((resolve) => {
    let cmd
    if (process.platform === 'darwin') {
      cmd = `osascript -e 'tell application "System Events" to keystroke "c" using command down'`
    } else if (process.platform === 'win32') {
      cmd = `powershell -NoProfile -Command "$w=New-Object -ComObject wscript.shell;$w.SendKeys('^c')"`
    } else {
      cmd = 'xdotool key --clearmodifiers ctrl+c'
    }
    exec(cmd, () => resolve())
  })
}

// 划词取词：保存当前剪贴板 -> 触发复制 -> 读取选中的文字 -> 还原剪贴板。
async function getSelectedText() {
  const previous = clipboard.readText()
  clipboard.writeText('') // 先清空，便于判断复制是否真的发生

  await simulateCopy()

  // 轮询等待目标 App 把选中内容写进剪贴板：一有内容就立刻返回（响应快的 App 往往几十毫秒
  // 就好），最多等 ~700ms 容忍慢的 App。比之前固定 sleep 220ms 稳——固定等待在浏览器 /
  // Electron 等较慢的 App 上偶发来不及，读到空 → 误报「没检测到选中的文字」。
  let selected = ''
  for (let i = 0; i < 28; i++) {
    await delay(25)
    selected = clipboard.readText()
    if (selected.trim()) break
  }

  // 还原用户原本的剪贴板内容
  if (previous) clipboard.writeText(previous)
  else clipboard.clear()

  return selected.trim()
}

module.exports = { getSelectedText }
