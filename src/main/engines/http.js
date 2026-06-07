'use strict'

const { net } = require('electron')

// 带总超时的 net.fetch（非流式）。
async function fetchT(url, options = {}, ms = 25000) {
  const ac = new AbortController()
  const timer = setTimeout(() => ac.abort(), ms)
  try {
    return await net.fetch(url, { ...options, signal: ac.signal })
  } finally {
    clearTimeout(timer)
  }
}

// 流式 fetch：空闲超时——每收到数据用 bump() 重置，超过 idleMs 没动静就中止。
// 返回 { res, bump, done }；调用方在读流时 bump、结束时 done()。
async function fetchStream(url, options = {}, idleMs = 30000) {
  const ac = new AbortController()
  let timer = setTimeout(() => ac.abort(), idleMs)
  const bump = () => {
    clearTimeout(timer)
    timer = setTimeout(() => ac.abort(), idleMs)
  }
  const done = () => clearTimeout(timer)
  try {
    const res = await net.fetch(url, { ...options, signal: ac.signal })
    return { res, bump, done }
  } catch (e) {
    clearTimeout(timer)
    throw e
  }
}

module.exports = { fetchT, fetchStream }
