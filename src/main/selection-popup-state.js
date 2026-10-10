'use strict'

function popupBounds(point, area) {
  const size = 40
  const x = point.x + 12 + size <= area.x + area.width ? point.x + 12 : point.x - size - 12
  const y = point.y + 12 + size <= area.y + area.height ? point.y + 12 : point.y - size - 12
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
    this.text = ''
    this.bounds = null
  }

  setEnabled(enabled) {
    this.enabled = enabled
    if (!enabled) this.dismiss()
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
      this.bounds = popupBounds(event, this.view.getWorkArea(event))
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
