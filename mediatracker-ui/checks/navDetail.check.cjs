// Navigation must work without F5. The regression this guards: AppShell used to hide the view area
// until a settle check counted <main>'s direct children down to 1, but MediaDetailView renders four
// top-level nodes (root + three modals), so the count never reached 1, the area stayed `invisible`
// and the detail page only appeared after a reload. Assert the screen is visible on its own.
const { chromium } = require('playwright-core');
const BASE = process.env.TS_BASE || 'http://localhost:5000';

(async () => {
  const fails = [];
  const ok = (l, c) => { if (!c) fails.push(l); console.log((c ? 'ok   ' : 'FAIL ') + l); };

  const browser = await chromium.launch({ channel: 'msedge' });
  const page = await browser.newPage({ viewport: { width: 1440, height: 900 } });
  page.setDefaultTimeout(12000);
  const errors = [];
  page.on('pageerror', (e) => errors.push(e.message));

  try {
    await page.goto(`${BASE}/?view=home`, { waitUntil: 'domcontentloaded' });
    await page.waitForTimeout(2500);

    const card = page.locator('article.media-card').first();
    await card.waitFor({ state: 'visible', timeout: 15000 });
    // The title is the card's own first line of text; the aria-label is localised, so parsing it
    // would make this check language-dependent.
    const title = (await card.innerText()).split('\n')[0].trim();

    await card.click();

    const url = page.url();
    ok('url switched to the detail route', /view=detail/.test(url) && /mediaId=/.test(url));

    // The detail screen has to show up by itself, with no reload.
    await page.waitForTimeout(1800);
    const state = await page.evaluate(() => {
      const main = document.getElementById('main-scroll');
      const style = getComputedStyle(main);
      return {
        visibility: style.visibility,
        display: style.display,
        text: (main.innerText || '').replace(/\s+/g, ' ').trim(),
      };
    });

    ok('view area is visible (was `invisible` after the bug)', state.visibility === 'visible');
    ok('view area is displayed', state.display !== 'none');
    ok('detail content rendered', state.text.length > 40);
    ok('the clicked title is on screen', title.length > 0 && state.text.includes(title.slice(0, 12)));

    // The back button returns to the library, still without a reload.
    await page.getByRole('button', { name: /Back|Назад/i }).first().click();
    await page.waitForTimeout(1200);
    ok('back returns to the library', !/view=detail/.test(page.url()));

    // Escape must also leave the detail view.
    await card.click();
    await page.waitForTimeout(1400);
    await page.keyboard.press('Escape');
    await page.waitForTimeout(900);
    ok('escape leaves the detail view', !/view=detail/.test(page.url()));
  } catch (error) {
    fails.push('exception: ' + error.message.split('\n')[0]);
  }

  await browser.close();
  if (errors.length) fails.push('page errors: ' + errors.join(' | '));
  console.log(fails.length ? 'RESULT FAIL\n  - ' + fails.join('\n  - ') : 'RESULT OK');
  if (fails.length) process.exitCode = 1;
})();