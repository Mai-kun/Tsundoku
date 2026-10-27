import fs from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";
import { chromium, type Browser, type BrowserContext, type Page } from "playwright";
import { ensureTestServer, type ServerHarness } from "../harness/testServerHarness.ts";
import { runCdpProfiler, type CdpReport } from "./cdpProfiler.check.ts";
import { runLayoutGeometry, type LayoutGeometryReport } from "./layoutGeometry.check.ts";
import { runAxeAccessibility, type AxeReport } from "./axeAccessibility.check.ts";
import { runVisualSnapshots, type VisualReport } from "./visualSnapshots.check.ts";
import { runWebVitals, type WebVitalsReport } from "./webVitals.check.ts";

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const reportsDir = path.resolve(__dirname, "../../../reports");

export interface LazyChunksPhaseResult {
  passed: boolean;
  viewsChecked: string[];
  modalsChecked: string[];
  consoleErrors: string[];
  durationMs: number;
}

export interface BrowserSuiteSummary {
  timestamp: string;
  totalDurationMs: number;
  serverUrl: string;
  phases: {
    lazyChunks: LazyChunksPhaseResult;
    cdpProfiler: {
      passed: boolean;
      durationMs: number;
      violations: string[];
      heaviestScreen: CdpReport["heaviestScreen"];
      memoryLeakDeltaMb: number;
    };
    layoutGeometry: {
      passed: boolean;
      durationMs: number;
      totalScreensChecked: number;
      totalAnomalies: number;
    };
    axeAccessibility: {
      passed: boolean;
      durationMs: number;
      totalScreensScanned: number;
      criticalAndSeriousCount: number;
    };
    visualSnapshots: {
      passed: boolean;
      durationMs: number;
      totalSnapshots: number;
      matched: number;
      mismatched: number;
      created: number;
      updated: number;
    };
    webVitals: {
      passed: boolean;
      durationMs: number;
      totalScreensChecked: number;
      violations: string[];
    };
  };
  passed: boolean;
}

async function verifyLazyChunks(page: Page, baseUrl: string): Promise<LazyChunksPhaseResult> {
  const startTime = Date.now();
  const consoleErrors: string[] = [];

  const errorHandler = (err: Error) => {
    consoleErrors.push(`[PageError] ${err.message}`);
  };
  const consoleHandler = (msg: { type: () => string; text: () => string }) => {
    if (msg.type() === "error") {
      const text = msg.text();
      // Ignore network noise or external favicon 404s
      if (
        !text.includes("favicon") &&
        !text.includes("net::ERR_") &&
        !text.includes("failed to load resource: the server responded with a status of 404")
      ) {
        consoleErrors.push(`[ConsoleError] ${text}`);
      }
    }
  };

  page.on("pageerror", errorHandler);
  page.on("console", consoleHandler);

  const viewsChecked: string[] = ["stats", "calendar", "history", "lists"];
  const modalsChecked: string[] = ["SearchModal", "CreateModal", "SettingsModal"];

  try {
    // 1. Check lazy views
    for (const v of viewsChecked) {
      await page.goto(`${baseUrl}/?view=${v}`, { waitUntil: "domcontentloaded" });
      await page.waitForTimeout(600);
    }

    // 2. Return to home to test modals
    await page.goto(`${baseUrl}/?view=home`, { waitUntil: "domcontentloaded" });
    await page.waitForTimeout(600);

    // SearchModal
    await page.keyboard.press("Control+KeyK");
    await page.waitForTimeout(400);
    await page.keyboard.press("Escape");
    await page.waitForTimeout(200);

    // CreateModal
    const addBtn = page.getByRole("button", { name: /Добавить|Add/i });
    if ((await addBtn.count()) > 0) {
      await addBtn.first().click();
      await page.waitForTimeout(400);
      await page.keyboard.press("Escape");
      await page.waitForTimeout(200);
    }

    // SettingsModal
    const settingsBtn = page.locator('[data-widget="sidebar"] button[title*="Настройки"], [data-widget="sidebar"] button[title*="Settings"]').first();
    if ((await settingsBtn.count()) > 0) {
      await settingsBtn.click();
      await page.waitForTimeout(400);
      await page.keyboard.press("Escape");
      await page.waitForTimeout(200);
    }
  } finally {
    page.off("pageerror", errorHandler);
    page.off("console", consoleHandler);
  }

  return {
    passed: consoleErrors.length === 0,
    viewsChecked,
    modalsChecked,
    consoleErrors,
    durationMs: Date.now() - startTime,
  };
}

