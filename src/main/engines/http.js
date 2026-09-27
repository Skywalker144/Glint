'use strict'

const { net } = require('electron')

// 把外部 signal（如用户点「停止」）接到内部 AbortController：任一触发都中止。
function linkSignal(ac, external) {
  if (!external) return
  if (external.aborted) ac.abort()
  else external.addEventListener('abort', () => ac.abort(), { once: true })
}

// 带总超时的 net.fetch（非流式）。options.signal 为可选的外部中断信号。
async function fetchT(url, options = {}, ms = 25000) {
  const ac = new AbortController()
  const timer = setTimeout(() => ac.abort(), ms)
  const { signal: external, ...rest } = options
  linkSignal(ac, external)
  try {
    return await net.fetch(url, { ...rest, signal: ac.signal })
  } finally {
    clearTimeout(timer)
  }
}

// 流式 fetch：空闲超时——每收到数据用 bump() 重置，超过 idleMs 没动静就中止。
// options.signal 为可选的外部中断信号（用户点「停止」/发起新请求时主动取消）。
// 返回 { res, bump, done }；调用方在读流时 bump、结束时 done()。
async function fetchStream(url, options = {}, idleMs = 30000) {
  const ac = new AbortController()
  let timer = setTimeout(() => ac.abort(), idleMs)
  const { signal: external, ...rest } = options
  linkSignal(ac, external)
  const bump = () => {
    clearTimeout(timer)
    timer = setTimeout(() => ac.abort(), idleMs)
  }
  const done = () => clearTimeout(timer)
  try {
    const res = await net.fetch(url, { ...rest, signal: ac.signal })
    return { res, bump, done }
  } catch (e) {
    clearTimeout(timer)
    throw e
  }
}

module.exports = { fetchT, fetchStream }
