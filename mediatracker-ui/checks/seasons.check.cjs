// Season UX: the per-season eye closes a season out, and the banner's "next up" rolls from S1 to S2
// on its own and expands the season it lands in.
const { chromium } = require('playwright-core');
const BASE = process.env.TS_BASE || 'http://localhost:5099';

(async () => {
  const fails = [];
  const ok = (l, c) => { if (!c) fails.push(l); console.log((c ? 'ok   ' : 'FAIL ') + l); };
  const flat = (s) => s.replace(/\s+/g, ' ').trim();

  const id = (await fetch(BASE + '/api/media', {
    method: 'POST', headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({
      type: 'tvshow', title: 'Verify Show', status: 0, isAnime: true, durationMinutes: 24,
      seasons: [
        { seasonNumber: 1, title: 'Season 1', totalEpisodes: 7, status: 0 },
        { seasonNumber: 2, title: 'Season 2', totalEpisodes: 3, status: 0 },
      ],
    }),
  }).then((r) => r.json())).id;

  const browser = await chromium.launch({ channel: 'msedge' });
  const page = await browser.newPage({ viewport: { width: 1440, height: 1000 } });
  page.setDefaultTimeout(9000);
  const errors = [];
  page.on('pageerror', (e) => errors.push(e.message));

  try {
    await page.goto(BASE + '/?view=detail&mediaId=' + id, { waitUntil: 'domcontentloaded' });
    await page.waitForTimeout(2000);

    // The per-season accordions live on the Episodes tab; the banner shows on every tab.
    await page.getByRole('button', { name: /(\u042d\u043f\u0438\u0437\u043e\u0434\u044b|Episodes)/ }).first().click();
    await page.waitForTimeout(900);

    // The banner action is the button whose name ends in "S1 E1" / "S2 E1" - ASCII, so it survives
    // either UI language.
    const banner = () => page.getByRole('button', { name: /S\d+ E\d+/ }).first();
    const header = async () => (await banner().count()) ? flat(await banner().innerText()) : '(none)';

    ok('banner starts at S1 E1 ("' + (await header()) + '")', (await header()).includes('S1 E1'));

    const eyes = page.locator('details').first().locator('summary button[aria-label]');
    ok('every unfinished season has an eye (' + (await eyes.count()) + ')', (await eyes.count()) === 1);

    // The eye closes season 1 out; the banner must roll to S2 E1 with no further input.
    await eyes.click();
    await page.waitForTimeout(1800);
    const afterEye = await page.evaluate(async (m) => (await fetch('/api/media/' + m)).json(), id);
    ok('eye stored S1 7/7 (' + afterEye.seasons[0].currentEpisode + ')', afterEye.seasons[0].currentEpisode === 7);
    ok('eye stored S1 completed (' + afterEye.seasons[0].status + ')', afterEye.seasons[0].status === 2);
    ok('banner rolled to S2 E1 ("' + (await header()) + '")', (await header()).includes('S2 E1'));

    const openTitle = flat(await page.locator('details[open] summary').first().innerText());
    ok('S2 accordion auto-expanded ("' + openTitle + '")', openTitle.includes('Season 2'));

    // Next-up keeps walking inside the season it rolled into.
    await banner().click();
    await page.waitForTimeout(1800);
    ok('banner advanced to S2 E2 ("' + (await header()) + '")', (await header()).includes('S2 E2'));

    const detail = await page.evaluate(async (m) => (await fetch('/api/media/' + m)).json(), id);
    ok('S1 stored 7/7 (' + detail.seasons[0].currentEpisode + ')', detail.seasons[0].currentEpisode === 7);
    ok('S1 stored completed (' + detail.seasons[0].status + ')', detail.seasons[0].status === 2);
    ok('S2 stored 1/3 (' + detail.seasons[1].currentEpisode + ')', detail.seasons[1].currentEpisode === 1);
  } catch (error) {
    fails.push('exception: ' + error.message.split('\n')[0]);
    console.log('BODY:', (await page.locator('body').innerText().catch(() => '?')).replace(/\s+/g, ' ').slice(0, 220));
  }

  await browser.close();
  if (errors.length) fails.push('page errors: ' + errors.join(' | '));
  console.log(fails.length ? 'RESULT FAIL\n  - ' + fails.join('\n  - ') : 'RESULT OK');
})();

