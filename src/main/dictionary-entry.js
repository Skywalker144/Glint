'use strict'

const { isLanguageCode } = require('./languages')

function dictionaryEntry(translated, options) {
  if (!options.dict || typeof translated !== 'string' || !isLanguageCode(options.secondaryLanguage)) return null
  const match = translated.trim().match(/^\*\*([^*\n]+)\*\*[^\n]*\r?\n\s*(\S[\s\S]*)$/u)
  if (!match) return null
  const headword = match[1].normalize('NFC').trim().replace(/\s+/gu, ' ')
  if (!headword || /[<>\[\]`]/u.test(headword)) return null
  const language = options.secondaryLanguage
  return {
    id: JSON.stringify([language, headword]),
    headword,
    language,
    definitionLanguage: options.primaryLanguage,
    translated,
  }
}

module.exports = { dictionaryEntry }
