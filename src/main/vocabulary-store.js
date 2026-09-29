'use strict'

const fs = require('node:fs')
const { EventEmitter } = require('node:events')
const { dictionaryEntry } = require('./dictionary-entry')

class VocabularyStore extends EventEmitter {
  constructor(file) {
    super()
    this.file = file
    this.items = null
  }

  list() {
    if (!this.items) {
      try {
        const items = JSON.parse(fs.readFileSync(this.file, 'utf8'))
        if (!Array.isArray(items) || items.some(item => !item || typeof item.id !== 'string' || !Number.isSafeInteger(item.queryCount) || item.queryCount < 0)) {
          throw new Error('生词本数据格式无效')
        }
        this.items = items
      } catch (error) {
        if (error.code !== 'ENOENT') throw error
        this.items = []
      }
    }
    return structuredClone(this.items)
  }

  persist(items) {
    fs.writeFileSync(this.file + '.tmp', JSON.stringify(items, null, 2), 'utf8')
    fs.renameSync(this.file + '.tmp', this.file)
    this.items = items
    this.emit('changed', this.list())
  }

  add(value) {
    const entry = value && dictionaryEntry(value.translated, {
      dict: true, secondaryLanguage: value.language, primaryLanguage: value.definitionLanguage,
    })
    if (!entry || entry.id !== value.id) throw new Error('没有可收藏的完整词条')
    const items = this.list()
    if (!items.some(item => item.id === entry.id)) {
      this.persist([{ ...entry, createdAt: new Date().toISOString(), queryCount: 0, lastQueriedAt: null }, ...items])
    }
    return this.list()
  }

  remove(id) {
    const items = this.list()
    const next = items.filter(item => item.id !== id)
    if (next.length !== items.length) this.persist(next)
    return this.list()
  }

  recordLookup(entry) {
    if (!entry) return
    const items = this.list()
    const item = items.find(item => item.id === entry.id)
    if (!item) return
    item.queryCount += 1
    item.lastQueriedAt = new Date().toISOString()
    this.persist(items)
  }
}

module.exports = { VocabularyStore }
