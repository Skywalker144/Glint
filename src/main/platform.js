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

  // 发 ⌘C 前先等一小会儿：⌥E 这类全局快捷键触发时，用户的 Option 等修饰键往往还按着，
  // 此刻合成的 ⌘C 会和残留的 ⌥ 叠成 ⌥⌘C，多数 App 不识别为复制 → 取词失败（时灵时不灵，
  // 还可能误触 ⌥⌘C 这类别的快捷键）。等 ~90ms 让修饰键先抬起，再发第一次复制。
  await delay(90)
  await simulateCopy()

  // 轮询等目标 App 把选中内容写进剪贴板：一有内容就立刻返回（快的 App 几十毫秒就好）。
  // 过了 ~200ms 还是空，就补发一次 ⌘C——这时修饰键必已抬起，覆盖「第一发因修饰键残留 /
  // 抢焦点没生效」与「App 较慢」两种情况。比固定 sleep 稳得多。
  let selected = ''
  let retried = false
  for (let i = 0; i < 30; i++) {
    await delay(25)
    selected = clipboard.readText()
    if (selected.trim()) break
    if (i === 8 && !retried) {
      retried = true
      await simulateCopy()
    }
  }

  // 还原用户原本的剪贴板内容
  if (previous) clipboard.writeText(previous)
  else clipboard.clear()

  return selected.trim()
}

module.exports = { getSelectedText }
