// Season UX: the accordions are purely visual (expanding one must NOT move the banner), the banner is
// pinned to series-wide progress, and the per-season completion toggle is two-way.
import { chromium } from "playwright-core";
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

  const launchOptions = {
    channel: process.env.TS_BROWSER_CHANNEL || (process.platform === 'win32' ? 'msedge' : undefined),
    headless: true
  };
  const browser = await chromium.launch(launchOptions);
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

    // The banner action is the button whose name ends in "S1E1" / "S2E1" - ASCII, so it survives
    // either UI language.
    const banner = () => page.getByRole('button', { name: /S\d+E\d+/ }).first();
    const header = async () => (await banner().count()) ? flat(await banner().innerText()) : '(none)';

    ok('banner starts at S1E1 ("' + (await header()) + '")', (await header()).includes('S1E1'));

    // Season ribbon: select Season 1 and complete it through the season action button.
    const seasonCard = () => page.getByRole('button', { name: /(\u0421\u0435\u0437\u043e\u043d 1|Season 1)/ }).first();
    const seasonAction = () => page.getByRole('button', { name: /(\u041e\u0442\u043c\u0435\u0442\u0438\u0442\u044c \u0441\u0435\u0437\u043e\u043d|Mark season)/ }).first();
    const seasonClear = () => page.getByRole('button', { name: /(\u0421\u043d\u044f\u0442\u044c \u0441\u0435\u0437\u043e\u043d|Clear season)/ }).first();

    await seasonCard().click();
    await page.waitForTimeout(300);
    ok('season action visible for the active season', (await seasonAction().count()) === 1);

    // Completing season 1 through its action; the banner must roll to S2E1 with no further input.
    await seasonAction().click();
    await page.waitForTimeout(1800);
    const afterEye = await page.evaluate(async (m) => (await fetch('/api/media/' + m)).json(), id);
    ok('season action stored S1 7/7 (' + afterEye.seasons[0].currentEpisode + ')', afterEye.seasons[0].currentEpisode === 7);
    ok('season action stored S1 completed (' + afterEye.seasons[0].status + ')', afterEye.seasons[0].status === 2);
    ok('banner rolled to S2E1 ("' + (await header()) + '")', (await header()).includes('S2E1'));

    // Two-way toggle: clearing the finished season rolls it back to 0.
    await seasonClear().click();
    await page.waitForTimeout(1500);
    const afterReset = await page.evaluate(async (m) => (await fetch('/api/media/' + m)).json(), id);
    ok('clear rolled S1 back to 0 (' + afterReset.seasons[0].currentEpisode + ')', afterReset.seasons[0].currentEpisode === 0);
    ok('clear rolled S1 back out of completed (' + afterReset.seasons[0].status + ')', afterReset.seasons[0].status !== 2);

    // Put it back so the next-up assertions below still start from a completed S1.
    await seasonAction().click();
    await page.waitForTimeout(1500);

    // Next-up keeps walking inside the season it rolled into.
    await banner().click();
    await page.waitForTimeout(1800);
    ok('banner advanced to S2E2 ("' + (await header()) + '")', (await header()).includes('S2E2'));

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



