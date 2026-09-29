'use strict'

function scriptWeights(text) {
  const t = text || ''
  return {
    han: (t.match(/\p{Script=Han}/gu) || []).length,
    kana: (t.match(/[\p{Script=Hiragana}\p{Script=Katakana}]/gu) || []).length,
    hangul: (t.match(/\p{Script=Hangul}/gu) || []).length,
    cyrillic: (t.match(/\p{Script=Cyrillic}/gu) || []).length,
    latin: (t.match(/[A-Za-zÀ-ÖØ-öø-ÿ]+/g) || []).length,
  }
}

function hasMixedLanguageScripts(text) {
  const w = scriptWeights(text)
  const groups = [w.kana || (w.han && !w.hangul), w.hangul, w.cyrillic, w.latin]
  return groups.filter(Boolean).length > 1
}

if (typeof module !== 'undefined') module.exports = { scriptWeights, hasMixedLanguageScripts }
