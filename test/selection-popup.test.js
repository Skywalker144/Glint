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

test('window focus during an icon click preserves the selection for activation', () => {
  const f = fixture()
  f.state.setEnabled(true)
  f.state.handle({ type: 'selection', text: 'new selection', x: 100, y: 100 })
  const point = { x: 132, y: 132 }
  f.state.handle({ type: 'focus', ...point })
  f.state.activate()
  assert.deepEqual(f.translated, ['new selection'])
})

test('activation checks allow the translator to regain focus after caching a selection', () => {
  const f = fixture()
  let translatorFocused = false
  f.state.view.isBlocked = activating => translatorFocused && !activating
  f.state.setEnabled(true)
  f.state.handle({ type: 'selection', text: 'first selection', x: 100, y: 100 })
  f.state.activate()
  translatorFocused = false
  f.state.handle({ type: 'selection', text: 'second selection', x: 100, y: 100 })
  translatorFocused = true
  f.state.handle({ type: 'focus', x: 132, y: 132 })
  f.state.activate()
  f.state.activate()
  assert.deepEqual(f.translated, ['first selection', 'second selection'])
  f.state.handle({ type: 'selection', text: 'inside Glint', x: 100, y: 100 })
  f.state.activate()
  assert.deepEqual(f.translated, ['first selection', 'second selection'])
})

test('window focus away from the icon discards the selection', () => {
  const f = fixture()
  f.state.setEnabled(true)
  f.state.handle({ type: 'selection', text: 'stale selection', x: 100, y: 100 })
  f.state.handle({ type: 'focus', x: 0, y: 0 })
  f.state.activate()
  assert.deepEqual(f.translated, [])
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

test('configured position and distance place the icon on each side of the release point', () => {
  const point = { x: 400, y: 250 }
  const area = { x: 0, y: 0, width: 1440, height: 900 }
  for (const [position, x, y] of [
    ['bottom-right', 420, 270], ['bottom-left', 340, 270],
    ['top-right', 420, 190], ['top-left', 340, 190],
  ]) {
    assert.deepEqual(popupBounds(point, area, { position, distance: 20 }), { x, y, width: 40, height: 40 })
  }
  assert.deepEqual(popupBounds(point, area, { position: 'top-left', distance: 0 }),
    { x: 360, y: 210, width: 40, height: 40 })
})

test('each preferred position flips away from display edges before clamping', () => {
  const area = { x: -500, y: -400, width: 500, height: 400 }
  for (const position of ['bottom-right', 'bottom-left', 'top-right', 'top-left']) {
    for (const point of [{ x: -495, y: -395 }, { x: -5, y: -5 }]) {
      const b = popupBounds(point, area, { position, distance: 100 })
      assert.ok(b.x >= area.x && b.y >= area.y)
      assert.ok(b.x + b.width <= 0 && b.y + b.height <= 0)
      assert.ok(point.x < b.x || point.x >= b.x + b.width)
      assert.ok(point.y < b.y || point.y >= b.y + b.height)
    }
  }
})

test('changing options dismisses cached selection and applies placement to the next selection', () => {
  const f = fixture()
  f.state.setEnabled(true)
  f.state.handle({ type: 'selection', text: 'old', x: 400, y: 250 })
  f.state.setOptions({ position: 'top-left', distance: 30, delayMs: 500 })
  f.state.activate()
  assert.deepEqual(f.translated, [])
  f.state.handle({ type: 'selection', text: 'new', x: 400, y: 250 })
  assert.deepEqual(f.shown.at(-1), { x: 330, y: 180, width: 40, height: 40 })
  f.state.setOptions({ position: 'top-left', distance: 30, delayMs: 500 })
  f.state.activate()
  assert.deepEqual(f.translated, ['new'])
})
