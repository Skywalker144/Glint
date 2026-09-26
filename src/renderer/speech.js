'use strict'

window.GlintSpeech = (() => {
  const languages = { 'zh-CN': 'zh-CN', zh: 'zh-CN', en: 'en-US', ja: 'ja-JP', ko: 'ko-KR', fr: 'fr-FR', de: 'de-DE', es: 'es-ES', ru: 'ru-RU', it: 'it-IT', pt: 'pt-PT' }
  let currentAudio = null
  let currentButton = null
  let sequence = 0

  async function speak(text, code, button) {
    text = String(text || '').trim()
    if (!text) return
    if (!code || code === 'auto') {
      code = /[぀-ヿ]/.test(text) ? 'ja' : /[가-힯]/.test(text) ? 'ko' : /[㐀-鿿]/.test(text) ? 'zh-CN' : /[Ѐ-ӿ]/.test(text) ? 'ru' : 'en'
    }
    const token = ++sequence
    currentAudio?.pause()
    currentAudio = null
    currentButton?.classList.remove('speaking')
    window.speechSynthesis?.cancel()
    currentButton = button
    button?.classList.add('speaking')
    const clear = () => { if (token === sequence) button?.classList.remove('speaking') }
    try {
      const response = await window.api.speak(text, code)
      if (token !== sequence) return
      if (response?.ok && response.audio) {
        currentAudio = new Audio('data:audio/mpeg;base64,' + response.audio)
        currentAudio.onended = clear
        currentAudio.onerror = clear
        await currentAudio.play()
        return
      }
    } catch {}
    if (token !== sequence) return
    if (!window.speechSynthesis) return clear()
    const utterance = new SpeechSynthesisUtterance(text)
    utterance.lang = languages[code] || code || 'en-US'
    utterance.onend = clear
    utterance.onerror = clear
    window.speechSynthesis.speak(utterance)
  }

  return { speak }
})()
