// Achievements are external data. The only sanctioned fetches are on add and on an explicit
// metadata refresh, so the card must NOT offer a third "load achievements" button. The
// "mark all / unmark all" control only writes to our own API, so it stays.
const { chromium } = require('playwright-core');
const BASE = process.env.TS_BASE || 'http://localhost:5000';

(async () => {
  const browser = await chromium.launch({ channel: 'msedge' });
  const page = await browser.newPage({ viewport: { width: 1440, height: 1000 } });

  // Grand Theft Auto V is a rated game in this DB, so the achievements panel renders.
  await page.goto(`${BASE}/?view=game`, { waitUntil: 'domcontentloaded' });
  await page.waitForTimeout(2500);
  await page.locator('article').first().click();
  await page.waitForTimeout(3000);

  const body = await page.evaluate(() => document.body.innerText);
  const hasLoadButton =
    body.includes('Загрузить достижения') || body.includes('Load achievements');
  const hasMarkAll =
    body.includes('Отметить все') || body.includes('Unmark all') || body.includes('Mark all');

  console.log(JSON.stringify({ hasLoadButton, hasMarkAll }));
  await browser.close();

  if (hasLoadButton) {
    console.error('FAIL: "Load achievements" button still present');
    process.exit(1);
  }
  if (!hasMarkAll) {
    console.error('FAIL: "Mark all / Unmark all" control is missing');
    process.exit(1);
  }
  console.log('OK: no achievements fetch button; mark/unmark all retained');
})().catch((e) => { console.error('FATAL', e); process.exit(1); });