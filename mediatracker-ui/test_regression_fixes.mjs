import { chromium } from 'playwright'
import fs from 'node:fs'
import { fileURLToPath } from 'node:url'

const base = 'http://127.0.0.1:5000'
const shots = fileURLToPath(new URL('../shots', import.meta.url))
fs.mkdirSync(shots, { recursive: true })
const browser = await chromium.launch({ headless: true })
const context = await browser.newContext({ viewport: { width: 1440, height: 900 } })
const page = await context.newPage()
const api = async (path, options = {}) => page.request.fetch(base + path, options)
const json = async (path, options = {}) => { const response = await api(path, options); if (!response.ok()) throw new Error(await response.text()); return response.json() }
const voidRequest = async (path, options = {}) => { const response = await api(path, options); if (!response.ok()) throw new Error(await response.text()) }
const log = (name, value) => console.log(`[${name}] ${value}`)
const assert = (condition, message) => { if (!condition) throw new Error(message) }

await page.goto(base)
await page.waitForLoadState('domcontentloaded')
log('server', 'reachable')

// (a) F5 while debounce is active
const book = await json('/api/media', { method: 'POST', headers: {'content-type':'application/json'}, data: JSON.stringify({ type:'book', title:`Regression book ${Date.now()}`, status:1, totalPages:20, author:'Test' }) })
await page.goto(base + '/?view=book'); await page.waitForLoadState('domcontentloaded')
const bookCard = page.locator('article').filter({ hasText: book.title }).first()
await bookCard.waitFor({ state: 'visible', timeout: 10000 })
await bookCard.locator('button:has(svg.lucide-plus)').click()
await page.waitForTimeout(100)
await page.reload(); await page.waitForTimeout(500)
const bookAfter = await json(`/api/media/${book.id}`)
assert(bookAfter.currentPage === 1, `F5 debounce failed: ${bookAfter.currentPage}`)
await page.screenshot({ path: `${shots}/regression_a_f5_debounce.png`, fullPage: true })
log('a F5 debounce', `saved currentPage=${bookAfter.currentPage}`)

// stale callback / filtering: verify the card that moved still sends to its own id
const other = await json('/api/media', { method: 'POST', headers: {'content-type':'application/json'}, data: JSON.stringify({ type:'book', title:`Other ${Date.now()}`, status:1, totalPages:20, author:'Test' }) })
await page.reload(); await page.waitForTimeout(500)
const target = page.locator('article').filter({ hasText: book.title })
await target.locator('button:has(svg.lucide-plus)').click()
await page.waitForTimeout(500)
const bookCheck = await json(`/api/media/${book.id}`)
const otherCheck = await json(`/api/media/${other.id}`)
assert(bookCheck.currentPage === 2 && otherCheck.currentPage === 0, `wrong id after rerender: ${bookCheck.currentPage}/${otherCheck.currentPage}`)
log('stale callback check', `target=${book.id} currentPage=${bookCheck.currentPage}, other=${other.id} currentPage=${otherCheck.currentPage}`)

// (b) all seasons complete
const show = await json('/api/media', { method: 'POST', headers: {'content-type':'application/json'}, data: JSON.stringify({ type:'tvshow', title:`Regression show ${Date.now()}`, status:1, seasons:[{seasonNumber:1,title:'S1',totalEpisodes:2,status:0},{seasonNumber:2,title:'S2',totalEpisodes:2,status:0}] }) })
const showAfterCreate = await json(`/api/media/${show.id}`)
for (const season of showAfterCreate.seasons) await voidRequest(`/api/seasons/${season.id}/progress`, { method:'PUT', headers:{'content-type':'application/json'}, data: JSON.stringify({currentEpisode:season.totalEpisodes}) })
const completedShow = await json(`/api/media/${show.id}`)
assert(completedShow.status === 2 && completedShow.finishedAt, 'all seasons did not complete show')
await page.goto(`${base}/?view=seasons&mediaId=${show.id}`); await page.waitForLoadState('domcontentloaded')
await page.screenshot({ path: `${shots}/regression_b_tvshow_completed.png`, fullPage: true })
log('b TvShow complete', `status=${completedShow.status}, finishedAt=${completedShow.finishedAt}`)

// (c) rollback
const season = completedShow.seasons[0]
await voidRequest(`/api/seasons/${season.id}/progress`, { method:'PUT', headers:{'content-type':'application/json'}, data: JSON.stringify({currentEpisode:1}) })
const rolledBack = await json(`/api/media/${show.id}`)
assert(rolledBack.status === 1 && rolledBack.finishedAt === null, `rollback failed: ${rolledBack.status}/${rolledBack.finishedAt}`)
await page.screenshot({ path: `${shots}/regression_c_tvshow_rollback.png`, fullPage: true })
log('c TvShow rollback', `status=${rolledBack.status}, finishedAt=${rolledBack.finishedAt}`)

// (d) edit through real browser click and verify UI + GET
await page.goto(`${base}/?view=book`); await page.waitForLoadState('domcontentloaded')
const card = page.locator('article').filter({ hasText: book.title })
await card.getByRole('button', { name: 'Edit' }).click()
const titleInput = page.locator('[role=dialog] input').first()
const newTitle = `${book.title} edited`
await titleInput.fill(newTitle)
await page.locator('[role=dialog] button[type=submit]').click()
await page.waitForLoadState('domcontentloaded')
const edited = await json(`/api/media/${book.id}`)
assert(edited.title === newTitle, `DB edit failed: ${edited.title}`)
await page.goto(`${base}/?view=book`); await page.waitForLoadState('domcontentloaded')
assert(await page.locator('article').filter({ hasText: newTitle }).count() === 1, 'edited title not visible in UI')
await page.screenshot({ path: `${shots}/regression_d_edit_card.png`, fullPage: true })
log('d edit card', `UI and GET title=${edited.title}`)

await browser.close()
console.log('ALL 4 REGRESSION SCENARIOS PASSED')














