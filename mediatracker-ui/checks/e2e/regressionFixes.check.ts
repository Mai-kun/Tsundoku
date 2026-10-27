import { chromium } from "playwright";
import fs from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";

const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);
const base = process.env.TRACKER_URL || "http://127.0.0.1:5000";
const shots = path.resolve(__dirname, "../../shots");
fs.mkdirSync(shots, { recursive: true });

const browser = await chromium.launch({ headless: true });
const context = await browser.newContext({
  viewport: { width: 1440, height: 900 },
});
const page = await context.newPage();

await page.addInitScript(() => {
  const originalFetch = window.fetch;
  window.fetch = (...args: [RequestInfo | URL, RequestInit?]) => {
    const request = args[0];
    const options = args[1] || {};
    const calls: Array<{ url: string; keepalive: boolean; method: string }> = JSON.parse(
      localStorage.getItem("progressFetchCalls") || "[]",
    );
    calls.push({
      url: String(request),
      keepalive: options.keepalive === true,
      method: options.method || "GET",
    });
    localStorage.setItem("progressFetchCalls", JSON.stringify(calls));
    return originalFetch(...args);
  };
});

const api = async (requestPath: string, options: Parameters<typeof page.request.fetch>[1] = {}) =>
  page.request.fetch(base + requestPath, options);

const json = async <T = any>(requestPath: string, options: Parameters<typeof page.request.fetch>[1] = {}): Promise<T> => {
  const response = await api(requestPath, options);
  if (!response.ok()) throw new Error(await response.text());
  return response.json() as Promise<T>;
};

const voidRequest = async (requestPath: string, options: Parameters<typeof page.request.fetch>[1] = {}) => {
  const response = await api(requestPath, options);
  if (!response.ok()) throw new Error(await response.text());
};

const log = (name: string, value: unknown) => console.log(`[${name}] ${value}`);
const assert = (condition: unknown, message: string): asserts condition => {
  if (!condition) throw new Error(message);
};

await page.goto(base);
await page.waitForLoadState("domcontentloaded");
log("server", "reachable");

// (a) F5 while debounce is active
const book = await json<{ id: string; title: string }>("/api/media", {
  method: "POST",
  headers: { "content-type": "application/json" },
  data: JSON.stringify({
    type: "book",
    title: `Regression book ${Date.now()}`,
    status: 1,
    totalPages: 20,
    author: "Test",
  }),
});
await page.goto(base + "/?view=book");
await page.waitForLoadState("domcontentloaded");
const bookCard = page
  .locator("article")
  .filter({ hasText: book.title })
  .first();
await bookCard.waitFor({ state: "visible", timeout: 10000 });
const plusButton = bookCard.locator("button:has(svg.lucide-plus)");
const reloadStartedAt = Date.now();
await Promise.all([
  plusButton.click({ force: true }),
  plusButton.click({ force: true }),
  plusButton.click({ force: true }),
]);
const elapsedBeforeReload = Date.now() - reloadStartedAt;
await page.reload();
await page.waitForTimeout(700);
const keepaliveCalls = await page.evaluate(() =>
  JSON.parse(localStorage.getItem("progressFetchCalls") || "[]"),
);
const bookProgressCall = keepaliveCalls.find(
  (call: { url: string; method: string; keepalive: boolean }) =>
    call.url.includes("/api/media/" + book.id + "/progress") &&
    call.method === "PUT" &&
    call.keepalive,
);
assert(
  elapsedBeforeReload < 375,
  "reload happened after debounce window: " + elapsedBeforeReload + "ms",
);
assert(
  bookProgressCall,
  "keepalive progress request not observed: " + JSON.stringify(keepaliveCalls),
);
const bookAfter = await json<{ currentPage: number }>(`/api/media/${book.id}`);
assert(
  bookAfter.currentPage === 3,
  `F5 debounce failed: ${bookAfter.currentPage}`,
);
await page.screenshot({
  path: `${shots}/regression_a_f5_debounce.png`,
  fullPage: true,
});
log("a F5 debounce", `saved currentPage=${bookAfter.currentPage}`);

