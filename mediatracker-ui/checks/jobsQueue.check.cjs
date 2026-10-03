// Regression guard for the background queue + Activity Center: adding a title from
// search must answer immediately, the header icon must badge and open a panel that
// lists the running job, and the card must show the sync overlay while it runs.
// Run: `npm run check:jobs` (needs the app on :5000, like the other browser checks).
const { chromium } = require("playwright-core");

const BASE = process.env.TS_BASE || "http://localhost:5000";
const QUERY = process.env.TS_JOB_QUERY || "Steins;Gate";

const fail = [];
const expect = (name, ok, extra) => {
  if (!ok) fail.push({ name, extra });
  return ok;
};

(async () => {
  const browser = await chromium.launch({ channel: "msedge" });
  const page = await browser.newPage({ viewport: { width: 1440, height: 900 } });
  const errors = [];
  page.on("pageerror", (e) => errors.push(e.message));

  await page.goto(BASE + "/?view=home", { waitUntil: "domcontentloaded" });
  await page.waitForTimeout(1200);

  // A queued job must reach the browser over SSE without any polling, so the trigger is
  // read before anything is added: no badge, no spinner.
  const trigger = page.locator('button[popovertarget="activity-popover"]');
  await trigger.waitFor({ state: "visible", timeout: 15000 });
  expect(
    "badge hidden while idle",
    (await trigger.locator("span").count()) === 0,
  );

  // The real flow: search a title, hit "Add", and watch the draft land in the grid.
  // Re-runnable: search results are ordered by the providers, so a title added by an earlier run
  // comes back already in the library. Clear it before the UI flow, not after — the modal's own
  // "in library" state is client-side and only a reload resets it.
  const stale = await page.request
    .get(`${BASE}/api/media?search=${encodeURIComponent(QUERY)}`)
    .then((r) => r.json());
  for (const item of stale) {
    await page.request.delete(`${BASE}/api/media/${item.id}`);
  }

  await page.keyboard.press("Control+k");
  const input = page.locator('input[type="search"]');
  await input.waitFor({ state: "visible", timeout: 5000 });
  await input.fill(QUERY);

  // The search modal is a native <dialog>, whose role is implicit rather than an attribute.
  const result = page.locator("dialog[open] h4[title]").first();
  await result
    .waitFor({ state: "visible", timeout: 45000 })
    .catch(() => {
      throw new Error(
        "no search results rendered: " +
          (page.locator("dialog[open]").innerText().slice(0, 400) || "<empty>"),
      );
    });
  const title = await result.getAttribute("title");

  const row = result.locator("xpath=ancestor::*[@role='button'][1]");
  await row.locator('button[title="Добавить"], button[title="Add"]').click();

  // The modal must not wait on the provider: the draft row is already enough to render.
  const modalGone = await page
    .locator("dialog[open]")
    .first()
    .waitFor({ state: "hidden", timeout: 5000 })
    .then(() => true)
    .catch(() => false);
  expect("search modal closes immediately", modalGone);

  const card = page.locator("article", { hasText: title }).first();
  await card.waitFor({ state: "visible", timeout: 15000 });
  const overlay = await card
    .locator("text=/Синхронизация|Syncing/")
    .first()
    .isVisible()
    .catch(() => false);
  expect("card shows sync overlay", overlay);

  await page.waitForTimeout(1500);
  expect(
    "badge appears over SSE",
    (await trigger.locator("span").innerText()).trim() === "1",
  );

  await trigger.click();
  const panel = page.locator("#activity-popover:popover-open");
  const opened = await panel
    .waitFor({ state: "visible", timeout: 5000 })
    .then(() => true)
    .catch(() => false);
  expect("panel opens", opened);

  let bar = null;
  let palette = null;
  if (opened) {
    await page.waitForTimeout(600);
    bar = await panel.locator('[role="progressbar"]').first().boundingBox();
    palette = await panel.evaluate((el) => getComputedStyle(el).backgroundColor);
    expect(
      "panel lists the running job",
      (await panel.locator("li").count()) >= 1,
    );
  }

  // The card itself must stay clickable while it syncs: the detail screen opens at once and
  // only the poster / season blocks show skeletons.
  await card.click();
  await page.waitForTimeout(1500);
  const detailOpen = page.url().includes("mediaId=");
  expect("syncing card is still clickable", detailOpen, page.url());

  const posterWaiting = await page
    .locator("text=/Загрузка обложки|Loading cover/")
    .first()
    .isVisible()
    .catch(() => false);
  console.log("poster skeleton visible:", posterWaiting);
  await page.screenshot({
    path: "shots/qa/jobs-syncing-detail.png",
    fullPage: false,
  });

  // Cancellation is the one branch that cannot be observed from the panel: the job is usually
  // already done by the time the click lands. Assert the endpoint answers instead.
  const cancelStatus = await page.request
    .post(`${BASE}/api/jobs/00000000-0000-0000-0000-000000000000/cancel`)
    .then((r) => r.status());
  expect("cancel of an unknown job is 404", cancelStatus === 404, cancelStatus);

  console.log(
    JSON.stringify({ title, bar, palette, detailOpen, errors, fail }, null, 1),
  );
  await browser.close();

  if (errors.length) {
    console.error("FAIL: page errors", errors);
    process.exit(1);
  }
  if (fail.length) {
    console.error("FAIL", fail);
    process.exit(1);
  }
  console.log(
    "OK: draft row is Syncing, badge and panel track the job over SSE, card stays clickable",
  );
})().catch((e) => {
  console.error("FATAL", e);
  process.exit(1);
});