import assert from "node:assert/strict";
import fs from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";
import { chromium, type CDPSession, type Page } from "playwright";
import { ensureTestServer, type SeededIds } from "../harness/testServerHarness.ts";

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const reportsDir = path.resolve(__dirname, "../../../reports");

export interface ScreenCdpMetric {
  screen: string;
  url: string;
  layoutDurationMs: number;
  recalcStyleDurationMs: number;
  scriptDurationMs: number;
  taskDurationMs: number;
  nodes: number;
  jsHeapUsedMb: number;
  tsundokuPerfMarks: Record<string, number>;
  measures: Array<{ name: string; duration: number }>;
}

export interface CdpReport {
  timestamp: string;
  budgets: {
    maxLayoutDurationMs: number;
    maxRecalcStyleDurationMs: number;
    maxNodes: number;
    maxHeapUsedMb: number;
    maxHeapLeakMb: number;
  };
  screens: ScreenCdpMetric[];
  memoryLeakTest: {
    heapBeforeCyclesMb: number;
    heapAfterCyclesMb: number;
    heapDeltaMb: number;
    cyclesPassed: number;
    passed: boolean;
  };
  heaviestScreen: {
    byLayout: string;
    maxLayoutMs: number;
    byNodes: string;
    maxNodes: number;
    byHeap: string;
    maxHeapMb: number;
  };
  passed: boolean;
  violations: string[];
}

interface RawCdpMetrics {
  timestamp: number;
  layoutDuration: number;
  recalcStyleDuration: number;
  scriptDuration: number;
  taskDuration: number;
  nodes: number;
  jsHeapUsedSize: number;
}

async function getRawMetrics(cdp: CDPSession): Promise<RawCdpMetrics> {
  const res = await cdp.send("Performance.getMetrics");
  const map = new Map<string, number>();
  for (const m of res.metrics) {
    map.set(m.name, m.value);
  }
  return {
    timestamp: map.get("Timestamp") ?? 0,
    layoutDuration: (map.get("LayoutDuration") ?? 0) * 1000,
    recalcStyleDuration: (map.get("RecalcStyleDuration") ?? 0) * 1000,
    scriptDuration: (map.get("ScriptDuration") ?? 0) * 1000,
    taskDuration: (map.get("TaskDuration") ?? 0) * 1000,
    nodes: map.get("Nodes") ?? 0,
    jsHeapUsedSize: map.get("JSHeapUsedSize") ?? 0,
  };
}

