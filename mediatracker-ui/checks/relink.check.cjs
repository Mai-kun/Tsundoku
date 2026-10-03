﻿// A provider that fails leaves a dark error block with a retry (the RAWG game path, which surfaces
// API failures rather than swallowing them), and the detail screen offers "change source".
const { chromium } = require('playwright-core');
const BASE = process.env.TS_BASE || 'http://localhost:5099';

(async () => {
  const fails = [];
  const ok = (l, c) => { if (!c) fails.push(l); console.log((c ? 'ok   ' : 'FAIL ') + l); };

  const id = (await fetch(BASE + '/api/media', {
    method: 'POST', headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ type: 'tvshow', title: 'Severance', status: 0, externalId: 'sev-test', externalSource: 'TMDb' }),
  }).then((r) => r.json())).id;

  const browser = await chromium.launch({ channel: 'msedge' });
  const page = await browser.newPage({ viewport: { width: 1440, height: 1000 } });
  page.setDefaultTimeout(9000);
  const errors = [];
  page.on('pageerror', (e) => errors.push(e.message));

  try {
    await page.route('**/api/external/relations**', (r) => r.abort('failed'));
    await page.goto(BASE + '/?view=detail&mediaId=' + id, { waitUntil: 'domcontentloaded' });
    await page.waitForTimeout(1800);
    await page.getByRole('button', { name: /(\u0421\u0432\u044f\u0437\u0430\u043d\u043d)/ }).first().click();
    await page.waitForTimeout(700);

    // The load button repeats the request for the selected source; with the relations endpoint down
    // that is the call that has to surface the error block.
    await page.getByRole('button', { name: /(\u0417\u0430\u0433\u0440\u0443\u0437\u0438\u0442\u044c \u0441\u0432\u044f\u0437\u0430\u043d\u043d\u044b\u0435|Load related)/ }).first().click();
    await page.waitForTimeout(2000);

    const alert = page.locator('div[role="alert"]').first();
    const hasAlert = await alert.count();
    ok('failing provider shows an error block', hasAlert === 1);
    if (hasAlert) {
      ok('error block offers a retry',
        (await page.getByRole('button', { name: /(\u041f\u043e\u043f\u0440\u043e\u0431\u043e\u0432\u0430\u0442\u044c \u0441\u043d\u043e\u0432\u0430|Try again)/ }).count()) > 0);
      const bg = await alert.evaluate((el) => getComputedStyle(el).backgroundColor);
      ok('error block is Steam Deck grey (' + bg + ')', bg === 'rgb(28, 32, 43)');
    }

    await page.getByRole('button', { name: /(\u0421\u043c\u0435\u043d\u0438\u0442\u044c \u0438\u0441\u0442\u043e\u0447\u043d\u0438\u043a)/ }).first().click();
    const dialog = page.locator('dialog[open]');
    ok('relink dialog opens', (await dialog.count()) === 1);
    ok('relink dialog is prefilled with the title',
      (await dialog.locator('input[type="search"]').inputValue()).includes('Severance'));
    ok('relink dialog names the current source', (await dialog.innerText()).includes('TMDb'));
  } catch (error) {
    fails.push('exception: ' + error.message.split('\n')[0]);
    console.log('BODY:', (await page.locator('body').innerText().catch(() => '?')).replace(/\s+/g, ' ').slice(0, 220));
  }

  await browser.close();
  if (errors.length) fails.push('page errors: ' + errors.join(' | '));
  console.log(fails.length ? 'RESULT FAIL\n  - ' + fails.join('\n  - ') : 'RESULT OK');
})();



