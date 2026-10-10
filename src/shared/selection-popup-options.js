'use strict'

const SELECTION_POPUP_POSITIONS = Object.freeze([
  { value: 'bottom-right', label: '右下' },
  { value: 'bottom-left', label: '左下' },
  { value: 'top-right', label: '右上' },
  { value: 'top-left', label: '左上' },
])
const SELECTION_POPUP_LIMITS = Object.freeze({ distance: 100, delayMs: 2000 })
const SELECTION_POPUP_DEFAULTS = Object.freeze({ position: 'bottom-right', distance: 12, delayMs: 120 })

function normalizeSelectionPopupOptions(value) {
  const options = { ...SELECTION_POPUP_DEFAULTS }
  if (SELECTION_POPUP_POSITIONS.some(position => position.value === value?.position)) options.position = value.position
  for (const key of Object.keys(SELECTION_POPUP_LIMITS)) {
    if (Number.isFinite(value?.[key])) {
      options[key] = Math.round(Math.max(0, Math.min(value[key], SELECTION_POPUP_LIMITS[key])))
    }
  }
  return options
}

if (typeof module !== 'undefined') module.exports = {
  SELECTION_POPUP_POSITIONS, SELECTION_POPUP_LIMITS, SELECTION_POPUP_DEFAULTS, normalizeSelectionPopupOptions,
}
