'use strict'

const { test } = require('node:test')
const assert = require('node:assert/strict')
const { SelectionPopupState, popupBounds } = require('../src/main/selection-popup-state')

function fixture() {
  const shown = []
  const translated = []
  let blocked = false
  let hidden = 0
  const state = new SelectionPopupState({
    show: bounds => shown.push(bounds),
    hide: () => hidden++,
    translate: text => translated.push(text),
    isBlocked: () => blocked,
    getWorkArea: () => ({ x: 0, y: 0, width: 1440, height: 900 }),
  })
  return { state, shown, translated, hidden: () => hidden, block: () => { blocked = true } }
}

test('selection is cached until the icon is clicked, without translating on selection', () => {
  const f = fixture()
  f.state.setEnabled(true)
  f.state.handle({ type: 'selection', text: '  selected paragraph  ', x: 400, y: 250 })
  assert.equal(f.shown.length, 1)
  assert.deepEqual(f.translated, [])
  f.state.handle({ type: 'pointer', x: f.shown[0].x + 12, y: f.shown[0].y + 12 })
  f.state.activate()
  f.state.activate()
  assert.deepEqual(f.translated, ['selected paragraph'])
  assert.equal(f.state.text, '')
})

test('clicking elsewhere, scrolling, typing and app switching discard cached text', () => {
  for (const event of [{ type: 'pointer', x: 0, y: 0 }, { type: 'dismiss' }]) {
    const f = fixture()
    f.state.setEnabled(true)
    f.state.handle({ type: 'selection', text: 'hello', x: 400, y: 250 })
    f.state.handle(event)
    f.state.activate()
    assert.deepEqual(f.translated, [])
    assert.ok(f.hidden() > 0)
  }
})

test('disabled and blocked states never show or activate the popup', () => {
  const f = fixture()
  const event = { type: 'selection', text: 'hello', x: 100, y: 100 }
  f.state.handle(event)
  assert.equal(f.shown.length, 0)
  f.state.setEnabled(true)
  f.state.handle(event)
  f.state.setEnabled(false)
  f.state.activate()
  f.state.setEnabled(true)
  f.block()
  f.state.handle(event)
  f.state.activate()
  assert.equal(f.shown.length, 1)
  assert.deepEqual(f.translated, [])
})

test('new selections replace old text and invalid or empty selections dismiss', () => {
  const f = fixture()
  f.state.setEnabled(true)
  f.state.handle({ type: 'selection', text: 'old', x: 100, y: 100 })
  f.state.handle({ type: 'selection', text: 'new', x: 100, y: 100 })
  f.state.activate()
  assert.deepEqual(f.translated, ['new'])
  for (const event of [
    { type: 'selection', text: '', x: 100, y: 100 },
    { type: 'selection', text: 'hello', x: NaN, y: 100 },
    { type: 'selection', text: 1, x: 100, y: 100 },
  ]) {
    f.state.handle(event)
    assert.equal(f.state.text, '')
  }
})

test('opening another Glint window before activation prevents a cached translation', () => {
  const f = fixture()
  f.state.setEnabled(true)
  f.state.handle({ type: 'selection', text: 'hello', x: 100, y: 100 })
  f.block()
  f.state.activate()
  assert.deepEqual(f.translated, [])
  assert.equal(f.state.text, '')
})

test('icon stays inside the current display including negative screen coordinates', () => {
  assert.deepEqual(popupBounds({ x: 100, y: 100 }, { x: 0, y: 0, width: 1440, height: 900 }),
    { x: 112, y: 112, width: 40, height: 40 })
  for (const area of [
    { x: 0, y: 25, width: 1440, height: 875 },
    { x: -1920, y: -1080, width: 1920, height: 1080 },
  ]) {
    for (const point of [area, { x: area.x + area.width, y: area.y + area.height }]) {
      const b = popupBounds(point, area)
      assert.ok(b.x >= area.x && b.y >= area.y)
      assert.ok(b.x + b.width <= area.x + area.width)
      assert.ok(b.y + b.height <= area.y + area.height)
    }
  }
})
