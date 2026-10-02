// Verifies the fixed mobile bottom nav never traps content: after scrolling the
// main area to the very bottom, the last element must clear the nav's top edge.
const { chromium } = require('playwright-core');
const BASE = process.env.TS_BASE || 'http://localhost:5000';
const ID = '46b9df89-bfed-4da9-b802-474fb55a8018';

(async () => {
  const browser = await chromium.launch({ channel: 'msedge' });
  const page = await browser.newPage({ viewport: { width: 390, height: 844 } });
  await page.goto(`${BASE}/?view=detail&mediaId=${ID}`, { waitUntil: 'domcontentloaded' });
  await page.waitForTimeout(1500);

  const result = await page.evaluate(async () => {
    const main = document.getElementById('main-scroll');
    main.scrollTop = main.scrollHeight;
    await new Promise((r) => setTimeout(r, 600));

    const nav = document.querySelector('aside').getBoundingClientRect();
    const last = main.querySelector('main > *:last-child') || main.lastElementChild;
    const box = last.getBoundingClientRect();

    return {
      navTop: Math.round(nav.top),
      lastBottom: Math.round(box.bottom),
      clearance: Math.round(nav.top - box.bottom),
      scrollTop: main.scrollTop,
      atBottom: main.scrollTop + main.clientHeight >= main.scrollHeight - 2,
    };
  });

  console.log(JSON.stringify(result));
  await browser.close();
  if (!result.atBottom || result.clearance < 0) {
    console.error('FAIL: bottom content is trapped under the mobile nav');
    process.exit(1);
  }
  console.log('OK: bottom content clears the mobile nav');
})().catch((e) => { console.error('FATAL', e); process.exit(1); });
