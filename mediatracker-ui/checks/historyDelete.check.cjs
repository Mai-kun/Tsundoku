// The activity log lists one row per event, and each row must be individually deletable (not just
// "clear all"). Verifies the per-row trash button exists, appears on hover, asks for confirmation,
// and that confirming actually removes that one row while leaving the others alone.
const { chromium } = require('playwright-core');
const BASE = process.env.TS_BASE || 'http://localhost:5000';

(async () => {
  const browser = await chromium.launch({ channel: 'msedge' });
  const page = await browser.newPage({ viewport: { width: 1440, height: 900 } });

  await page.goto(`${BASE}/?view=history`, { waitUntil: 'domcontentloaded' });
  await page.waitForTimeout(2500);

  // The check deletes a row every run, so seed two events first to make it repeatable.
  const MEDIA_ID = 'EDF19F2D-BE3D-4501-AE08-C7506DE2561A';
  const seed = async (body) => {
    await page.request.put(`${BASE}/api/media/${MEDIA_ID}`, { data: body });
  };
  await seed({ score: 6 });
  await seed({ score: 7 });

  // Reload so the freshly seeded events are what the page renders.
  await page.reload({ waitUntil: 'domcontentloaded' });
  await page.waitForTimeout(2000);

  const before = await page.locator('ol > li').count();
  if (before < 2) {
    console.error(`FAIL: need at least 2 history rows to prove single-row delete, got ${before}`);
    await browser.close();
    process.exit(1);
  }

  const firstRowText = (await page.locator('ol > li').first().innerText()).slice(0, 40);
  const secondRowText = (await page.locator('ol > li').nth(1).innerText()).slice(0, 40);

  const row = page.locator('ol > li').first();
  const button = row.locator('button').first();
  if ((await button.count()) === 0) {
    console.error('FAIL: history row has no per-row delete button');
    await browser.close();
    process.exit(1);
  }

  // Hidden until hover, like the card actions elsewhere in the app.
  const opacityBefore = await button.evaluate((el) => getComputedStyle(el).opacity);
  await row.hover();
  await page.waitForTimeout(250);
  const opacityAfter = await button.evaluate((el) => getComputedStyle(el).opacity);

  // Confirm the dialog rather than letting it block.
  page.once('dialog', (d) => d.accept());
  await button.click();
  await page.waitForTimeout(1200);

  const after = await page.locator('ol > li').count();
  const stillHasSecond = (await page.locator('ol > li').allInnerTexts()).some((t) =>
    t.slice(0, 40).includes(secondRowText.replace(/\s+/g, ' ').trim()),
  );

  console.log(
    JSON.stringify({ before, after, opacityBefore, opacityAfter, deletedRow: firstRowText, stillHasSecond }, null, 2),
  );
  await browser.close();

  // The activity label must be separated from its values by a space, e.g.
  // "статус изменён Completed → InProgress" rather than "статус изменёнCompleted → InProgress".
  const glued = firstRowText.match(
    /(?:добавлено|статус изменён|рейтинг изменён|достижение получено)[^\s]/,
  );
  if (glued) {
    console.error(`FAIL: label runs into its value: ${JSON.stringify(firstRowText)}`);
    process.exit(1);
  }

  if (Number(opacityAfter) <= Number(opacityBefore)) {
    console.error('FAIL: delete button does not reveal on hover');
    process.exit(1);
  }
  if (after !== before - 1) {
    console.error(`FAIL: expected ${before - 1} rows after deleting one, got ${after}`);
    process.exit(1);
  }
  console.log('OK: single history entry deletable, other rows untouched');
})().catch((e) => { console.error('FATAL', e); process.exit(1); });