// Games: achievements and recommendations live on the row, so F5 brings them back without another
// provider call, and a 1000-achievement title must not mount 1000 DOM nodes at once.
const { chromium } = require('playwright-core');
const BASE = process.env.TS_BASE || 'http://localhost:5000';

const TOTAL = 150;
const WINDOW = 60;

const achievements = {
  total: TOTAL,
  items: Array.from({ length: TOTAL }, (_, i) => ({
    name: `Achievement ${i + 1}`,
    description: `Reward number ${i + 1}`,
    iconUrl: null,
  })),
};

const recommendations = [
  { id: 'rec-1', title: 'Cached Recommendation', type: 'game', coverUrl: null, score: 8 },
];

(async () => {
  const fails = [];
  const ok = (l, c) => { if (!c) fails.push(l); console.log((c ? 'ok   ' : 'FAIL ') + l); };

  const created = await (
    await fetch(BASE + '/api/media', {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({
        type: 'game',
        title: 'Payload Cache Probe',
        status: 0,
        platform: 'PC',
        externalId: 'payload-probe',
        externalSource: 'RAWG',
      }),
    })
  ).json();
  const id = created.id;

  // Persistence goes through an update, exactly as the client does on the first provider fetch.
  await fetch(`${BASE}/api/media/${id}`, {
    method: 'PUT',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({
      achievementsJson: JSON.stringify(achievements),
      recommendationsJson: JSON.stringify(recommendations),
    }),
  });

  const stored = await (await fetch(`${BASE}/api/media/${id}`)).json();
  ok('server stored the achievements payload', !!stored.achievementsJson);
  ok('server stored the recommendations payload', !!stored.recommendationsJson);

  const browser = await chromium.launch({ channel: 'msedge' });
  const page = await browser.newPage({ viewport: { width: 1440, height: 1000 } });
  page.setDefaultTimeout(12000);
  const errors = [];
  page.on('pageerror', (e) => errors.push(e.message));

  // Any hit on the achievements endpoint means the panel went to the provider instead of the row.
  let providerCalls = 0;
  page.on('request', (r) => {
    if (r.url().includes('/api/external/games/achievements')) providerCalls++;
  });

  // Scoped to the achievement grid: a bare `button[title]` would also match the "mark all" control.
  const rows = () => page.locator('div.thin-scroll.grid > button[title]');

  try {
    await page.goto(`${BASE}/?view=detail&mediaId=${id}`, { waitUntil: 'domcontentloaded' });
    await page.waitForTimeout(2200);

    const mounted = await rows().count();
    ok(`only a window of rows is mounted (${mounted} of ${TOTAL})`, mounted === WINDOW);
    ok('no provider call on open', providerCalls === 0);

    const more = page.getByRole('button', { name: /Show \d+ more|Показать ещё \d+/i });
    ok('a "show more" control is offered', (await more.count()) === 1);
    if (await more.count()) {
      await more.first().click();
      await page.waitForTimeout(500);
      ok('clicking it grows the list', (await rows().count()) === WINDOW * 2);
    }

    // F5 is the whole point: the panel has to come back from the row.
    await page.reload({ waitUntil: 'domcontentloaded' });
    await page.waitForTimeout(2200);
    ok('achievements survive an F5', (await rows().count()) === WINDOW);
    ok('still no provider call after F5', providerCalls === 0);

    await page.getByRole('button', { name: /Рекомендации|Recommendations/i }).first().click();
    await page.waitForTimeout(900);
    ok('recommendations survive an F5', (await page.getByText('Cached Recommendation').count()) > 0);
  } catch (error) {
    fails.push('exception: ' + error.message.split('\n')[0]);
  }

  await browser.close();
  await fetch(`${BASE}/api/media/${id}`, { method: 'DELETE' });
  if (errors.length) fails.push('page errors: ' + errors.join(' | '));
  console.log(fails.length ? 'RESULT FAIL\n  - ' + fails.join('\n  - ') : 'RESULT OK');
  if (fails.length) process.exitCode = 1;
})();