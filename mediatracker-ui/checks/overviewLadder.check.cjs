// Overview tab ladder: on desktop the tab is two independent columns (each block hugs
// its own content - no block stretched to match its neighbour, so no black holes), the
// left one being Progress -> Trailer -> Notes and the right one Cast -> Creator. Below lg
// everything collapses into one column ordered Progress -> Cast -> Trailer -> Creator ->
// Notes. Run against a server: TS_BASE (default http://localhost:5000).
const { chromium } = require('playwright-core')
const { mkdirSync } = require('node:fs')
const { join } = require('node:path')

const BASE = process.env.TS_BASE || 'http://localhost:5000'
const OUT = join(__dirname, '..', 'shots', 'overview')
mkdirSync(OUT, { recursive: true })

const BLOCKS = [1, 2, 3, 4, 5] // order-* classes: 1 progress, 2 cast, 3 trailer, 4 creator, 5 notes
const LEFT_COLUMN = [1, 3, 5] // progress, trailer, notes
const RIGHT_COLUMN = [2, 4] // cast, creator
const VIEWPORTS = [
  ['desktop', { width: 1440, height: 900 }],
  ['mobile', { width: 390, height: 844 }],
]

const box = (page, order) =>
  page.evaluate((o) => {
    const wrap = document.querySelector(`[class~="order-${o}"]`)
    if (!wrap) return null
    const w = wrap.getBoundingClientRect()
    // Content extent of the wrapper: top of the first child to bottom of the last one. Measuring
    // only the first child would report a game (counter + achievements, two sections) as stretched.
    const kids = [...wrap.children]
    const first = kids[0]?.getBoundingClientRect()
    const last = kids[kids.length - 1]?.getBoundingClientRect()
    const inner = first && last ? { height: last.bottom - first.top } : null
    return {
      x: Math.round(w.x),
      y: Math.round(w.y),
      bottom: Math.round(w.bottom),
      h: Math.round(w.height),
      innerH: inner ? Math.round(inner.height) : 0,
    }
  }, order)

