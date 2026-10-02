// Verifies the "Характеристики" date rows on the media detail page:
// "Дата начала" must render the full date, and "Дата окончания" must show a dash
// (never the start year) when the title has no end date.
const { chromium } = require("playwright-core");

const BASE = "http://127.0.0.1:5099";
const ID = process.argv[2] || "e8165434-03dc-4fef-8171-63123cce7730";

(async () => {
  const browser = await chromium.launch({ channel: "msedge" });
  const page = await browser.newPage({ viewport: { width: 1440, height: 900 } });
  await page.addInitScript(() => localStorage.setItem("lang", "ru"));
  await page.goto(`${BASE}/?view=detail&mediaId=${ID}`, {
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
  if (end !== "—" && !/^\d{1,2}\s\S+\s\d{4}/.test(end)) {
    failures.push(`Дата окончания is neither a full date nor a dash: ${JSON.stringify(end)}`);
  }
  const eps = byLabel["Серии"] ?? "";
  if (/^0\s*\/\s*0/.test(eps)) {
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