'use strict'

// 翻译服务通常会把 snake_case / kebab-case 文件名当作需要原样保留的标识符，
// 例如 meta_game_payoff_heatmap.png 会被直接回显。发送前把文件名主体拆成普通词组，
// 译完后再补回扩展名，让自动方向和手动目标语言都能得到真正的译文。
const TECHNICAL_FILENAME = /^([A-Za-z0-9]+(?:[_-][A-Za-z0-9]+)+)((?:\.[A-Za-z0-9]{1,10})+)$/

function prepareTranslationInput(text) {
  const input = String(text || '')
  const match = input.match(TECHNICAL_FILENAME)
  if (!match || !/[A-Za-z]/.test(match[1])) return { text: input, suffix: '' }

  return {
    text: match[1].replace(/[_-]+/g, ' '),
    suffix: match[2],
  }
}

function restoreTranslationInput(translated, prepared) {
  const body = String(translated || '').trim()
  return body && prepared && prepared.suffix ? body + prepared.suffix : body
}

module.exports = { prepareTranslationInput, restoreTranslationInput }
