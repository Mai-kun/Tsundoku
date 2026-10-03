// Visual QA sweep: every view + detail page, desktop and mobile.
// Fails on stray single-character text nodes (e.g. the "?" regression) or page errors.
const { chromium } = require('playwright-core')
const { mkdirSync } = require('node:fs')
const { join } = require('node:path')

const BASE = process.env.TS_BASE || 'http://localhost:5000'
const OUT = join(__dirname, '..', 'shots', 'qa')
mkdirSync(OUT, { recursive: true })

// Detail pages are discovered from the library rather than hardcoded, so the sweep works against any
// data directory instead of only the one the ids happened to be copied from. A type with no items in
// the library simply has no detail page to visit.
const DETAIL_TYPES = [
  ['detail-tv', 'tvshow'],
  ['detail-manga', 'manga'],
  ['detail-game', 'game'],
  ['detail-movie', 'movie'],
]

const VIEW_PAGES = [
  ['home', '?view=home'],
  ['tvshow', '?view=tvshow'],
  ['movie', '?view=movie'],
  ['anime', '?view=anime'],
  ['manga', '?view=manga'],
  ['game', '?view=game'],
  ['book', '?view=book'],
  ['stats', '?view=stats'],
  ['lists', '?view=lists'],
  ['history', '?view=history'],
  ['calendar', '?view=calendar'],
]

const STRAY = () => {
  const out = []
  const walker = document.createTreeWalker(document.body, NodeFilter.SHOW_TEXT)
  let n
  while ((n = walker.nextNode())) {
    const t = n.nodeValue.trim()
    if (t.length === 1 && /[?¿!¡]/.test(t)) {
      const el = n.parentElement
      const r = el.getBoundingClientRect()
      out.push({ char: t, x: Math.round(r.x), y: Math.round(r.y), tag: el.tagName, cls: String(el.className).slice(0, 60) })
    }
  }
  return out
}

const VIEWPORTS = [
  ['desktop', { width: 1440, height: 900 }],
  ['mobile', { width: 390, height: 844 }],
].filter(([name]) => !process.argv[2] || process.argv[2] === name)

;(async () => {
  const library = await fetch(`${BASE}/api/media`).then((r) => r.json())
  const firstOfType = (type) => library.find((m) => m.type === type)

  const PAGES = [
    ...VIEW_PAGES,
    ...DETAIL_TYPES.map(([name, type]) => {
      const item = firstOfType(type)
      return item ? [name, `?view=detail&mediaId=${item.id}`] : null
    }).filter(Boolean),
  ]

  const missing = DETAIL_TYPES.filter(([, type]) => !firstOfType(type)).map(([name]) => name)
  if (missing.length) console.log(`note: no library item for ${missing.join(', ')} - skipping those detail pages`)

  const browser = await chromium.launch({ channel: 'msedge' })
  const problems = []

  for (const [vpName, viewport] of VIEWPORTS) {
    const page = await browser.newPage({ viewport, deviceScaleFactor: 1 })
    const errors = []
    page.on('pageerror', (e) => errors.push('PAGEERROR: ' + e.message))
    page.on('console', (m) => { if (m.type() === 'error') errors.push('CONSOLE: ' + m.text()) })

    for (const [name, query] of PAGES) {
      errors.length = 0
      await page.goto(BASE + '/' + query, { waitUntil: 'domcontentloaded' })
      await page.waitForTimeout(900)
      await page.screenshot({ path: join(OUT, `${vpName}-${name}.png`), fullPage: true })

      const stray = await page.evaluate(STRAY)
      const real = stray.filter((s) => s.x > 0 || s.y > 0)
      if (real.length) problems.push(`${vpName}/${name}: stray glyphs ${JSON.stringify(real)}`)
      const errs = errors.filter((e) => !/favicon|404 \(Not Found\)/i.test(e))
      if (errs.length) problems.push(`${vpName}/${name}: ${errs.slice(0, 3).join(' | ')}`)
    }
    await page.close()
  }

  await browser.close()

  if (problems.length) {
    console.error('PROBLEMS:\n' + problems.join('\n'))
    process.exit(1)
  }
  console.log(`OK: ${PAGES.length} screens x ${VIEWPORTS.length} viewports clean -> ${OUT}`)
})().catch((e) => { console.error('FATAL', e); process.exit(1); })
