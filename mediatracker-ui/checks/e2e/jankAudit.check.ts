// Detects Long Tasks (>50ms) and UI jank during user interactions.
// Requires the Tsundoku server running on :5000 (or TARGET_URL).
// Run: npm --prefix mediatracker-ui run check:jank
import { chromium } from "playwright-core";

const BASE =
  process.env.TARGET_URL ||
  process.env.TS_BASE ||
  "http://127.0.0.1:5000";
const LONG_TASK_MS = 50;
const MAX_SINGLE_TASK_MS = 100;
const INITIAL_LOAD_MAX_MS = 200;
const MAX_INTERACTION_LONG_TASKS = 1;

const failures: Array<{ name: string; details?: unknown }> = [];

function check(name: string, condition: boolean, details?: unknown) {
  if (!condition) failures.push({ name, details });
  console.log(`${condition ? "ok   " : "FAIL "} ${name}`);
  return condition;
}

(async () => {
  const browser = await chromium.launch({
    channel: process.env.TS_BROWSER_CHANNEL || (process.platform === "win32" ? "msedge" : undefined),
    headless: true,
  });
  const page = await browser.newPage({ viewport: { width: 1440, height: 900 } });
  page.setDefaultTimeout(10000);

  const initialLoadLongTasks: Array<{ name: string; duration: number; startTime: number }> = [];
  const interactionLongTasks: Array<{ name: string; duration: number; startTime: number }> = [];

  async function snapshot(target: Array<{ name: string; duration: number; startTime: number }>) {
    const tasks = await page.evaluate(() => (window as any).__longTasks || []);
    target.push(...tasks);
  }

  async function clearBuffer() {
    await page.evaluate(() => {
      (window as any).__longTasks.length = 0;
    });
  }

  // Inject the PerformanceObserver before the first navigation so long tasks are
  // captured from the moment the page loads, across the whole session.
  await page.addInitScript(() => {
    (window as any).__longTasks = [];
    const observer = new PerformanceObserver((list) => {
      for (const entry of list.getEntries()) {
        (window as any).__longTasks.push({
          name: entry.name,
          duration: Math.round(entry.duration),
          startTime: Math.round(entry.startTime),
        });
      }
    });
    observer.observe({ entryTypes: ["longtask"] });
  });

  try {
    // --- PHASE 1: Initial cold-boot page load ---
    // Wait until at least one media card is mounted in the DOM so we capture the full
    // evaluation + paint (cards may be position-hidden by the virtualizer, so check
    // presence rather than visibility).
    await page.goto(`${BASE}/?view=home`, { waitUntil: "domcontentloaded" });
    await page.locator(".media-card, article").first().waitFor({ state: "attached", timeout: 15000 });
    await page.waitForTimeout(1000);
    await snapshot(initialLoadLongTasks);

    // Separate initial load from interactions: clear the buffer now that cold boot is measured.
    await clearBuffer();

    // --- PHASE 2: Fast category switching: Home -> Game -> Manga -> Movie -> TV ---
    for (const view of ["home", "game", "manga", "movie", "tvshow"]) {
      await page.goto(`${BASE}/?view=${view}`, { waitUntil: "domcontentloaded" });
      await page.locator(".media-card, article").first().waitFor({ state: "attached", timeout: 15000 });
      await page.waitForTimeout(800);
      await snapshot(interactionLongTasks);
    }

    // --- PHASE 3: Open and close SearchModal via Ctrl+K ---
    await page.keyboard.press("Control+k");
    const searchDialog = page.locator("dialog[open]").first();
    await searchDialog.waitFor({ state: "visible", timeout: 10000 });
    await page.keyboard.press("Escape");
    await searchDialog.waitFor({ state: "hidden" });
    await snapshot(interactionLongTasks);

    // --- PHASE 4: Open and close SettingsModal ---
    await page.locator("button", { hasText: /Настройки|Settings/ }).first().click();
    const settingsDialog = page.locator("dialog[open]").first();
    await settingsDialog.waitFor({ state: "visible", timeout: 10000 });
    await page.keyboard.press("Escape");
    await settingsDialog.waitFor({ state: "hidden" });
    await snapshot(interactionLongTasks);

    // --- PHASE 5: Rapid virtual grid scroll (down 3000px and back up) ---
    await page.goto(`${BASE}/?view=game`, { waitUntil: "domcontentloaded" });
    await page.locator(".media-card, article").first().waitFor({ state: "attached", timeout: 15000 });
    await page.waitForTimeout(800);
    await page.evaluate(() => {
      const main = document.getElementById("main-scroll");
      if (main) main.scrollTop = 3000;
    });
    await page.waitForTimeout(800);
    await page.evaluate(() => {
      const main = document.getElementById("main-scroll");
      if (main) main.scrollTop = 0;
    });
    await page.waitForTimeout(800);
    await snapshot(interactionLongTasks);

    // --- Report ---
    console.log("\n--- Long Tasks Summary ---");
    console.log(`Initial load long tasks: ${initialLoadLongTasks.length}`);
    if (initialLoadLongTasks.length > 0) {
      console.log("  Duration(ms)  StartTime(ms)");
      for (const t of initialLoadLongTasks) {
        console.log(`  ${String(t.duration).padStart(10)}  ${String(t.startTime).padStart(11)}`);
      }
    }
    console.log(`Interaction long tasks: ${interactionLongTasks.length}`);
    if (interactionLongTasks.length > 0) {
      console.log("  Duration(ms)  StartTime(ms)");
      for (const t of interactionLongTasks) {
        console.log(`  ${String(t.duration).padStart(10)}  ${String(t.startTime).padStart(11)}`);
      }
    }

    const overInitial = initialLoadLongTasks.filter((t) => t.duration > INITIAL_LOAD_MAX_MS);
    const over100 = interactionLongTasks.filter((t) => t.duration > MAX_SINGLE_TASK_MS);
    const over50Interaction = interactionLongTasks.filter((t) => t.duration > LONG_TASK_MS);

    check(
      `Initial cold-boot task <= ${INITIAL_LOAD_MAX_MS}ms`,
      overInitial.length === 0,
      overInitial,
    );
    check("No interaction task exceeds 100ms", over100.length === 0, over100);
    check(
      `Interaction long tasks (>${LONG_TASK_MS}ms) <= ${MAX_INTERACTION_LONG_TASKS}`,
      over50Interaction.length <= MAX_INTERACTION_LONG_TASKS,
      over50Interaction,
    );
  } catch (error) {
    failures.push({ name: "unexpected exception", details: error.stack || error.message });
    console.error("EXCEPTION:", error.message);
  } finally {
    await browser.close();
  }

  if (failures.length) {
    console.error("FAILED:", JSON.stringify(failures, null, 2));
    process.exit(1);
  }
  console.log("OK: jank audit passed — no long tasks above thresholds");
})().catch((error) => {
  console.error("FATAL:", error);
  process.exit(1);
});
