'use strict'

const fs = require('node:fs/promises')
const path = require('node:path')
const { createHash } = require('node:crypto')
const { gunzip } = require('node:zlib')
const { promisify } = require('node:util')
const manifest = require('./data/ecdict/manifest.json')
const decompress = promisify(gunzip)
const cache = new Map()
const changes = { p: '过去式', d: '过去分词', i: '现在分词', '3': '第三人称单数', r: '比较级', t: '最高级', s: '复数', '0': '原形' }
const tags = { zk: '中考', gk: '高考', cet4: '四级', cet6: '六级', ky: '考研', toefl: '托福', ielts: '雅思', gre: 'GRE' }

function normalizeWord(text) {
  return String(text || '').normalize('NFKC').trim().toLowerCase().replace(/\s+/g, ' ')
}

async function lookup(text, resolveRoot = true) {
  const key = normalizeWord(text)
  if (!key || key.length > 100 || !/^[a-z][a-z '’.-]*$/i.test(key)) return null
  const bucket = createHash('sha256').update(key).digest()[0] % manifest.shards
  if (!cache.has(bucket)) {
    const loading = fs.readFile(path.join(__dirname, 'data/ecdict', String(bucket).padStart(2, '0') + '.json.gz'))
      .then(decompress).then((data) => JSON.parse(data.toString('utf8')))
    cache.set(bucket, loading)
    loading.catch(() => cache.delete(bucket))
    if (cache.size > 4) cache.delete(cache.keys().next().value)
  }
  const shard = await cache.get(bucket)
  if (!Object.hasOwn(shard, key)) return null
  const record = shard[key]
  if (typeof record === 'string') return resolveRoot ? lookup(record, false) : null
  if (resolveRoot) {
    const root = (record.exchange || '').split('/').find((part) => part.startsWith('0:'))?.slice(2).split(',')[0]
    if (root && normalizeWord(root) !== key) return (await lookup(root, false)) || record
  }
  return record
}

function escapeMarkdown(text) {
  return String(text || '').replace(/[\\`*_{}\[\]<>#+.!|$~-]/g, '\\$&')
}

function renderEntry(entry, original = entry.word) {
  const sections = ['**' + escapeMarkdown(entry.word) + '**' + (entry.phonetic ? ' /' + escapeMarkdown(entry.phonetic) + '/' : '')]
  if (normalizeWord(original) !== normalizeWord(entry.word)) sections.push('查询：' + escapeMarkdown(original))
  if (entry.translation) sections.push('**中文释义**\n' + escapeMarkdown(entry.translation))
  if (entry.definition) sections.push('**英文释义**\n' + escapeMarkdown(entry.definition))
  const forms = (entry.exchange || '').split('/').map((part) => {
    const [kind, value] = part.split(':')
    return changes[kind] && value ? changes[kind] + '：' + escapeMarkdown(value) : ''
  }).filter(Boolean)
  if (forms.length) sections.push('**词形变化**\n' + forms.join(' · '))
  const labels = (entry.tag || '').split(' ').map((tag) => tags[tag]).filter(Boolean)
  if (labels.length) sections.push(labels.join(' · '))
  sections.push('[词典来源：ECDICT](' + manifest.url + ')')
  return sections.join('\n\n')
}

module.exports = { lookup, renderEntry, normalizeWord }