// stale callback / filtering: verify the card that moved still sends to its own id
const other = await json<{ id: string; title: string }>("/api/media", {
  method: "POST",
  headers: { "content-type": "application/json" },
  data: JSON.stringify({
    type: "book",
    title: `Other ${Date.now()}`,
    status: 1,
    totalPages: 20,
    author: "Test",
  }),
});
await page.reload();
await page.waitForTimeout(500);
const target = page.locator("article").filter({ hasText: book.title });
await target.locator("button:has(svg.lucide-plus)").click();
await page.waitForTimeout(500);
const bookCheck = await json<{ currentPage: number }>(`/api/media/${book.id}`);
const otherCheck = await json<{ currentPage: number }>(`/api/media/${other.id}`);
assert(
  bookCheck.currentPage === 4 && otherCheck.currentPage === 0,
  `wrong id after rerender: ${bookCheck.currentPage}/${otherCheck.currentPage}`,
);
log(
  "stale callback check",
  `target=${book.id} currentPage=${bookCheck.currentPage}, other=${other.id} currentPage=${otherCheck.currentPage}`,
);

// (b) all seasons complete
const show = await json<{ id: string }>("/api/media", {
  method: "POST",
  headers: { "content-type": "application/json" },
  data: JSON.stringify({
    type: "tvshow",
    title: `Regression show ${Date.now()}`,
    status: 1,
    seasons: [
      { seasonNumber: 1, title: "S1", totalEpisodes: 2, status: 0 },
      { seasonNumber: 2, title: "S2", totalEpisodes: 2, status: 0 },
    ],
  }),
});
const showAfterCreate = await json<{ seasons: Array<{ id: string; totalEpisodes: number }> }>(`/api/media/${show.id}`);
for (const s of showAfterCreate.seasons)
  await voidRequest(`/api/seasons/${s.id}/progress`, {
    method: "PUT",
    headers: { "content-type": "application/json" },
    data: JSON.stringify({ currentEpisode: s.totalEpisodes }),
  });
const completedShow = await json<{ status: number; finishedAt: string | null; seasons: Array<{ id: string }> }>(`/api/media/${show.id}`);
assert(
  completedShow.status === 2 && completedShow.finishedAt,
  "all seasons did not complete show",
);
await page.goto(`${base}/?view=seasons&mediaId=${show.id}`);
await page.waitForLoadState("domcontentloaded");
await page.screenshot({
  path: `${shots}/regression_b_tvshow_completed.png`,
  fullPage: true,
});
log(
  "b TvShow complete",
  `status=${completedShow.status}, finishedAt=${completedShow.finishedAt}`,
);

// (c) rollback
const targetSeason = completedShow.seasons[0];
await voidRequest(`/api/seasons/${targetSeason.id}/progress`, {
  method: "PUT",
  headers: { "content-type": "application/json" },
  data: JSON.stringify({ currentEpisode: 1 }),
});
const rolledBack = await json<{ status: number; finishedAt: string | null }>(`/api/media/${show.id}`);
assert(
  rolledBack.status === 1 && rolledBack.finishedAt === null,
  `rollback failed: ${rolledBack.status}/${rolledBack.finishedAt}`,
);
await page.reload();
await page.waitForTimeout(700);
await page.screenshot({
  path: `${shots}/regression_c_tvshow_rollback.png`,
  fullPage: true,
});
log(
  "c TvShow rollback",
  `status=${rolledBack.status}, finishedAt=${rolledBack.finishedAt}`,
);

// (d) edit through real browser click and verify UI + GET
await page.goto(`${base}/?view=book`);
await page.waitForLoadState("domcontentloaded");
const card = page.locator("article").filter({ hasText: book.title });
await card.getByRole("button", { name: "Edit" }).click();
const titleInput = page.locator("[role=dialog] input").first();
const newTitle = `${book.title} edited`;
await titleInput.fill(newTitle);
await Promise.all([
  page.waitForResponse(
    (response) =>
      response.url().includes("/api/media/" + book.id) &&
      response.request().method() === "PUT",
  ),
  page.locator("[role=dialog] button[type=submit]").click(),
]);
await page.waitForLoadState("domcontentloaded");
const edited = await json<{ title: string }>(`/api/media/${book.id}`);
assert(edited.title === newTitle, `DB edit failed: ${edited.title}`);
await page.goto(`${base}/?view=book`);
await page.waitForLoadState("domcontentloaded");
assert(
  (await page.locator("article").filter({ hasText: newTitle }).count()) === 1,
  "edited title not visible in UI",
);
await page.screenshot({
  path: `${shots}/regression_d_edit_card.png`,
  fullPage: true,
});
log("d edit card", `UI and GET title=${edited.title}`);

await browser.close();
console.log("ALL 4 REGRESSION SCENARIOS PASSED");
