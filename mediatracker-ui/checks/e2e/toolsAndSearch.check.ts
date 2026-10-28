import { chromium } from "playwright-core";

const BASE = process.env.TS_BASE || "http://localhost:5000";
const failures: Array<{ name: string; details?: unknown }> = [];
const pageErrors: string[] = [];

function check(name: string, condition: boolean, details?: unknown) {
  if (!condition) failures.push({ name, details });
  console.log(`${condition ? "ok   " : "FAIL "} ${name}`);
  return condition;
}

(async () => {
  const launchOptions = {
    channel: process.env.TS_BROWSER_CHANNEL || (process.platform === "win32" ? "msedge" : undefined),
    headless: true,
  };
  const browser = await chromium.launch(launchOptions);
  const page = await browser.newPage({ viewport: { width: 1440, height: 900 } });
  page.setDefaultTimeout(10000);
  page.on("pageerror", (error) => pageErrors.push(error.message));

  try {
    // 1. Open home view
    console.log(`Navigating to ${BASE}/?view=home`);
    await page.goto(`${BASE}/?view=home`, { waitUntil: "domcontentloaded" });
    await page.waitForSelector("aside", { state: "visible", timeout: 10000 });
    check("home page loaded", page.url().includes("view=home"));

    // 2. Click search button in header -> checks dialog appeared and search input focused. Closes on Escape.
    const headerSearch = page.locator('header button:has-text("Ctrl K"), header button:has(svg)').first();
    await headerSearch.waitFor({ state: "visible", timeout: 10000 });
    await headerSearch.click();

    const searchDialog = page.locator("dialog[open]").first();
    await searchDialog.waitFor({ state: "visible", timeout: 10000 });
    const isSearchDialogOpen = await searchDialog.evaluate((d) => d instanceof HTMLDialogElement && d.open);
    check('search modal opens on header click', isSearchDialogOpen);

    const searchInput = searchDialog.locator('input[type="search"]').first();
    await searchInput.waitFor({ state: "visible", timeout: 5000 });
    const isInputFocused = await searchInput.evaluate((el) => document.activeElement === el);
    check("search input receives focus", isInputFocused);

    await page.keyboard.press("Escape");
    await searchDialog.waitFor({ state: "hidden", timeout: 5000 });
    const isSearchClosed = (await page.locator("dialog[open]").count()) === 0;
    check("search modal closes on Escape", isSearchClosed);

    // 3. Click «Статистика» -> checks transition to view stats
    const statsBtn = page.locator("aside button", { hasText: /Статистика|Stats/i }).first();
    await statsBtn.waitFor({ state: "visible", timeout: 5000 });
    await statsBtn.click();
    await page.waitForFunction(
      () => new URL(window.location.href).searchParams.get("view") === "stats",
      null,
      { timeout: 10000 }
    );
    check("navigates to stats", new URL(page.url()).searchParams.get("view") === "stats");

    // 4. Click «Списки» -> checks transition to view lists
    const listsBtn = page.locator("aside button", { hasText: /Списки|Lists/i }).first();
    await listsBtn.waitFor({ state: "visible", timeout: 5000 });
    await listsBtn.click();
    await page.waitForFunction(
      () => new URL(window.location.href).searchParams.get("view") === "lists",
      null,
      { timeout: 10000 }
    );
    check("navigates to lists", new URL(page.url()).searchParams.get("view") === "lists");

    // 5. Click «История» -> checks transition to view history
    const historyBtn = page.locator("aside button", { hasText: /История|History/i }).first();
    await historyBtn.waitFor({ state: "visible", timeout: 5000 });
    await historyBtn.click();
    await page.waitForFunction(
      () => new URL(window.location.href).searchParams.get("view") === "history",
      null,
      { timeout: 10000 }
    );
    check("navigates to history", new URL(page.url()).searchParams.get("view") === "history");

    // 6. Click «Календарь» -> checks transition to view calendar
    const calendarBtn = page.locator("aside button", { hasText: /Календарь|Calendar/i }).first();
    await calendarBtn.waitFor({ state: "visible", timeout: 5000 });
    await calendarBtn.click();
    await page.waitForFunction(
      () => new URL(window.location.href).searchParams.get("view") === "calendar",
      null,
      { timeout: 10000 }
    );
    check("navigates to calendar", new URL(page.url()).searchParams.get("view") === "calendar");

    // 7. Click «Настройки» -> checks settings modal opened
    const settingsBtn = page.locator("aside button", { hasText: /Настройки|Settings/i }).first();
    await settingsBtn.waitFor({ state: "visible", timeout: 5000 });
    await settingsBtn.click();

    const settingsDialog = page.locator("dialog[open]").first();
    await settingsDialog.waitFor({ state: "visible", timeout: 10000 });
    const isSettingsDialogOpen = await settingsDialog.evaluate((d) => d instanceof HTMLDialogElement && d.open);
    check("settings modal opens", isSettingsDialogOpen);

    await page.keyboard.press("Escape");
    await settingsDialog.waitFor({ state: "hidden", timeout: 5000 });
    const isSettingsClosed = (await page.locator("dialog[open]").count()) === 0;
    check("settings modal closes on Escape", isSettingsClosed);
  } catch (error: any) {
    failures.push({ name: "unexpected exception", details: error.stack || error.message });
    console.error("EXCEPTION:", error.message);
  } finally {
    if (pageErrors.length) failures.push({ name: "page errors", details: pageErrors });
    if (pageErrors.length) console.error("PAGE ERRORS:", pageErrors);
    await browser.close();
  }

  if (failures.length) {
    console.error("FAILED:", JSON.stringify(failures, null, 2));
    process.exit(1);
  }
  console.log("OK: all tools navigation and search modal checks passed successfully");
})().catch((error) => {
  console.error("FATAL:", error);
  process.exit(1);
});
