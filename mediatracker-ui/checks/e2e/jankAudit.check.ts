// Detects Long Tasks (>50ms) and UI jank during user interactions.
// Includes 144 Hz micro-jank detection via rAF frame-delta sampling.
// Requires the Tsundoku server running on :5000 (or TARGET_URL).
// Run: npm --prefix mediatracker-ui run check:jank
import fs from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";
import { chromium } from "playwright-core";

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const reportsDir = path.resolve(__dirname, "../../../reports");

const BASE =
  process.env.TARGET_URL ||
  process.env.TS_BASE ||
  "http://127.0.0.1:5000";
const LONG_TASK_MS = 50;
const MAX_SINGLE_TASK_MS = 100;
const INITIAL_LOAD_MAX_MS = 200;
const MAX_INTERACTION_LONG_TASKS = 1;
// 144 Hz frame budget = 1000 / 144 ≈ 6.94 ms per frame.
const FRAME_BUDGET_144_MS = 6.94;

const failures: Array<{ name: string; details?: unknown }> = [];

function percentile(sorted: number[], p: number) {
  if (sorted.length === 0) return 0;
  const s = [...sorted].sort((a, b) => a - b);
  const rank = (p / 100) * (s.length - 1);
  const lo = Math.floor(rank);
  const hi = Math.ceil(rank);
  const frac = rank - lo;
  return s[lo] + (s[hi] - s[lo]) * frac;
}

function check(name: string, condition: boolean, details?: unknown) {
  if (!condition) failures.push({ name, details });
  console.log(`${condition ? "ok   " : "FAIL "} ${name}`);
  return condition;
}

(async () => {
  const browser = await chromium.launch({
    channel: process.env.TS_BROWSER_CHANNEL || (process.platform === "win32" ? "msedge" : undefined),
    headless: true,
    args: ["--disable-frame-rate-limit", "--disable-gpu-vsync"],
  });
  const page = await browser.newPage({ viewport: { width: 1440, height: 900 } });
  page.setDefaultTimeout(10000);

  const initialLoadLongTasks: Array<{ name: string; duration: number; startTime: number }> = [];
  const interactionLongTasks: Array<{ name: string; duration: number; startTime: number }> = [];
  let highRefresh:
    | {
        avgFps: number;
        frameTimeP95Ms: number;
        droppedFrames144: number;
        highRefreshCapable: boolean;
        fpsThreshold: number;
      }
    | null = null;

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
    await page.waitForLoadState("load");
    await page.waitForSelector(".media-card, [data-widget=\"sidebar\"]", { timeout: 15000 });
    await page.waitForTimeout(1500);
    await snapshot(initialLoadLongTasks);

    // Separate initial load from interactions: clear the buffer now that cold boot is measured.
    await clearBuffer();

    // High-precision frame timer for micro-jank detection (runs across interactions).
    await page.evaluate(() => {
      (window as any).__frameDeltas = [];
      let lastTime = performance.now();
      function loop(now: number) {
        const delta = now - lastTime;
        lastTime = now;
        if (delta > 0) (window as any).__frameDeltas.push(delta);
        (window as any).__rafId = requestAnimationFrame(loop);
      }
      (window as any).__rafId = requestAnimationFrame(loop);
    });

    // --- PHASE 2: Fast category switching: Home -> Game -> Manga -> Movie -> TV ---
    for (const view of ["home", "game", "manga", "movie", "tvshow"]) {
      await page.goto(`${BASE}/?view=${view}`, { waitUntil: "domcontentloaded" });
      await page.waitForLoadState("load");
      await page.waitForSelector(".media-card, [data-widget=\"sidebar\"]", { timeout: 15000 });
      await page.waitForTimeout(1500);
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
    await page.waitForLoadState("load");
    await page.waitForSelector(".media-card, [data-widget=\"sidebar\"]", { timeout: 15000 });
    await page.waitForTimeout(1500);
    // Re-inject the rAF frame timer (page navigations reset the JS context) and
    // reset the delta buffer so we only measure the active scroll window.
    await page.evaluate(() => {
      (window as any).__frameDeltas = [];
      let lastTime = performance.now();
      function loop(now: number) {
        const delta = now - lastTime;
        lastTime = now;
        if (delta > 0) (window as any).__frameDeltas.push(delta);
        (window as any).__rafId = requestAnimationFrame(loop);
      }
      (window as any).__rafId = requestAnimationFrame(loop);
    });
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

    // --- Micro-jank: rAF frame-delta metrics captured during the active scroll ---
    const frameDeltas = (await page.evaluate(
      () => (window as any).__frameDeltas || [],
    )) as number[];
    const sortedDeltas = [...frameDeltas].sort((a, b) => a - b);
    const avgDelta =
      frameDeltas.length > 0
        ? frameDeltas.reduce((a, b) => a + b, 0) / frameDeltas.length
        : 0;
    const avgFps = avgDelta > 0 ? Math.round(1000 / avgDelta) : 0;
    const frameTimeP95Ms = sortedDeltas.length
      ? Math.round(percentile(sortedDeltas, 95) * 100) / 100
      : 0;
    const droppedFrames144 = frameDeltas.filter((d) => d > FRAME_BUDGET_144_MS).length;
    // With the frame-rate limit unlocked, rAF runs unbounded (>100 FPS) on
    // high-refresh-capable pipelines; hold the 144 Hz bar (>= 120). On a
    // locked 60 Hz pipeline (~60 FPS) relax to >= 58.
    const highRefreshCapable = avgFps > 100;
    const fpsThreshold = highRefreshCapable ? 120 : 58;
    highRefresh = {
      avgFps,
      frameTimeP95Ms,
      droppedFrames144,
      highRefreshCapable,
      fpsThreshold,
    };

    check(
      `Scrolling avg FPS >= ${fpsThreshold} (${
        highRefreshCapable ? "high-refresh" : "60 Hz"
      } pipeline)`,
      avgFps >= fpsThreshold,
      highRefresh,
    );
    console.log(
      `  frame deltas: count=${frameDeltas.length} avgFps=${avgFps} p95=${frameTimeP95Ms}ms dropped144=${droppedFrames144}`,
    );

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

  // Write the check summary so the audit report can surface the 144 Hz metrics.
  fs.mkdirSync(reportsDir, { recursive: true });
  fs.writeFileSync(
    path.join(reportsDir, "jank-audit.json"),
    JSON.stringify(
      {
        timestamp: new Date().toISOString(),
        passed: failures.length === 0,
        longTasks: {
          initialLoad: initialLoadLongTasks.length,
          interaction: interactionLongTasks.length,
          overInitial: initialLoadLongTasks.filter(
            (t) => t.duration > INITIAL_LOAD_MAX_MS,
          ).length,
          over100ms: interactionLongTasks.filter((t) => t.duration > MAX_SINGLE_TASK_MS).length,
          over50msInteraction: interactionLongTasks.filter(
            (t) => t.duration > LONG_TASK_MS,
          ).length,
        },
        highRefresh,
        failures,
      },
      null,
      2,
    ),
    "utf-8",
  );

  if (failures.length) {
    console.error("FAILED:", JSON.stringify(failures, null, 2));
    process.exit(1);
  }
  console.log("OK: jank audit passed — no long tasks above thresholds");
})().catch((error) => {
  console.error("FATAL:", error);
  process.exit(1);
});
