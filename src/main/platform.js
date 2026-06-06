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
  await delay(220) // 等系统把选中内容写入剪贴板

  const selected = clipboard.readText()

  // 还原用户原本的剪贴板内容
  if (previous) clipboard.writeText(previous)
  else clipboard.clear()

  return selected.trim()
}

module.exports = { getSelectedText }
