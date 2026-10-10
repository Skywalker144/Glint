'use strict'

const { normalizeSelectionPopupOptions } = require('../shared/selection-popup-options')

function popupBounds(point, area, options) {
  const size = 40
  const { position, distance } = normalizeSelectionPopupOptions(options)
  const right = point.x + distance
  const left = point.x - size - distance
  const bottom = point.y + distance
  const top = point.y - size - distance
  let x = position.endsWith('right') ? right : left
  let y = position.startsWith('bottom') ? bottom : top
  if (x < area.x || x + size > area.x + area.width) x = position.endsWith('right') ? left : right
  if (y < area.y || y + size > area.y + area.height) y = position.startsWith('bottom') ? top : bottom
  return {
    x: Math.round(Math.max(area.x, Math.min(x, area.x + area.width - size))),
    y: Math.round(Math.max(area.y, Math.min(y, area.y + area.height - size))),
    width: size,
    height: size,
  }
}

class SelectionPopupState {
  constructor(view) {
    this.view = view
    this.enabled = false
    this.options = normalizeSelectionPopupOptions()
    this.text = ''
    this.bounds = null
  }

  setEnabled(enabled) {
    this.enabled = enabled
    if (!enabled) this.dismiss()
  }

  setOptions(value) {
    const options = normalizeSelectionPopupOptions(value)
    if (Object.keys(options).some(key => options[key] !== this.options[key])) this.dismiss()
    this.options = options
  }

  handle(event) {
    if (!this.enabled) return
    if (event.type === 'pointer' || event.type === 'focus') {
      const b = this.bounds
      if (b && event.x >= b.x && event.x < b.x + b.width && event.y >= b.y && event.y < b.y + b.height) return
      this.dismiss()
    } else if (event.type === 'dismiss') {
      this.dismiss()
    } else if (event.type === 'selection') {
      this.dismiss()
      if (this.view.isBlocked() || typeof event.text !== 'string' || !event.text.trim() ||
          !Number.isFinite(event.x) || !Number.isFinite(event.y)) return
      this.text = event.text.trim()
      this.bounds = popupBounds(event, this.view.getWorkArea(event), this.options)
      this.view.show(this.bounds)
    }
  }

  dismiss() {
    this.text = ''
    this.bounds = null
    this.view.hide()
  }

  activate() {
    const text = this.text
    this.dismiss()
    if (this.enabled && text && !this.view.isBlocked(true)) this.view.translate(text)
  }
}

module.exports = { SelectionPopupState, popupBounds }
