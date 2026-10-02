// The card status badge opens on CLICK only -- hovering it must do nothing, so the pointer can
// travel across a grid of cards without menus flashing open. Verify both halves: hover stays
// closed, a click opens it, and the menu is positioned under its trigger.
const { chromium } = require('playwright-core');
const BASE = process.env.TS_BASE || 'http://localhost:5000';

(async () => {
  const browser = await chromium.launch({ channel: 'msedge' });
  const page = await browser.newPage({ viewport: { width: 1440, height: 900 } });
  const errors = [];
  page.on('pageerror', (e) => errors.push(e.message));

  await page.goto(BASE + '/?view=home', { waitUntil: 'domcontentloaded' });
  await page.waitForTimeout(1500);

  const card = page.locator('article').first();
  const trigger = card.locator('button[popovertarget]').first();
  await trigger.waitFor({ state: 'visible', timeout: 15000 });
  const title = await trigger.getAttribute('title');
  const t = await trigger.boundingBox();

  const isOpen = () =>
    page.locator('[popover]:popover-open').first().isVisible().catch(() => false);

  // 1. Hovering must NOT open it.
  await trigger.hover();
  await page.waitForTimeout(500);
  const openedOnHover = await isOpen();

  // 2. A click must open it.
  await trigger.click();
  const menu = page.locator('[popover]:popover-open').first();
  const opened = await menu
    .waitFor({ state: 'visible', timeout: 5000 })
    .then(() => true)
    .catch(() => false);

  let m = null;
  let opaque = null;
  if (opened) {
    await page.waitForTimeout(300);
    m = await menu.boundingBox();
    opaque = await menu.evaluate((el) => getComputedStyle(el).backgroundColor);
  }

  console.log(JSON.stringify({ title, trigger: t, menu: m, openedOnHover, opened, opaque, errors }, null, 1));
  await browser.close();

  if (openedOnHover) {
    console.error('FAIL: status popover opened on hover; it must be click-only');
    process.exit(1);
  }
  if (!opened) { console.error('FAIL: status popover did not open on click'); process.exit(1); }
  if (Math.abs(m.x - t.x) > 2) { console.error(`FAIL: menu misaligned x=${m.x} vs trigger ${t.x}`); process.exit(1); }
  if (m.y < t.y + t.height - 1) { console.error(`FAIL: menu opened above its trigger`); process.exit(1); }
  console.log('OK: status popover is click-only, aligned under its trigger');
})().catch((e) => { console.error('FATAL', e); process.exit(1); });
