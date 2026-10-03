// Related tab: the source picker is a styled popover rather than a native select, and a list loaded
// earlier is still there after a reload.
const { chromium } = require('playwright-core');
const BASE = process.env.TS_BASE || 'http://localhost:5099';

(async () => {
  const fails = [];
  const ok = (l, c) => { if (!c) fails.push(l); console.log((c ? 'ok   ' : 'FAIL ') + l); };

  const created = await fetch(BASE + '/api/media', {
    method: 'POST', headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ type: 'manga', title: 'Noragami', status: 0, totalChapters: 109, totalVolumes: 27, externalId: 'relink-test', externalSource: 'MangaDex' }),
  }).then((r) => r.json());
  const id = created.id;

  const stored = [
    { id: 'ext-1', title: 'Noragami+: Ashes of Autumn', coverUrl: null, type: 'manga', relationType: 'Side story', rawRelationType: 'SIDE_STORY' },
    { id: 'ext-2', title: 'Noragami - Stray Stories', coverUrl: null, type: 'manga', relationType: 'Adaptation', rawRelationType: 'ADAPTATION' },
  ];
  await fetch(BASE + '/api/media/' + id, {
    method: 'PUT', headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ relatedMediaJson: JSON.stringify(stored), relatedSource: 'MangaDex' }),
  });

  const browser = await chromium.launch({ channel: 'msedge' });
  const page = await browser.newPage({ viewport: { width: 1440, height: 1000 } });
  page.setDefaultTimeout(9000);
  const errors = [];
  page.on('pageerror', (e) => errors.push(e.message));
  page.on('console', (m) => { const t = m.text(); if (t.includes('[DBG]') || t.includes('MediaDetailView')) console.log('CONSOLE:', t); });

  try {
    await page.goto(BASE + '/?view=detail&mediaId=' + id, { waitUntil: 'domcontentloaded' });
    await page.waitForTimeout(1800);
    await page.getByRole('button', { name: /(\u0421\u0432\u044f\u0437\u0430\u043d\u043d)/ }).first().click();
    await page.waitForTimeout(700);

    const seen = await page.evaluate(async (m) => { const d = await (await fetch('/api/media/' + m)).json(); return { json: d.relatedMediaJson, src: d.relatedSource }; }, id);
    console.log('BROWSER SEES:', JSON.stringify(seen));
    const secs = await page.locator('section').allInnerTexts();
    console.log('SECTIONS:', secs.length);
    secs.forEach((s, i) => console.log('  #' + i + ': ' + s.replace(/\s+/g, ' ').slice(0, 160)));
    const body = await page.locator('body').innerText();
    ok('stored related survive a reload', body.includes('Noragami+') && body.includes('Stray Stories'));

    const trigger = page.locator('button[popovertarget^="popover-relation-source"]');
    ok('source picker is a popover trigger', (await trigger.count()) === 1);
    ok('no native <select> inside the related panel', (await page.locator('section').last().locator('select').count()) === 0);
    if (await trigger.count()) {
      const label = (await trigger.first().innerText()).replace(/\s+/g, ' ').trim();
      ok('source button names MangaDex ("' + label + '")', label.includes('MangaDex'));
      ok('source button stays enabled after a load', await trigger.first().isEnabled());
      const bg = await trigger.first().evaluate((el) => getComputedStyle(el).backgroundColor);
      ok('source button is Steam Deck grey (' + bg + ')', bg === 'rgb(28, 32, 43)');
      await trigger.first().click();
      const menu = page.locator('[popover]:popover-open').first();
      const opened = await menu.waitFor({ state: 'visible', timeout: 4000 }).then(() => true).catch(() => false);
      ok('source menu opens after a load', opened);
      if (opened) {
        const mbg = await menu.evaluate((el) => getComputedStyle(el).backgroundColor);
        ok('menu is dark (' + mbg + ')', mbg === 'rgb(38, 43, 58)');
        const options = await page.locator('[popover]:popover-open [role="option"]').allInnerTexts();
        ok('menu still lists providers (' + options.length + ')', options.length >= 2);
      }
    }
  } catch (error) {
    fails.push('exception: ' + error.message.split('\n')[0]);
    console.log('BODY:', (await page.locator('body').innerText().catch(() => '?')).replace(/\s+/g, ' ').slice(0, 260));
  }

  await browser.close();
  if (errors.length) fails.push('page errors: ' + errors.join(' | '));
  console.log(fails.length ? 'RESULT FAIL\n  - ' + fails.join('\n  - ') : 'RESULT OK');
})();