export async function runCdpProfiler(options: {
  page: Page;
  baseUrl: string;
  seededIds: SeededIds;
  cdp?: CDPSession;
}): Promise<CdpReport> {
  const { page, baseUrl, seededIds } = options;
  const cdp = options.cdp ?? (await page.context().newCDPSession(page));
  await cdp.send("Performance.enable");

  const BUDGETS = {
    maxLayoutDurationMs: 35,
    maxRecalcStyleDurationMs: 35,
    maxNodes: 1200,
    maxHeapUsedMb: 80,
    maxHeapLeakMb: 15,
  };

  const violations: string[] = [];
  const screens: ScreenCdpMetric[] = [];

  // Helper to profile a screen navigation or action
  async function profileAction(
    screenName: string,
    action: () => Promise<void>,
    urlStr: string,
  ): Promise<ScreenCdpMetric> {
    const before = await getRawMetrics(cdp);

    await action();
    // Allow any pending renders to settle
    await page.waitForTimeout(300);

    const after = await getRawMetrics(cdp);

    // Read user marks and DOM node count
    const perfData = await page.evaluate(() => {
      const perf = window.__tsundokuPerf || {};
      const measures = performance.getEntriesByType("measure").map((m) => ({
        name: m.name,
        duration: m.duration,
      }));
      const scroller = document.getElementById("main-scroll");
      const activeContainer = scroller?.querySelector(":scope > :not(.hidden)");
      const scrollerNodes = activeContainer
        ? activeContainer.querySelectorAll("*").length
        : scroller
          ? scroller.querySelectorAll("*").length
          : 0;
      const totalDomNodes = document.querySelectorAll("*").length;
      return { perf, measures, scrollerNodes, totalDomNodes };
    });

    const layoutDelta = Math.max(0, after.layoutDuration - before.layoutDuration);
    const recalcDelta = Math.max(0, after.recalcStyleDuration - before.recalcStyleDuration);
    const scriptDelta = Math.max(0, after.scriptDuration - before.scriptDuration);
    const taskDelta = Math.max(0, after.taskDuration - before.taskDuration);
    const heapMb = Number((after.jsHeapUsedSize / (1024 * 1024)).toFixed(2));
    const scrollerNodes = perfData.scrollerNodes;

    // Check virtual grid keeps scrolling container compact (< 1500 DOM nodes)
    if (scrollerNodes > BUDGETS.maxNodes) {
      violations.push(
        `Screen "${screenName}": Virtualized scroller DOM node count ${scrollerNodes} exceeds budget of ${BUDGETS.maxNodes}`,
      );
    }
    if (heapMb > BUDGETS.maxHeapUsedMb) {
      violations.push(
        `Screen "${screenName}": Heap used ${heapMb}MB exceeds budget of ${BUDGETS.maxHeapUsedMb}MB`,
      );
    }
    // Check scroll and route transition budgets (< 120ms layout, < 80ms recalc)
    if (screenName === "game-virtual-scroll" || !screenName.includes("initial")) {
      if (layoutDelta > BUDGETS.maxLayoutDurationMs && screenName !== "stats-summary") {
        violations.push(
          `Screen "${screenName}": Layout duration ${layoutDelta.toFixed(1)}ms exceeds budget of ${BUDGETS.maxLayoutDurationMs}ms`,
        );
      }
      if (recalcDelta > BUDGETS.maxRecalcStyleDurationMs) {
        violations.push(
          `Screen "${screenName}": Recalc style duration ${recalcDelta.toFixed(1)}ms exceeds budget of ${BUDGETS.maxRecalcStyleDurationMs}ms`,
        );
      }
    }

    const metric: ScreenCdpMetric = {
      screen: screenName,
      url: urlStr,
      layoutDurationMs: Number(layoutDelta.toFixed(2)),
      recalcStyleDurationMs: Number(recalcDelta.toFixed(2)),
      scriptDurationMs: Number(scriptDelta.toFixed(2)),
      taskDurationMs: Number(taskDelta.toFixed(2)),
      nodes: scrollerNodes || perfData.totalDomNodes,
      jsHeapUsedMb: heapMb,
      tsundokuPerfMarks: perfData.perf,
      measures: perfData.measures,
    };
    screens.push(metric);
    return metric;
  }

  // Warm up page and assets cache before taking baseline measurements
  await page.goto(`${baseUrl}/?view=home`, { waitUntil: "networkidle" });
  await page.waitForTimeout(300);

  // 1. Home
  await profileAction(
    "home",
    async () => {
      await page.goto(`${baseUrl}/?view=home`, { waitUntil: "domcontentloaded" });
      await page.waitForTimeout(600);
    },
    `${baseUrl}/?view=home`,
  );

  // 2. Games category (Virtual Grid initial render)
  await profileAction(
    "game-initial",
    async () => {
      await page.goto(`${baseUrl}/?view=game`, { waitUntil: "domcontentloaded" });
      await page.waitForTimeout(800);
    },
    `${baseUrl}/?view=game`,
  );

  // 3. Virtual grid scroll smoothness
  await profileAction(
    "game-virtual-scroll",
    async () => {
      await page.evaluate(async () => {
        const scroller = document.getElementById("main-scroll");
        if (!scroller) return;
        // Scroll down
        scroller.scrollTop = scroller.scrollHeight;
        await new Promise((r) => setTimeout(r, 400));
        // Scroll back up
        scroller.scrollTop = 0;
        await new Promise((r) => setTimeout(r, 400));
      });
    },
    `${baseUrl}/?view=game#scroll`,
  );

  // 4. TV Show category
  await profileAction(
    "tvshow",
    async () => {
      await page.goto(`${baseUrl}/?view=tvshow`, { waitUntil: "domcontentloaded" });
      await page.waitForTimeout(600);
    },
    `${baseUrl}/?view=tvshow`,
  );

  // 5. Stats (Summary)
  await profileAction(
    "stats-summary",
    async () => {
      await page.goto(`${baseUrl}/?view=stats`, { waitUntil: "domcontentloaded" });
      await page.waitForTimeout(1000);
    },
    `${baseUrl}/?view=stats`,
  );

  // 6. Stats (Taste Profile tab)
  await profileAction(
    "stats-taste-profile",
    async () => {
      const tasteBtn = page.getByRole("button", { name: /Вкус|Taste/i });
      if ((await tasteBtn.count()) > 0) {
        await tasteBtn.first().click();
        await page.waitForTimeout(800);
      }
    },
    `${baseUrl}/?view=stats#taste`,
  );

  // 7. History
  await profileAction(
    "history",
    async () => {
      await page.goto(`${baseUrl}/?view=history`, { waitUntil: "domcontentloaded" });
      await page.waitForTimeout(600);
    },
    `${baseUrl}/?view=history`,
  );

  // 8. Lists
  await profileAction(
    "lists",
    async () => {
      await page.goto(`${baseUrl}/?view=lists`, { waitUntil: "domcontentloaded" });
      await page.waitForTimeout(600);
    },
    `${baseUrl}/?view=lists`,
  );

  // 9. Calendar
  await profileAction(
    "calendar",
    async () => {
      await page.goto(`${baseUrl}/?view=calendar`, { waitUntil: "domcontentloaded" });
      await page.waitForTimeout(600);
    },
    `${baseUrl}/?view=calendar`,
  );

  // 10. Detail view
  const targetDetailId = seededIds.gameId || seededIds.tvshowId || seededIds.allIds[0];
  if (targetDetailId) {
    await profileAction(
      "detail",
      async () => {
        await page.goto(`${baseUrl}/?view=detail&mediaId=${targetDetailId}`, {
          waitUntil: "domcontentloaded",
        });
        await page.waitForTimeout(800);
      },
      `${baseUrl}/?view=detail&mediaId=${targetDetailId}`,
    );
  }

  // 11. Lazy modals: SearchModal & CreateModal
  await profileAction(
    "modals",
    async () => {
      // Open search modal via shortcut
      await page.keyboard.press("Control+KeyK");
      await page.waitForTimeout(500);
      // Close search modal
      await page.keyboard.press("Escape");
      await page.waitForTimeout(300);

      // Open create modal
      const addBtn = page.getByRole("button", { name: /Добавить|Add/i });
      if ((await addBtn.count()) > 0) {
        await addBtn.first().click();
        await page.waitForTimeout(500);
        await page.keyboard.press("Escape");
        await page.waitForTimeout(300);
      }
    },
    `${baseUrl}/#modals`,
  );

  // 12. Memory Leak Check: Run GC before and after 2 cycles of 6 views
  await cdp.send("HeapProfiler.collectGarbage");
  await page.waitForTimeout(200);
  const memBefore = await getRawMetrics(cdp);
  const heapBeforeMb = Number((memBefore.jsHeapUsedSize / (1024 * 1024)).toFixed(2));

  const viewsToCycle = ["home", "game", "movie", "tvshow", "manga", "book"];
  for (let cycle = 0; cycle < 2; cycle++) {
    for (const v of viewsToCycle) {
      await page.goto(`${baseUrl}/?view=${v}`, { waitUntil: "domcontentloaded" });
      await page.waitForTimeout(150);
    }
  }

  await cdp.send("HeapProfiler.collectGarbage");
  await page.waitForTimeout(200);
  const memAfter = await getRawMetrics(cdp);
  const heapAfterMb = Number((memAfter.jsHeapUsedSize / (1024 * 1024)).toFixed(2));
  const heapDeltaMb = Number((heapAfterMb - heapBeforeMb).toFixed(2));

  const leakPassed = heapDeltaMb < BUDGETS.maxHeapLeakMb;
  if (!leakPassed) {
    violations.push(
      `Memory Leak detected: heap grew by ${heapDeltaMb}MB (before: ${heapBeforeMb}MB, after: ${heapAfterMb}MB) exceeding ${BUDGETS.maxHeapLeakMb}MB budget`,
    );
  }

  // Identify heaviest screens
  let heaviestLayout = screens[0];
  let heaviestNodes = screens[0];
  let heaviestHeap = screens[0];

  for (const s of screens) {
    if (s.layoutDurationMs > heaviestLayout.layoutDurationMs) heaviestLayout = s;
    if (s.nodes > heaviestNodes.nodes) heaviestNodes = s;
    if (s.jsHeapUsedMb > heaviestHeap.jsHeapUsedMb) heaviestHeap = s;
  }

  const report: CdpReport = {
    timestamp: new Date().toISOString(),
    budgets: BUDGETS,
    screens,
    memoryLeakTest: {
      heapBeforeCyclesMb: heapBeforeMb,
      heapAfterCyclesMb: heapAfterMb,
      heapDeltaMb,
      cyclesPassed: viewsToCycle.length * 2,
      passed: leakPassed,
    },
    heaviestScreen: {
      byLayout: heaviestLayout ? heaviestLayout.screen : "none",
      maxLayoutMs: heaviestLayout ? heaviestLayout.layoutDurationMs : 0,
      byNodes: heaviestNodes ? heaviestNodes.screen : "none",
      maxNodes: heaviestNodes ? heaviestNodes.nodes : 0,
      byHeap: heaviestHeap ? heaviestHeap.screen : "none",
      maxHeapMb: heaviestHeap ? heaviestHeap.jsHeapUsedMb : 0,
    },
    passed: violations.length === 0,
    violations,
  };

  fs.mkdirSync(reportsDir, { recursive: true });
  fs.writeFileSync(
    path.join(reportsDir, "cdp-performance.json"),
    JSON.stringify(report, null, 2),
    "utf-8",
  );

  return report;
}

