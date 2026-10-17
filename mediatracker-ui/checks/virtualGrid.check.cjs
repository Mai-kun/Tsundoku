// The homemade batch grid (BATCH_SIZE + IntersectionObserver sentinel + page-wide budget)
// truncated sections and left dead space: sections past the budget rendered empty, jumping
// to the bottom never mounted the last rows, and navigating home kept the previous view's
// scroll offset. The grid now virtualizes rows with @tanstack/svelte-virtual instead:
//   - no sentinel element ships at all,
//   - the card DOM stays bounded at any scroll offset and unmounts again on the way back,
//   - the bottom of a long category shows real cards right after a jump,
//   - navigating to Home resets the scroll to the top.
// Run: npm run check:virtual-grid   (needs the server on :5000 with a populated DB)
const { chromium } = require('playwright-core');
const BASE = process.env.TS_BASE || 'http://localhost:5000';

(async () => {
  const launchOptions = {
    channel: process.env.TS_BROWSER_CHANNEL || (process.platform === 'win32' ? 'msedge' : undefined),
    headless: true
  };
  const browser = await chromium.launch(launchOptions);
  const page = await browser.newPage({ viewport: { width: 1440, height: 900 } });
  const errors = [];
  page.on('pageerror', (e) => errors.push(e.message));

  await page.goto(`${BASE}/?view=game`, { waitUntil: 'domcontentloaded' });
  await page.waitForTimeout(2500);

  const result = await page.evaluate(async () => {
    const main = document.getElementById('main-scroll');
    const articles = () => main.querySelectorAll('article').length;
    const sentinels = () => main.querySelectorAll('.col-span-full.pointer-events-none').length;

    const atTop = articles();

    // Jump straight to the bottom of the category list.
    main.scrollTop = main.scrollHeight;
    await new Promise((r) => setTimeout(r, 1200));
    const atBottom = articles();
    const scrollTopAtBottom = main.scrollTop;

    const sections = Array.from(main.querySelectorAll('section'));
    const lastSection = sections[sections.length - 1];
    const lastSectionCards = lastSection
      ? lastSection.querySelectorAll('article').length
      : -1;

    // Back to the top: far rows must unmount again.
    main.scrollTop = 0;
    await new Promise((r) => setTimeout(r, 1200));
    const backAtTop = articles();

    return {
      atTop,
      atBottom,
      backAtTop,
      scrollTopAtBottom,
      sections: sections.length,
      lastSectionCards,
      sentinels: sentinels(),
    };
  });

  // Navigating to Home from a scrolled category must land at the top.
  await page.evaluate(() => {
    document.getElementById('main-scroll').scrollTop = 3000;
  });
  const links = page.locator('aside a, aside button');
  const homeLink = links.filter({ hasText: 'Главная' }).first();
  await homeLink.click();
  await page.waitForTimeout(1200);
  const homeScrollTop = await page.evaluate(
    () => document.getElementById('main-scroll').scrollTop,
  );

  // --- Scroll-performance hardening (WebView2 micro-freezes) ----------------
  // measureElement is gone: every row gets one fixed height per breakpoint, so
  // consecutive rows must sit exactly one row + gap apart (no overlap, no
  // void), rows must be composited in isolation, no measurement wiring
  // (data-index) may remain, and .media-card must not stack content-visibility
  // on top of the virtualizer.
  const perfProblems = [];
  for (const width of [1440, 768, 1920]) {
    await page.setViewportSize({ width, height: 900 });
    await page.goto(`${BASE}/?view=game`, { waitUntil: 'domcontentloaded' });
    await page.waitForSelector('[data-virtual-grid] > div', { timeout: 15000 });
    await page.waitForTimeout(1500);
    const perf = await page.evaluate(() => {
      const grid = document.querySelector('[data-virtual-grid]');
      const rows = [...(grid?.children ?? [])].filter(
        (el) => el instanceof HTMLElement,
      );
      const sample = rows.slice(0, 6).map((r) => {
        const cs = getComputedStyle(r);
        return {
          h: r.getBoundingClientRect().height,
          ty: new DOMMatrix(cs.transform).m42,
          hasDataIndex: r.hasAttribute('data-index'),
          contain: cs.contain,
          willChange: cs.willChange,
        };
      });
      const card = document.querySelector('.media-card');
      return {
        rows: sample.length,
        sample,
        cardContentVisibility: card
          ? getComputedStyle(card).contentVisibility
          : 'missing',
      };
    });
    if (perf.rows < 3)
      perfProblems.push(`${width}px: expected >=3 mounted rows, got ${perf.rows}`);
    for (let i = 1; i < perf.sample.length; i++) {
      const pitch = perf.sample[i].ty - perf.sample[i - 1].ty;
      const expected = perf.sample[i - 1].h + 16;
      if (Math.abs(pitch - expected) > 2)
        perfProblems.push(
          `${width}px: row ${i} pitch ${pitch.toFixed(1)} != height+gap ${expected.toFixed(1)}`,
        );
    }
    if (perf.sample.some((r) => r.hasDataIndex))
      perfProblems.push(`${width}px: rows still carry data-index (measureElement wiring)`);
    if (perf.sample.some((r) => !r.contain.includes('layout')))
      perfProblems.push(`${width}px: virtual rows lack contain: layout`);
    if (perf.sample.some((r) => r.willChange !== 'transform'))
      perfProblems.push(`${width}px: virtual rows lack will-change: transform`);
    if (perf.cardContentVisibility !== 'visible')
      perfProblems.push(
        `${width}px: .media-card content-visibility is ${perf.cardContentVisibility}, must be removed`,
      );
  }
  await page.setViewportSize({ width: 1440, height: 900 });

  await browser.close();

  console.log(
    JSON.stringify({ ...result, homeScrollTop, pageErrors: errors }, null, 2),
  );

  const problems = [];
  if (result.sentinels > 0)
    problems.push(`sentinel element still rendered (${result.sentinels})`);
  if (result.lastSectionCards < 1)
    problems.push(
      `bottom-most of ${result.sections} sections has no cards after jump to bottom (${result.lastSectionCards})`,
    );
  if (result.atBottom >= 150)
    problems.push(`unbounded card DOM at bottom: ${result.atBottom} articles`);
  if (result.backAtTop >= 150)
    problems.push(
      `far rows never unmount on return to top: ${result.backAtTop} articles`,
    );
  if (Math.abs(homeScrollTop) > 2)
    problems.push(`navigating to Home kept scroll offset ${homeScrollTop}`);
  if (perfProblems.length) problems.push(...perfProblems);
  if (errors.length)
    problems.push(`page errors: ${errors.slice(0, 3).join(' | ')}`);

  if (problems.length) {
    console.error('FAIL: ' + problems.join('; '));
    process.exit(1);
  }
  console.log(
    'OK: virtual grid stays bounded, bottom reachable, home scroll resets',
  );
})().catch((e) => {
  console.error('FATAL', e);
  process.exit(1);
});
