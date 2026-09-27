'use strict'

const shot = document.getElementById('shot')
const dark = document.getElementById('dark')
const sel = document.getElementById('sel')

let startX = 0
let startY = 0
let dragging = false

window.api.onCaptureInit(({ dataURL }) => {
  shot.src = dataURL
})

function rectFrom(e) {
  return {
    x: Math.min(e.clientX, startX),
    y: Math.min(e.clientY, startY),
    width: Math.abs(e.clientX - startX),
    height: Math.abs(e.clientY - startY),
  }
}

function drawSel(r) {
  sel.style.left = r.x + 'px'
  sel.style.top = r.y + 'px'
  sel.style.width = r.width + 'px'
  sel.style.height = r.height + 'px'
  sel.style.display = 'block'
}

document.addEventListener('mousedown', (e) => {
  dragging = true
  startX = e.clientX
  startY = e.clientY
  dark.style.display = 'none' // 改由选框投影压暗
  drawSel({ x: startX, y: startY, width: 0, height: 0 })
})

document.addEventListener('mousemove', (e) => {
  if (!dragging) return
  drawSel(rectFrom(e))
})

document.addEventListener('mouseup', (e) => {
  if (!dragging) return
  dragging = false
  const r = rectFrom(e)
  if (r.width < 3 || r.height < 3) {
    window.api.captureCancel()
    return
  }
  window.api.captureSelect(r)
})

document.addEventListener('keydown', (e) => {
  if (e.key === 'Escape') window.api.captureCancel()
})