async function checkItem(page, item, vpName, problems) {
  await page.goto(`${BASE}/?view=detail&mediaId=${item.id}`, { waitUntil: 'domcontentloaded' })
  await page.waitForTimeout(1500)

  const boxes = []
  for (const order of BLOCKS) {
    const b = await box(page, order)
    if (b) boxes.push({ order, ...b })
  }
  const tag = `${item.type}/${vpName}`
  if (!boxes.some((b) => b.order === 1)) problems.push(`${tag}: progress block missing`)
  // Books/manga carry no cast: the wrapper must be absent, not an empty cell holding the row open.
  if ((item.type === 'book' || item.type === 'manga' || item.type === 'game') && boxes.some((b) => b.order === 2))
    problems.push(`${tag}: an empty cast block was rendered`)

  // A block never renders taller than the panel inside it (that is what opened the holes).
  for (const b of boxes) {
    if (b.innerH && Math.abs(b.h - b.innerH) > 2)
      problems.push(`${tag}: block order-${b.order} stretched (${b.h}px box vs ${b.innerH}px content)`)
    // The game's hour counter carries its own achievements list, so it is the one progress block
    // allowed to be tall; every other one must hug the stepper.
    if (b.order === 1 && item.type !== 'game' && b.h > 260)
      problems.push(`${tag}: progress block is ${b.h}px tall - it should hug the stepper`)
  }

  const sorted = [...boxes].sort((a, b) => a.order - b.order)
  // Blocks render top-to-bottom in their order-* sequence -- but only where they share a flow. On
  // desktop each column is its own, so a right-column block may legitimately sit higher.
  if (vpName !== 'desktop') {
    for (let i = 1; i < sorted.length; i++) {
      if (sorted[i].y + 2 < sorted[i - 1].y)
        problems.push(`${tag}: order-${sorted[i].order} sits above order-${sorted[i - 1].order}`)
    }
  }

  if (vpName === 'desktop') {
    const left = LEFT_COLUMN.map((o) => sorted.find((b) => b.order === o)).filter(Boolean)
    const right = RIGHT_COLUMN.map((o) => sorted.find((b) => b.order === o)).filter(Boolean)
    for (const b of left) {
      if (Math.abs(b.x - left[0].x) > 8) problems.push(`${tag}: order-${b.order} left the left column`)
    }
    for (const b of right) {
      if (Math.abs(b.x - right[0].x) > 8) problems.push(`${tag}: order-${b.order} left the right column`)
    }
    if (left.length && right.length && right[0].x <= left[0].x + 100)
      problems.push(`${tag}: right column does not stand beside the left one`)
    // Both columns hang off the same top edge. Their bottoms are free to differ -- block heights are
    // content-driven (a game's hour counter is a metre taller than a movie's status chip), and
    // equalising them is exactly the stretch that opened the black holes this ladder avoids.
    if (left.length && right.length && Math.abs(left[0].y - right[0].y) > 8)
      problems.push(`${tag}: columns start ${Math.abs(left[0].y - right[0].y)}px apart`)
    for (const col of [left, right]) {
      for (let i = 1; i < col.length; i++) {
        const gap = col[i].y - col[i - 1].bottom
        if (gap < 8 || gap > 24) problems.push(`${tag}: column gap is ${gap}px, expected ~16px`)
      }
    }
    // Cast cards are two per row with roomy avatars, not a squeezed three-column strip.
    const cast = await page.evaluate(() => {
      const heading = [...document.querySelectorAll('h2')].find((h) => /cast|сэйю|ролях/i.test(h.textContent || ''))
      const grid = heading?.nextElementSibling
      const card = grid?.firstElementChild
      const avatar = card?.querySelector('img, span')
      return {
        cols: grid ? getComputedStyle(grid).gridTemplateColumns.split(' ').length : 0,
        avatar: avatar ? Math.round(avatar.getBoundingClientRect().width) : 0,
      }
    })
    if (cast.cols && cast.cols > 2) problems.push(`${tag}: cast renders ${cast.cols} columns, expected at most 2`)
    if (cast.avatar && cast.avatar < 40) problems.push(`${tag}: cast avatar is ${cast.avatar}px, expected 52+`)
  } else {
    const xs = boxes.map((b) => b.x)
    if (xs.length > 1 && Math.max(...xs) - Math.min(...xs) > 4)
      problems.push(`${tag}: blocks are not one column, x positions ${xs.join(', ')}`)
  }

  // The sidebar poster (local /covers or /media-assets asset) must actually decode.
  const cover = await page.evaluate(() => {
    const img = document.querySelector('aside img')
    return img ? { src: img.currentSrc, w: img.naturalWidth, complete: img.complete } : null
  })
  if (cover && cover.complete && cover.w === 0) problems.push(`${tag}: sidebar cover did not decode: ${cover.src}`)

  const broken = await page.evaluate(() =>
    [...document.images].filter((i) => i.currentSrc && i.complete && i.naturalWidth === 0).map((i) => i.currentSrc),
  )
  if (broken.length) console.log(`note ${tag}: ${broken.length} broken image(s), e.g. ${broken.slice(0, 3).join(', ')}`)

  await page.screenshot({ path: join(OUT, `${item.type}-${vpName}.png`), fullPage: true })
}

;(async () => {
  const library = await fetch(`${BASE}/api/media`).then((r) => r.json())
  // One item per media type: each brings a different left column (episodes / pages / chapters /
  // hours) and a different creator card, and books/manga have to prove the empty cast case.
  const items = ['tvshow', 'movie', 'book', 'manga', 'game']
    .map((type) => library.find((m) => m.type === type))
    .filter(Boolean)
  if (!items.length) {
    console.log('note: empty library, nothing to verify')
    return
  }

  const launchOptions = {
    channel: process.env.TS_BROWSER_CHANNEL || (process.platform === 'win32' ? 'msedge' : undefined),
    headless: true
  };
  const browser = await chromium.launch(launchOptions);
  const problems = []

  for (const [vpName, viewport] of VIEWPORTS) {
    const page = await browser.newPage({ viewport, deviceScaleFactor: 1 })
    for (const item of items) await checkItem(page, item, vpName, problems)
    await page.close()
  }

  await browser.close()

  if (problems.length) {
    console.error('PROBLEMS:\n' + problems.join('\n'))
    process.exit(1)
  }
  console.log(`OK: overview ladder holds on desktop + mobile for ${items.length} media type(s) -> ${OUT}`)
})().catch((e) => {
  console.error('FATAL', e)
  process.exit(1)
})
