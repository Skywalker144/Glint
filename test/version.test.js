'use strict'

const { test } = require('node:test')
const assert = require('node:assert')
const { isNewer } = require('../src/main/version')

test('isNewer: 基本比较', () => {
  assert.ok(isNewer('0.2.9', '0.2.8'))
  assert.ok(isNewer('0.3.0', '0.2.9'))
  assert.ok(isNewer('1.0.0', '0.9.9'))
  assert.ok(!isNewer('0.2.8', '0.2.8'))
  assert.ok(!isNewer('0.2.7', '0.2.8'))
})

test('isNewer: 忽略 v 前缀', () => {
  assert.ok(isNewer('v0.2.9', 'v0.2.8'))
  assert.ok(!isNewer('v0.2.8', '0.2.8'))
})

test('isNewer: 忽略预发布后缀', () => {
  assert.ok(!isNewer('0.2.8-beta', '0.2.8'))
  assert.ok(isNewer('0.2.9-rc1', '0.2.8'))
})

test('isNewer: 段数不同', () => {
  assert.ok(isNewer('0.2.8.1', '0.2.8'))
  assert.ok(!isNewer('0.2.8', '0.2.8.1'))
})