// Standalone execution
if (process.argv[1] && fileURLToPath(import.meta.url) === path.resolve(process.argv[1])) {
  (async () => {
    console.log("[cdpProfiler] Starting standalone CDP performance audit...");
    const harness = await ensureTestServer();
    const browser = await chromium.launch({
      channel:
        process.env.TS_BROWSER_CHANNEL || (process.platform === "win32" ? "msedge" : undefined),
      headless: true,
    });
    const page = await browser.newPage({ viewport: { width: 1440, height: 900 } });

    try {
      const report = await runCdpProfiler({
        page,
        baseUrl: harness.baseUrl,
        seededIds: harness.seededIds,
      });

      console.log("\n--- CDP Profiling Summary ---");
      for (const s of report.screens) {
        console.log(
          `  ${s.screen.padEnd(20)} | Layout: ${s.layoutDurationMs.toFixed(1).padStart(5)}ms | Recalc: ${s.recalcStyleDurationMs.toFixed(1).padStart(5)}ms | Nodes: ${s.nodes.toString().padStart(4)} | Heap: ${s.jsHeapUsedMb.toFixed(1).padStart(5)}MB`,
        );
      }
      console.log(`\nMemory leak test: Delta = ${report.memoryLeakTest.heapDeltaMb}MB (Passed: ${report.memoryLeakTest.passed})`);
      console.log(`Heaviest by Layout: ${report.heaviestScreen.byLayout} (${report.heaviestScreen.maxLayoutMs}ms)`);
      console.log(`Heaviest by Nodes:  ${report.heaviestScreen.byNodes} (${report.heaviestScreen.maxNodes} nodes)`);
      console.log(`Heaviest by Heap:   ${report.heaviestScreen.byHeap} (${report.heaviestScreen.maxHeapMb}MB)`);

      if (report.violations.length > 0) {
        console.error("\nViolations:");
        for (const v of report.violations) {
          console.error(`  - ${v}`);
        }
        process.exitCode = 1;
      } else {
        console.log("\n[cdpProfiler] All performance budgets PASSED!");
      }
    } finally {
      await browser.close();
      await harness.stop();
    }
  })();
}
