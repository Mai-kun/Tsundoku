// Throwaway diagnostic (dev server): user-facing verification scenarios.
// 1. Home sections are capped (<=13 cards each), bounded DOM.
// 2. Status filter switch keeps the grid rendered (scrollMargin correctness).
// 3. Back-nav from detail keeps scroll + grid stable while the background
//    reload lands (no virtualizer reset).
const { chromium } = require("playwright-core");

const BASE = process.env.TS_BASE || "http://localhost:5173";

(async () => {
  const browser = await chromium.launch({ channel: "msedge" });
  const page = await browser.newPage({ viewport: { width: 1440, height: 900 } });
  const problems = [];
  page.on("pageerror", (e) => problems.push("pageerror: " + e.message.slice(0, 200)));
  page.on("console", (m) => {
    if (m.type() === "error") problems.push("console.error: " + m.text().slice(0, 300));
  });

  // --- 1. Home sections ---
  await page.goto(`${BASE}/?view=home`, { waitUntil: "domcontentloaded" });
  await page.waitForTimeout(2500);
  const home = await page.evaluate(() => {
    const main = document.getElementById("main-scroll");
    const sections = [...main.querySelectorAll("section")];
    return {
      nodeCount: document.getElementsByTagName("*").length,
      articles: main.querySelectorAll("article.media-card").length,
      sectionCards: sections.map((s) => s.querySelectorAll("article.media-card").length),
      sectionTitles: sections.map((s) => s.querySelector("h2")?.textContent?.trim()),
    };
  });
  console.log("HOME:", JSON.stringify(home, null, 2));
  if (home.articles > 42) problems.push(`home mounts too many cards: ${home.articles}`);
  for (const n of home.sectionCards) if (n > 14) problems.push(`home section over limit: ${n}`);

  // --- 2. Status filter keeps grids rendered (margin correctness) ---
  await page.goto(`${BASE}/?view=manga`, { waitUntil: "domcontentloaded" });
  await page.waitForTimeout(2500);
  const filterResult = await page.evaluate(async () => {
    const main = document.getElementById("main-scroll");
    const articlesBefore = main.querySelectorAll("article.media-card").length;
    const select = document.getElementById("library-status");
    select.value = "1"; // in progress
    select.dispatchEvent(new Event("change", { bubbles: true }));
    await new Promise((r) => setTimeout(r, 900));
    const articlesAfter = main.querySelectorAll("article.media-card").length;
    // Rows must sit inside their virtual container bounds (no stale margin).
    const badRows = [...main.querySelectorAll("[data-virtual-grid]")].flatMap((grid) => {
      const gridRect = grid.getBoundingClientRect();
      return [...grid.querySelectorAll(":scope > div")].filter((row) => {
        const rowRect = row.getBoundingClientRect();
        return (
          rowRect.height > 0 &&
          (rowRect.top < gridRect.top - 2 || rowRect.bottom > gridRect.bottom + 2)
        );
      }).length;
    });
    return { articlesBefore, articlesAfter, badRows };
  });
  console.log("FILTER:", JSON.stringify(filterResult, null, 2));
  if (filterResult.articlesAfter === 0)
    problems.push("status filter renders an empty grid");
  if (filterResult.badRows > 0)
    problems.push(`rows outside container after filter: ${filterResult.badRows}`);

  // --- 3. Back-nav from detail ---
  await page.goto(`${BASE}/?view=manga`, { waitUntil: "domcontentloaded" });
  await page.waitForTimeout(2500);
  await page.evaluate(() => {
    document.getElementById("main-scroll").scrollTop = 3000;
  });
  await page.waitForTimeout(600);
  const beforeOpen = await page.evaluate(() => {
    const main = document.getElementById("main-scroll");
    const cards = [...main.querySelectorAll("article.media-card")];
    const visibleCard = cards.find((c) => {
      const r = c.getBoundingClientRect();
      return r.top >= 100 && r.bottom <= 800;
    });
    return {
      scrollTop: main.scrollTop,
      cardTitle: visibleCard?.getAttribute("aria-label"),
    };
  });
  const cardHandle = await page.evaluateHandle(() => {
    const main = document.getElementById("main-scroll");
    const cards = [...main.querySelectorAll("article.media-card")];
    return cards.find((c) => {
      const r = c.getBoundingClientRect();
      return r.top >= 100 && r.bottom <= 800;
    });
  });
  await cardHandle.asElement().click();
  await page.waitForTimeout(1500);
  const backBtn = page
    .locator("button", { hasText: "Назад" })
    .first();
  await backBtn.click();
  await page.waitForTimeout(120); // grid mounted from cache, scroll restored
  const rightAfterBack = await page.evaluate(() => {
    const main = document.getElementById("main-scroll");
    return {
      scrollTop: main.scrollTop,
      firstCard: main.querySelector("article.media-card")?.getAttribute("aria-label"),
    };
  });
  await page.waitForTimeout(900); // background reload has landed by now
  const afterReload = await page.evaluate(() => {
    const main = document.getElementById("main-scroll");
    return {
      scrollTop: main.scrollTop,
      firstCard: main.querySelector("article.media-card")?.getAttribute("aria-label"),
      articles: main.querySelectorAll("article.media-card").length,
    };
  });
  console.log(
    "BACK-NAV:",
    JSON.stringify({ beforeOpen, rightAfterBack, afterReload }, null, 2),
  );
  if (Math.abs(rightAfterBack.scrollTop - beforeOpen.scrollTop) > 2)
    problems.push(
      `scroll not restored on back: ${beforeOpen.scrollTop} -> ${rightAfterBack.scrollTop}`,
    );
  if (Math.abs(afterReload.scrollTop - rightAfterBack.scrollTop) > 2)
    problems.push(
      `scroll jumped after reload: ${rightAfterBack.scrollTop} -> ${afterReload.scrollTop}`,
    );

  console.log("PROBLEMS:", problems.length ? problems : "none");
  await browser.close();
  if (problems.length) process.exit(1);
})().catch((e) => {
  console.error("FATAL", e);
  process.exit(1);
});
