'use strict'

const fs = require('node:fs')
const { randomUUID } = require('node:crypto')

class Vocabulary {
  constructor(file) {
    this.file = file
  }

  list() {
    let data
    try {
      data = JSON.parse(fs.readFileSync(this.file, 'utf8'))
    } catch (error) {
      if (error.code === 'ENOENT') return []
      throw new Error('无法读取生词本，请检查文件：' + this.file, { cause: error })
    }
    if (!data || data.version !== 1 || !Array.isArray(data.entries) || data.entries.some((entry) =>
      !entry || typeof entry.id !== 'string' || typeof entry.word !== 'string' || typeof entry.translated !== 'string')) {
      throw new Error('生词本格式无效：' + this.file)
    }
    return data.entries
  }

  persist(entries) {
    fs.writeFileSync(this.file + '.tmp', JSON.stringify({ version: 1, entries }, null, 2), { encoding: 'utf8', mode: 0o600 })
    fs.renameSync(this.file + '.tmp', this.file)
  }

  add(item) {
    if (!item || item.mode !== 'dict' || typeof item.word !== 'string' || !item.word.trim() || item.word.length > 100 ||
      typeof item.translated !== 'string' || !item.translated.trim() || item.translated.length > 100000) {
      throw new Error('只能收藏完整的词典词条')
    }
    const entries = this.list()
    const word = item.word.normalize('NFKC').trim().replace(/\s+/g, ' ')
    const source = typeof item.source === 'string' ? item.source : 'auto'
    const previous = entries.find((entry) => entry.word.toLowerCase() === word.toLowerCase() && entry.source === source)
    const entry = {
      id: previous?.id || randomUUID(), word: previous?.word || word,
      original: String(item.original || word), translated: item.translated,
      source, target: String(item.target || ''), attribution: String(item.attribution || ''),
      createdAt: previous?.createdAt || new Date().toISOString(),
      updatedAt: new Date().toISOString(), mastered: previous?.mastered || false,
    }
    this.persist([entry, ...entries.filter((other) => other.id !== entry.id)])
    return entry
  }

  update(id, mastered) {
    if (typeof mastered !== 'boolean') throw new Error('无效的掌握状态')
    const entries = this.list()
    const entry = entries.find((other) => other.id === id)
    if (!entry) throw new Error('词条不存在')
    entry.mastered = mastered
    entry.updatedAt = new Date().toISOString()
    this.persist(entries)
    return entry
  }

  remove(id) {
    this.persist(this.list().filter((entry) => entry.id !== id))
  }

  export() {
    return JSON.stringify({ version: 1, entries: this.list() }, null, 2)
  }
}

module.exports = { Vocabulary }
