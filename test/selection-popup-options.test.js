'use strict'

const { test } = require('node:test')
const assert = require('node:assert/strict')
const { SELECTION_POPUP_DEFAULTS, normalizeSelectionPopupOptions } = require('../src/shared/selection-popup-options')

test('missing and invalid options use shared defaults', () => {
  for (const value of [undefined, null, {}, { position: 'invalid', distance: '20', delayMs: NaN }]) {
    assert.deepEqual(normalizeSelectionPopupOptions(value), SELECTION_POPUP_DEFAULTS)
  }
})

test('options preserve zero and valid preferences and constrain numeric ranges', () => {
  assert.deepEqual(normalizeSelectionPopupOptions({ position: 'top-left', distance: 0, delayMs: 0 }),
    { position: 'top-left', distance: 0, delayMs: 0 })
  assert.deepEqual(normalizeSelectionPopupOptions({ position: 'bottom-left', distance: 200, delayMs: -5 }),
    { position: 'bottom-left', distance: 100, delayMs: 0 })
  assert.deepEqual(normalizeSelectionPopupOptions({ distance: -5, delayMs: 3000 }),
    { position: 'bottom-right', distance: 0, delayMs: 2000 })
  assert.deepEqual(normalizeSelectionPopupOptions({ distance: 12.6, delayMs: 150.3 }),
    { position: 'bottom-right', distance: 13, delayMs: 150 })
})
