// Overview tab ladder: on desktop the tab is two independent columns (each block hugs
// its own content - no block stretched to match its neighbour, so no black holes), and
// below lg everything collapses into one column ordered Progress -> Cast -> Trailer ->
// Studio -> Notes. Run against a server: TS_BASE (default http://localhost:5000).
const { chromium } = require('playwright-core')
const { mkdirSync } = require('node:fs')
const { join } = require('node:path')

const BASE = process.env.TS_BASE || 'http://localhost:5000'
const OUT = join(__dirname, '..', 'shots', 'overview')
mkdirSync(OUT, { recursive: true })

const BLOCKS = [1, 2, 3, 4, 5] // order-* classes: 1 progress, 2 cast, 3 trailer, 4 studio, 5 notes
const VIEWPORTS = [
  ['desktop', { width: 1440, height: 900 }],
  ['mobile', { width: 390, height: 844 }],
]

const box = (page, order) =>
  page.evaluate((o) => {
    const wrap = document.querySelector(`[class~="order-${o}"]`)
    if (!wrap) return null
    const inner = wrap.firstElementChild
    const w = wrap.getBoundingClientRect()
    const i = inner ? inner.getBoundingClientRect() : null
    return {
      x: Math.round(w.x),
      y: Math.round(w.y),
      bottom: Math.round(w.bottom),
      h: Math.round(w.height),
      innerH: i ? Math.round(i.height) : 0,
      tag: inner ? inner.tagName : '',
    }
  }, order)

;(async () => {
  const library = await fetch(`${BASE}/api/media`).then((r) => r.json())
  const item = library.find((m) => m.type === 'movie' || m.type === 'tvshow') || library[0]
  if (!item) {
    console.log('note: empty library, nothing to verify')
    return
  }

  const browser = await chromium.launch({ channel: 'msedge' })
  const problems = []

  for (const [vpName, viewport] of VIEWPORTS) {
    const page = await browser.newPage({ viewport, deviceScaleFactor: 1 })
    await page.goto(`${BASE}/?view=detail&mediaId=${item.id}`, { waitUntil: 'domcontentloaded' })
    await page.waitForTimeout(1500)

    const boxes = []
    for (const order of BLOCKS) {
      const b = await box(page, order)
      if (b) boxes.push({ order, ...b })
    }
    if (!boxes.some((b) => b.order === 1)) problems.push(`${vpName}: progress block missing`)

    // A block never renders taller than the panel inside it (that is what opened the holes).
    for (const b of boxes) {
      if (b.innerH && Math.abs(b.h - b.innerH) > 2)
        problems.push(`${vpName}: block order-${b.order} stretched (${b.h}px box vs ${b.innerH}px content)`)
      if (b.order === 1 && b.h > 260)
        problems.push(`${vpName}: progress block is ${b.h}px tall - it should hug the stepper`)
    }

    // Blocks render top-to-bottom in their order-* sequence.
    const sorted = [...boxes].sort((a, b) => a.order - b.order)
    for (let i = 1; i < sorted.length; i++) {
      if (sorted[i].y + 2 < sorted[i - 1].y)
        problems.push(`${vpName}: order-${sorted[i].order} sits above order-${sorted[i - 1].order}`)
    }

    if (vpName === 'desktop') {
      const left = sorted.filter((b) => b.order === 1 || b.order === 3)
      const right = sorted.filter((b) => b.order === 2 || b.order === 4 || b.order === 5)
      if (left.length === 2 && Math.abs(left[0].x - left[1].x) > 8)
        problems.push('desktop: progress and trailer are not in the same column')
      if (left.length && right.length && right[0].x <= left[0].x + 100)
        problems.push('desktop: right column does not stand beside the left one')
      for (let i = 1; i < left.length; i++) {
        const gap = left[i].y - left[i - 1].bottom
        if (gap < 8 || gap > 24) problems.push(`desktop: left column gap is ${gap}px, expected ~16px`)
      }
      for (let i = 1; i < right.length; i++) {
        const gap = right[i].y - right[i - 1].bottom
        if (gap < 8 || gap > 24) problems.push(`desktop: right column gap is ${gap}px, expected ~16px`)
      }
    } else {
      const xs = boxes.map((b) => b.x)
      if (xs.length > 1 && Math.max(...xs) - Math.min(...xs) > 4)
        problems.push(`mobile: blocks are not one column, x positions ${xs.join(', ')}`)
    }

    // The sidebar poster (local /covers or /media-assets asset) must actually decode.
    const cover = await page.evaluate(() => {
      const img = document.querySelector('aside img')
      return img ? { src: img.currentSrc, w: img.naturalWidth, complete: img.complete } : null
    })
    if (cover && cover.complete && cover.w === 0)
      problems.push(`${vpName}: sidebar cover did not decode: ${cover.src}`)

    const broken = await page.evaluate(() =>
      [...document.images]
        .filter((i) => i.currentSrc && i.complete && i.naturalWidth === 0)
        .map((i) => i.currentSrc),
    )
    if (broken.length) console.log(`note ${vpName}: ${broken.length} broken image(s), e.g. ${broken.slice(0, 3).join(', ')}`)

    await page.screenshot({ path: join(OUT, `${vpName}.png`), fullPage: true })
    await page.close()
  }

  await browser.close()

  if (problems.length) {
    console.error('PROBLEMS:\n' + problems.join('\n'))
    process.exit(1)
  }
  console.log(`OK: overview ladder holds on desktop + mobile for "${item.title}" -> ${OUT}`)
})().catch((e) => {
  console.error('FATAL', e)
  process.exit(1)
})
