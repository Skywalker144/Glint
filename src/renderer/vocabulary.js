'use strict'

const list = document.querySelector('#list')
const detail = document.querySelector('#detail')
const search = document.querySelector('#search')
const sort = document.querySelector('#sort')
const error = document.querySelector('#error')
let items = []
let selectedId = null
let renderVersion = 0
let revision = 0
let languages = []

function showError(message) {
  error.textContent = message
  error.hidden = !message
}

async function render() {
  const version = ++renderVersion
  const query = search.value.normalize('NFC').trim().toLocaleLowerCase()
  const visible = items.filter(item => (item.headword + '\n' + item.translated).normalize('NFC').toLocaleLowerCase().includes(query))
  visible.sort((a, b) => (sort.value === 'queries' ? b.queryCount - a.queryCount : 0) || b.createdAt.localeCompare(a.createdAt))
  if (!visible.some(item => item.id === selectedId)) selectedId = visible[0]?.id || null
  document.querySelector('#summary').textContent = query ? `${visible.length} / ${items.length} 个词` : `${items.length} 个词`
  list.replaceChildren()
  for (const item of visible) {
    const button = document.createElement('button')
    button.className = 'word'
    button.dataset.id = item.id
    button.setAttribute('aria-current', String(item.id === selectedId))
    const word = document.createElement('strong')
    word.textContent = item.headword
    const meta = document.createElement('small')
    meta.textContent = `${languages.find(language => language.code === item.language)?.label || item.language} · 查询 ${item.queryCount} 次`
    button.append(word, meta)
    button.addEventListener('click', () => { selectedId = item.id; render() })
    list.appendChild(button)
  }
  const item = visible.find(item => item.id === selectedId)
  detail.replaceChildren()
  if (!item) {
    const empty = document.createElement('p')
    empty.className = 'empty'
    empty.textContent = items.length ? '没有匹配的词条' : '查词后点击 ☆，把单词收入生词本'
    detail.appendChild(empty)
    return
  }
  const heading = document.createElement('h1')
  heading.textContent = item.headword
  const metadata = document.createElement('p')
  metadata.className = 'metadata'
  metadata.textContent = `收藏于 ${new Date(item.createdAt).toLocaleDateString()} · 收藏后查询 ${item.queryCount} 次`
  const definition = document.createElement('div')
  definition.className = 'definition'
  const remove = document.createElement('button')
  remove.id = 'remove'
  remove.className = 'ghost'
  remove.textContent = '取消收藏'
  remove.addEventListener('click', async () => {
    remove.disabled = true
    try {
      await window.api.removeVocabulary(item.id)
      showError('')
    } catch (cause) {
      showError('取消收藏失败：' + cause.message)
      remove.disabled = false
    }
  })
  detail.append(heading, metadata, definition, remove)
  try {
    const html = await window.api.renderMarkdown(item.translated)
    if (version === renderVersion) definition.innerHTML = html
  } catch (cause) {
    if (version === renderVersion) showError('显示词条失败：' + cause.message)
  }
}

window.api.onVocabularyChanged((next) => {
  revision++
  items = next
  showError('')
  render()
})
search.addEventListener('input', render)
sort.addEventListener('change', render)
detail.addEventListener('click', (event) => {
  const link = event.target.closest('a')
  if (!link) return
  event.preventDefault()
  window.api.openExternal(link.href)
})
document.querySelector('#close').addEventListener('click', () => window.api.closeVocabulary())
document.addEventListener('keydown', (event) => {
  if (event.key === 'Escape' && !event.isComposing) window.api.closeVocabulary()
})
const initialRevision = revision
Promise.all([window.api.getVocabulary(), window.api.getLanguages()]).then(([next, nextLanguages]) => {
  languages = nextLanguages
  if (initialRevision === revision) items = next
  render()
  search.focus()
}).catch((cause) => showError('读取生词本失败：' + cause.message))
