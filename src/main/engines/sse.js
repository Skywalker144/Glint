'use strict'

// 读取 SSE 流：逐行把 `data:` 后面的负载交给 onData。
// res 需是 fetch Response（net.fetch 的返回），其 body 为 ReadableStream。
async function readSSE(res, onData, onActivity) {
  if (!res.body || typeof res.body.getReader !== 'function') {
    throw new Error('当前环境不支持流式响应')
  }
  const reader = res.body.getReader()
  const decoder = new TextDecoder()
  let buf = ''
  for (;;) {
    const { done, value } = await reader.read()
    if (done) break
    if (onActivity) onActivity()
    buf += decoder.decode(value, { stream: true })
    let nl
    while ((nl = buf.indexOf('\n')) >= 0) {
      let line = buf.slice(0, nl)
      buf = buf.slice(nl + 1)
      if (line.endsWith('\r')) line = line.slice(0, -1)
      line = line.trim()
      if (line.startsWith('data:')) onData(line.slice(5).trim())
    }
  }
  const rest = buf.trim()
  if (rest.startsWith('data:')) onData(rest.slice(5).trim())
}

module.exports = { readSSE }