export async function runBrowserSuite(): Promise<BrowserSuiteSummary> {
  const suiteStartTime = Date.now();
  console.log("==================================================================");
  console.log("🚀 STARTING CONSOLIDATED PLAYWRIGHT BROWSER AUDIT SUITE");
  console.log("==================================================================");

  let harness: ServerHarness | null = null;
  let browser: Browser | null = null;
  let context: BrowserContext | null = null;

  try {
    harness = await ensureTestServer();
    console.log(`[Suite] Test server ready at ${harness.baseUrl}`);

    browser = await chromium.launch({
      channel:
        process.env.TS_BROWSER_CHANNEL || (process.platform === "win32" ? "msedge" : undefined),
      headless: true,
    });
    context = await browser.newContext({ viewport: { width: 1440, height: 900 } });
    const page = await context.newPage();

    // PHASE 1: Lazy views & modals chunk loading check
    console.log("\n▶ PHASE 1: Verifying lazy chunks and modal mounting...");
    const lazyResult = await verifyLazyChunks(page, harness.baseUrl);
    console.log(
      `  Status: ${lazyResult.passed ? "✅ PASS" : "❌ FAIL"} (${lazyResult.durationMs}ms)`,
    );
    if (!lazyResult.passed) {
      console.error("  Console errors encountered during lazy loading:");
      for (const err of lazyResult.consoleErrors) {
        console.error(`    ${err}`);
      }
    }

    // PHASE 2: CDP Performance Profiler
    console.log("\n▶ PHASE 2: Running Chrome DevTools Protocol (CDP) Profiler...");
    const cdpStart = Date.now();
    const cdpReport: CdpReport = await runCdpProfiler({
      page,
      baseUrl: harness.baseUrl,
      seededIds: harness.seededIds,
    });
    const cdpDuration = Date.now() - cdpStart;
    console.log(
      `  Status: ${cdpReport.passed ? "✅ PASS" : "❌ FAIL"} (${cdpDuration}ms, ${cdpReport.violations.length} violations)`,
    );
    console.log(
      `  Heaviest by Layout: ${cdpReport.heaviestScreen.byLayout} (${cdpReport.heaviestScreen.maxLayoutMs}ms)`,
    );
    console.log(`  Memory Leak Delta:  ${cdpReport.memoryLeakTest.heapDeltaMb}MB`);

    // PHASE 3: Layout Geometry Assertions
    console.log("\n▶ PHASE 3: Inspecting Layout Geometry & DOM assertions...");
    const geomStart = Date.now();
    const geomReport: LayoutGeometryReport = await runLayoutGeometry({
      page,
      baseUrl: harness.baseUrl,
      seededIds: harness.seededIds,
    });
    const geomDuration = Date.now() - geomStart;
    console.log(
      `  Status: ${geomReport.passed ? "✅ PASS" : "❌ FAIL"} (${geomDuration}ms, ${geomReport.totalAnomalies} anomalies)`,
    );

    // PHASE 4: Axe-core Accessibility & Contrast
    console.log("\n▶ PHASE 4: Auditing Accessibility with @axe-core/playwright...");
    const axeStart = Date.now();
    const axeReport: AxeReport = await runAxeAccessibility({
      page,
      baseUrl: harness.baseUrl,
      seededIds: harness.seededIds,
    });
    const axeDuration = Date.now() - axeStart;
    console.log(
      `  Status: ${axeReport.passed ? "✅ PASS" : "❌ FAIL"} (${axeDuration}ms, ${axeReport.totalCriticalAndSerious} critical/serious violations)`,
    );

    // PHASE 5: Visual Component Snapshots
    console.log("\n▶ PHASE 5: Running Pixel-by-Pixel Visual Snapshots...");
    const visualStart = Date.now();
    const visualReport: VisualReport = await runVisualSnapshots({
      page,
      baseUrl: harness.baseUrl,
      seededIds: harness.seededIds,
    });
    const visualDuration = Date.now() - visualStart;
    console.log(
      `  Status: ${visualReport.passed ? "✅ PASS" : "❌ FAIL"} (${visualDuration}ms, Matched: ${visualReport.matched}, Created: ${visualReport.created}, Mismatched: ${visualReport.mismatched})`,
    );

    // PHASE 6: Google Core Web Vitals (LCP, CLS, FID, FCP)
    console.log("\n▶ PHASE 6: Collecting Google Core Web Vitals...");
    const vitalsStart = Date.now();
    const vitalsReport: WebVitalsReport = await runWebVitals({
      page,
      baseUrl: harness.baseUrl,
      seededIds: harness.seededIds,
    });
    const vitalsDuration = Date.now() - vitalsStart;
    console.log(
      `  Status: ${vitalsReport.passed ? "✅ PASS" : "❌ FAIL"} (${vitalsDuration}ms, ${vitalsReport.violations.length} violations)`,
    );

    const totalSuiteDuration = Date.now() - suiteStartTime;
    const allPassed =
      lazyResult.passed &&
      cdpReport.passed &&
      geomReport.passed &&
      axeReport.passed &&
      visualReport.passed &&
      vitalsReport.passed;

    const summary: BrowserSuiteSummary = {
      timestamp: new Date().toISOString(),
      totalDurationMs: totalSuiteDuration,
      serverUrl: harness.baseUrl,
      phases: {
        lazyChunks: lazyResult,
        cdpProfiler: {
          passed: cdpReport.passed,
          durationMs: cdpDuration,
          violations: cdpReport.violations,
          heaviestScreen: cdpReport.heaviestScreen,
          memoryLeakDeltaMb: cdpReport.memoryLeakTest.heapDeltaMb,
        },
        layoutGeometry: {
          passed: geomReport.passed,
          durationMs: geomDuration,
          totalScreensChecked: geomReport.totalScreensChecked,
          totalAnomalies: geomReport.totalAnomalies,
        },
        axeAccessibility: {
          passed: axeReport.passed,
          durationMs: axeDuration,
          totalScreensScanned: axeReport.totalScreensScanned,
          criticalAndSeriousCount: axeReport.totalCriticalAndSerious,
        },
        visualSnapshots: {
          passed: visualReport.passed,
          durationMs: visualDuration,
          totalSnapshots: visualReport.totalSnapshots,
          matched: visualReport.matched,
          mismatched: visualReport.mismatched,
          created: visualReport.created,
          updated: visualReport.updated,
        },
        webVitals: {
          passed: vitalsReport.passed,
          durationMs: vitalsDuration,
          totalScreensChecked: vitalsReport.screens.length,
          violations: vitalsReport.violations,
        },
      },
      passed: allPassed,
    };

    fs.mkdirSync(reportsDir, { recursive: true });
    fs.writeFileSync(
      path.join(reportsDir, "browser-suite-summary.json"),
      JSON.stringify(summary, null, 2),
      "utf-8",
    );

    console.log("\n==================================================================");
    console.log(
      `🏁 BROWSER SUITE COMPLETE: ${allPassed ? "ALL PHASES PASSED" : "FAILED"} in ${(totalSuiteDuration / 1000).toFixed(1)}s`,
    );
    console.log("==================================================================");

    return summary;
  } finally {
    if (context) await context.close().catch(() => {});
    if (browser) await browser.close().catch(() => {});
    if (harness) await harness.stop().catch(() => {});
  }
}

if (process.argv[1] && fileURLToPath(import.meta.url) === path.resolve(process.argv[1])) {
  runBrowserSuite()
    .then((summary) => {
      if (!summary.passed) {
        process.exitCode = 1;
      }
    })
    .catch((err) => {
      console.error("[Suite Fatal Error]", err);
      process.exitCode = 1;
    });
}
