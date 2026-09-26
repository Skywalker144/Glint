'use strict'

window.VocabularyPage = (() => {
  const query = (selector) => document.querySelector(selector)
  const list = query('#vocabulary-list')
  const summary = query('#vocabulary-summary')
  const search = query('#vocabulary-search')
  const filter = query('#vocabulary-filter')
  let entries = []
  let page = 0
  let request = 0
  const pageSize = 30

  function render() {
    const text = search.value.trim().toLowerCase()
    const matching = entries.filter((entry) => {
      const matchesText = (entry.word + '\n' + entry.translated).toLowerCase().includes(text)
      const matchesStatus = filter.value === 'all' || (filter.value === 'mastered' ? entry.mastered : !entry.mastered)
      return matchesText && matchesStatus
    })
    const pages = Math.max(1, Math.ceil(matching.length / pageSize))
    page = Math.min(page, pages - 1)
    summary.textContent = '共 ' + entries.length + ' 词 · 学习中 ' + entries.filter((entry) => !entry.mastered).length + ' · 匹配 ' + matching.length + ' 词'
    query('#vocabulary-page').textContent = (page + 1) + ' / ' + pages
    query('#vocabulary-previous').disabled = page === 0
    query('#vocabulary-next').disabled = page + 1 >= pages
    list.replaceChildren()
    if (!matching.length) {
      const empty = document.createElement('p')
      empty.className = 'history-empty'
      empty.textContent = entries.length ? '没有匹配的生词' : '查词后点击「☆ 收藏」，在这里保存和回顾。'
      list.append(empty)
    }
    for (const entry of matching.slice(page * pageSize, (page + 1) * pageSize)) {
      const card = document.createElement('article')
      card.className = 'vocabulary-entry'
      const heading = document.createElement('div')
      heading.className = 'vocabulary-heading'
      const word = document.createElement('strong')
      word.textContent = entry.word
      const badge = document.createElement('span')
      badge.className = 's-tip'
      badge.textContent = entry.mastered ? '已掌握' : '学习中'
      heading.append(word, badge)
      const details = document.createElement('details')
      const title = document.createElement('summary')
      title.textContent = '查看释义'
      const body = document.createElement('div')
      body.className = 'vocabulary-definition'
      details.append(title, body)
      details.addEventListener('toggle', async () => {
        if (!details.open || body.childNodes.length) return
        try {
          const html = await window.api.renderMarkdown(entry.translated)
          if (details.isConnected) body.innerHTML = html
        } catch (error) {
          summary.textContent = '无法显示释义：' + error.message
        }
      })
      const actions = document.createElement('div')
      actions.className = 'vocabulary-actions'
      for (const [label, action] of [['朗读', 'speak'], [entry.mastered ? '继续学习' : '标记已掌握', 'master'], ['删除', 'remove']]) {
        const button = document.createElement('button')
        button.className = 'ghost'
        button.textContent = label
        button.addEventListener('click', async () => {
          button.disabled = true
          try {
            if (action === 'speak') await window.GlintSpeech.speak(entry.word, entry.source, button)
            if (action === 'master') await window.api.updateVocabulary(entry.id, !entry.mastered)
            if (action === 'remove') await window.api.removeVocabulary(entry.id)
            if (action !== 'speak') await load()
          } catch (error) {
            summary.textContent = '操作失败：' + error.message
          } finally {
            button.disabled = false
          }
        })
        actions.append(button)
      }
      const metadata = document.createElement('p')
      metadata.className = 's-tip'
      metadata.textContent = entry.attribution + ' · ' + new Date(entry.createdAt).toLocaleDateString('zh-CN')
      card.append(heading, details, metadata, actions)
      list.append(card)
    }
  }

  async function load() {
    const token = ++request
    try {
      const loaded = await window.api.getVocabulary()
      if (token !== request) return
      entries = loaded
      render()
    } catch (error) {
      if (token === request) summary.textContent = '读取失败：' + error.message
    }
  }

  for (const input of [search, filter]) input.addEventListener('input', () => { page = 0; render() })
  query('#vocabulary-previous').addEventListener('click', () => { page--; render() })
  query('#vocabulary-next').addEventListener('click', () => { page++; render() })
  query('#vocabulary-export').addEventListener('click', async () => {
    try {
      const result = await window.api.exportVocabulary()
      if (!result.canceled) summary.textContent = '已导出生词本（JSON）'
    } catch (error) {
      summary.textContent = '导出失败：' + error.message
    }
  })
  list.addEventListener('click', (event) => {
    const link = event.target.closest('a')
    if (link) {
      event.preventDefault()
      window.api.openExternal(link.href)
    }
  })
  return { load }
})()
