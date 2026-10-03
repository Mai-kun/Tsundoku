// Verifies the "Характеристики" date rows on the media detail page:
// "Дата начала" must render the full date, and "Дата окончания" must show a dash
// (never the start year) when the title has no end date.
//
// The item is discovered from the API instead of being hardcoded. The "Дата начала" row renders
// releaseDate, so the fixture must be an item that has one — otherwise the row is a dash and the
// assertion would be vacuous. Run against any server with TS_BASE (default http://localhost:5000).
const { chromium } = require("playwright-core");

const BASE = process.env.TS_BASE || "http://localhost:5000";

(async () => {
  const browser = await chromium.launch({ channel: "msedge" });
  const page = await browser.newPage({ viewport: { width: 1440, height: 900 } });

  const library = await page.request.get(`${BASE}/api/media`).then((r) => r.json());
  if (!library.length) {
    await browser.close();
    console.error("FATAL library is empty - nothing to verify");
    process.exit(1);
  }

  // Prefer a title with no end date, which is the row that must fall back to a dash. Among those,
  // prefer one that also records episodes so the episode counter assertion has something to check.
  const withReleaseDate = library.filter((m) => m.releaseDate);
  const target =
    withReleaseDate.find((m) => !m.endDate && m.totalEpisodesCount > 0) ??
    withReleaseDate.find((m) => !m.endDate) ??
    withReleaseDate.find((m) => m.totalEpisodesCount > 0) ??
    withReleaseDate[0];

  if (!target) {
    await browser.close();
    console.log(
      "SKIP: no library item has a releaseDate, so the date rows have nothing to render; add one and re-run",
    );
    process.exit(0);
  }
  console.log(
    `verifying ${target.type} "${target.title}" (releaseDate=${target.releaseDate}, releaseYear=${target.releaseYear ?? "none"}, endDate=${target.endDate ?? "none"}, episodes=${target.totalEpisodesCount})`,
  );

  await page.addInitScript(() => localStorage.setItem("lang", "ru"));
  await page.goto(`${BASE}/?view=detail&mediaId=${target.id}`, {
    waitUntil: "domcontentloaded",
  });
  await page.waitForTimeout(4000);

  const rows = await page.evaluate(() => {
    const wanted = ["Дата начала", "Дата окончания", "Статус", "Серии", "Хронометраж"];
    return Array.from(document.querySelectorAll("dt"))
      .map((dt) => ({
        label: dt.textContent.trim(),
        value: dt.nextElementSibling?.textContent?.trim() ?? "",
      }))
      .filter((row) => wanted.includes(row.label));
  });

  const byLabel = Object.fromEntries(rows.map((r) => [r.label, r.value]));
  console.log(JSON.stringify(byLabel, null, 2));

  const failures = [];
  const start = byLabel["Дата начала"] ?? "";
  // A full date has a day component (1-31) followed by a month name. A bare "2015 год" fallback
  // has neither, so this cannot be satisfied by the year-only rendering the bug produced.
  if (!/^\d{1,2}\s\S+\s\d{4}/.test(start)) {
    failures.push(`Дата начала is not a full date: ${JSON.stringify(start)}`);
  }
  // A missing end date must be a dash, never the start year.
  const end = byLabel["Дата окончания"] ?? "";
  if (target.endDate ? !/^\d{1,2}\s\S+\s\d{4}/.test(end) : end !== "—") {
    failures.push(`Дата окончания is neither a full date nor a dash: ${JSON.stringify(end)}`);
  }
  // Only meaningful when the fixture actually has episodes; a title with no seasons legitimately
  // renders 0/0, so asserting against it would fail for the wrong reason.
  const eps = byLabel["Серии"] ?? "";
  if (target.totalEpisodesCount > 0 && /^0\s*\/\s*0/.test(eps)) {
    failures.push(`Серии is still 0/0: ${JSON.stringify(eps)}`);
  }

  await browser.close();
  if (failures.length) {
    for (const f of failures) console.error("FAIL " + f);
    process.exit(1);
  }
  console.log("OK: date rows render in full and the end date falls back to a dash");
})().catch((e) => {
  console.error("FATAL", e);
  process.exit(1);
});
