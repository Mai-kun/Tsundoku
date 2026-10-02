// Reports which design tokens actually resolve on :root at runtime.
const { chromium } = require('playwright-core');
const BASE = process.env.TS_BASE || 'http://localhost:5000';

const TOKENS = [
  'canvas', 'surface', 'card', 'card-hover', 'elevated', 'panel', 'accent', 'accent-soft',
  'muted', 'ink', 'panel-line', 'field', 'overlay', 'overlay-strong', 'modal',
  'track', 'track-deep', 'track-mid', 'track-soft', 'track-faint', 'track-alt',
  'score-bg', 'brand-blue', 'slate-deep',
];

(async () => {
  const browser = await chromium.launch({ channel: 'msedge' });
  const page = await browser.newPage({ viewport: { width: 1440, height: 900 } });
  await page.goto(BASE + '/?view=home', { waitUntil: 'domcontentloaded' });
  await page.waitForTimeout(1200);

  const res = await page.evaluate((tokens) => {
    const cs = getComputedStyle(document.documentElement);
    const out = {};
    for (const t of tokens) {
      const v = cs.getPropertyValue(`--color-${t}`).trim();
      out[`--color-${t}`] = v === '' ? 'MISSING' : v;
    }
    const ease = cs.getPropertyValue('--ease-tap').trim();
    out['--ease-tap'] = ease === '' ? 'MISSING' : ease;
    return out;
  }, TOKENS);

  console.log(JSON.stringify(res, null, 1));
  const missing = Object.entries(res).filter(([, v]) => v === 'MISSING');
  await browser.close();
  if (missing.length) {
    console.error(`FAIL: ${missing.length} token(s) unresolved: ${missing.map(([k]) => k).join(', ')}`);
    process.exit(1);
  }
  console.log('OK: all design tokens resolve');
})().catch((e) => { console.error('FATAL', e); process.exit(1); });
