// Verifies the external-rating skeleton resolves (isEnriching must settle).
const { chromium } = require('playwright-core');
const BASE = 'http://localhost:5000';
const ID = '46b9df89-bfed-4da9-b802-474fb55a8018';

(async () => {
  const browser = await chromium.launch({ channel: 'msedge' });
  const page = await browser.newPage({ viewport: { width: 1440, height: 900 } });
  await page.goto(`${BASE}/?view=detail&mediaId=${ID}`, { waitUntil: 'domcontentloaded' });

  for (const wait of [1500, 5000, 10000]) {
    await page.waitForTimeout(wait === 1500 ? 1500 : wait - 1500);
    const badges = await page.evaluate(() =>
      Array.from(document.querySelectorAll('[title]'))
        .filter((el) => /anilist|mal|kitsu|shikimori/i.test(el.getAttribute('title') || ''))
        .map((el) => ({ title: el.getAttribute('title'), text: el.textContent.trim(), hasSkeleton: !!el.querySelector('.animate-pulse') }))
    );
    console.log(`t=${wait}ms`, JSON.stringify(badges));
  }
  await browser.close();
})().catch((e) => { console.error('FATAL', e); process.exit(1); });
