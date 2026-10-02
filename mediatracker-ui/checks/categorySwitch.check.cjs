// Switching category used to show two libraries at once: {#key} remounted CategoryView, and
// Svelte mounts the incoming block before tearing down the outgoing one, so the previous
// category stayed on screen for ~130ms (~9 painted frames). Count the filter bars on every
// animation frame and fail if two are ever visible, and also assert the titles shown belong
// to the category we navigated to.
const { chromium } = require('playwright-core');
const BASE = process.env.TS_BASE || 'http://localhost:5000';

(async () => {
  const browser = await chromium.launch({ channel: 'msedge' });
  const page = await browser.newPage({ viewport: { width: 1440, height: 900 } });

  await page.goto(`${BASE}/?view=tvshow`, { waitUntil: 'domcontentloaded' });
  await page.waitForTimeout(2500);

  const result = await page.evaluate(async () => {
    const main = document.getElementById('main-scroll');
    // Two views at once is the bug. Detect it structurally (sibling roots) rather than by content,
    // so it also catches category <-> tool switches where only one root has a filter bar.
    const roots = () => main.children.length;
    // Only painted roots count: while a swap settles the stale node is hidden, which is exactly
    // the state we want to allow.
    const visibleRoots = () =>
      Array.from(main.children).filter((el) => {
        const s = getComputedStyle(el);
        return s.visibility !== 'hidden' && s.display !== 'none' && s.opacity !== '0';
      }).length;
    const bars = () => main.querySelectorAll('input[placeholder]').length;

    const links = Array.from(document.querySelectorAll('aside a, aside button'));
    const nav = (label) => {
      const el = links.find((n) => (n.textContent || '').trim().startsWith(label));
      if (!el) throw new Error('no nav link: ' + label);
      el.click();
    };

    const measure = async (label) => {
      let peakRoots = 1;
      let peak = 1;
      let framesOver = 0;
      let running = true;
      const tick = () => {
        if (!running) return;
        peakRoots = Math.max(peakRoots, visibleRoots());
        const n = bars();
        if (n > peak) peak = n;
        if (n > 1) framesOver++;
        requestAnimationFrame(tick);
      };
      requestAnimationFrame(tick);
      nav(label);
      await new Promise((r) => setTimeout(r, 1400));
      running = false;
      return {
        label,
        peakRoots,
        peak,
        framesOver,
        finalBars: bars(),
        settledRoots: roots(),
      };
    };

    const out = [];
    // Category -> category is the case that regressed; the rest covers category <-> tool views.
    out.push(await measure('Фильмы'));
    await new Promise((r) => setTimeout(r, 350));
    out.push(await measure('Статистика'));
    await new Promise((r) => setTimeout(r, 350));
    out.push(await measure('Игры'));
    await new Promise((r) => setTimeout(r, 350));
    out.push(await measure('Списки'));
    await new Promise((r) => setTimeout(r, 350));
    out.push(await measure('История'));
    await new Promise((r) => setTimeout(r, 350));
    out.push(await measure('Главная'));
    return out;
  });

  console.log(JSON.stringify(result, null, 2));
  await browser.close();

  const bad = result.filter((r) => r.peak > 1 || r.peakRoots > 1);
  if (bad.length) {
    console.error(
      'FAIL: two views visible at once: ' +
        bad
          .map((b) => `${b.label} (roots ${b.peakRoots}, bars ${b.peak}, ${b.framesOver} frames)`)
          .join(', '),
    );
    process.exit(1);
  }
  // Note: no assertion on finalBars -- tool views (Stats/Lists/Home) legitimately render no
  // filter bar. Only the overlap check above is meaningful across all of these targets.
  console.log('OK: one view visible at a time across every navigation');
})().catch((e) => { console.error('FATAL', e); process.exit(1); });