// The status badge and the score bubble sit in one overlapping cluster on the poster. They must
// keep that overlap (the score pulls left over the badge) AND the score must paint on top.
// Paint order cannot be read off geometry, so hit-test the overlap point: whatever element
// actually receives the click at the centre of the shared area is the one on top.
const { chromium } = require('playwright-core');
const BASE = process.env.TS_BASE || 'http://localhost:5000';

(async () => {
  const browser = await chromium.launch({ channel: 'msedge' });
  const page = await browser.newPage({ viewport: { width: 1440, height: 900 } });

  await page.goto(`${BASE}/?view=game`, { waitUntil: 'domcontentloaded' });
  await page.waitForTimeout(2500);

  const result = await page.evaluate(() => {
    // Find a card that actually shows a score, so the overlap is exercised.
    for (const card of document.querySelectorAll('article')) {
      const poster = card.querySelector('article > div');
      if (!poster) continue;

      const badge = poster.querySelector('button[popovertarget]');
      const score = Array.from(poster.querySelectorAll('div')).find(
        (d) => /^[\d.,]+$/.test((d.textContent || '').trim()) && d !== badge,
      );
      if (!badge || !score) continue;

      const b = badge.getBoundingClientRect();
      const s = score.getBoundingClientRect();

      const overlapLeft = Math.max(b.left, s.left);
      const overlapRight = Math.min(b.right, s.right);
      const overlapW = overlapRight - overlapLeft;
      if (overlapW <= 1) continue;

      // Sample inside the shared strip, biased to the score's own area.
      const px = Math.round(s.left + (overlapW * 0.6));
      const py = Math.round(s.top + s.height / 2);
      const hit = document.elementFromPoint(px, py);

      return {
        title: card.querySelector('h2')?.textContent?.trim(),
        overlapW: Math.round(overlapW),
        scoreOnTop: score.contains(hit) || hit === score,
        hitTag: hit?.tagName,
        hitText: (hit?.textContent || '').trim().slice(0, 12),
      };
    }
    return { error: 'no rated card with an overlapping score bubble found' };
  });

  console.log(JSON.stringify(result, null, 2));
  await browser.close();

  if (result.error) { console.error('FAIL:', result.error); process.exit(1); }
  if (!result.scoreOnTop) {
    console.error(`FAIL: score bubble is painted under the status badge (hit "${result.hitTag} ${result.hitText}")`);
    process.exit(1);
  }
  if (result.overlapW <= 1) { console.error('FAIL: bubbles no longer overlap'); process.exit(1); }
  console.log(`OK: score overlaps badge by ${result.overlapW}px and paints on top`);
})().catch((e) => { console.error('FATAL', e); process.exit(1); });