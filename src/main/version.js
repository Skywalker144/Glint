'use strict'

// 语义化版本比较：只看数字段，忽略 v 前缀和预发布后缀（如 -beta）。

function parseVersion(v) {
  return String(v || '')
    .replace(/^v/i, '')
    .split('-')[0] // 丢掉 -beta 之类的预发布后缀
    .split('.')
    .map((n) => parseInt(n, 10) || 0)
}

// a 是否比 b 新。
function isNewer(a, b) {
  const pa = parseVersion(a)
  const pb = parseVersion(b)
  for (let i = 0; i < Math.max(pa.length, pb.length); i++) {
    if ((pa[i] || 0) > (pb[i] || 0)) return true
    if ((pa[i] || 0) < (pb[i] || 0)) return false
  }
  return false
}

module.exports = { isNewer, parseVersion }
