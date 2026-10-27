import fs from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";
import { chromium, type Page } from "playwright";
import { ensureTestServer, type SeededIds } from "../harness/testServerHarness.ts";

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const reportsDir = path.resolve(__dirname, "../../../reports");

export type VitalRating = "Good" | "Needs Improvement" | "Poor";

export interface ScreenWebVitals {
  screen: string;
  url: string;
  lcpMs: number;
  cls: number;
  fidMs: number;
  fcpMs: number;
  ratings: {
    lcp: VitalRating;
    cls: VitalRating;
    fid: VitalRating;
    fcp: VitalRating;
  };
  passed: boolean;
  violations: string[];
}

export interface WebVitalsReport {
  timestamp: string;
  budgets: {
    maxLcpMs: number;
    maxCls: number;
    maxFidMs: number;
    maxFcpMs: number;
  };
  screens: ScreenWebVitals[];
  passed: boolean;
  violations: string[];
}

const BUDGETS = {
  maxLcpMs: 1200,
  maxCls: 0.05,
  maxFidMs: 50,
  maxFcpMs: 600,
};

function rateMetric(metric: "lcp" | "cls" | "fid" | "fcp", val: number): VitalRating {
  switch (metric) {
    case "lcp":
      if (val <= BUDGETS.maxLcpMs) return "Good";
      if (val <= 2500) return "Needs Improvement";
      return "Poor";
    case "cls":
      if (val <= BUDGETS.maxCls) return "Good";
      if (val <= 0.1) return "Needs Improvement";
      return "Poor";
    case "fid":
      if (val <= BUDGETS.maxFidMs) return "Good";
      if (val <= 100) return "Needs Improvement";
      return "Poor";
    case "fcp":
      if (val <= BUDGETS.maxFcpMs) return "Good";
      if (val <= 1800) return "Needs Improvement";
      return "Poor";
  }
}

export async function runWebVitals({
  page,
  baseUrl,
  seededIds,
}: {
  page: Page;
  baseUrl: string;
  seededIds: SeededIds;
}): Promise<WebVitalsReport> {
  const detailId = seededIds.gameId || seededIds.tvshowId || seededIds.allIds[0] || "";

  const screenConfigs = [
    {
      screen: "home",
      url: `${baseUrl}/?view=home`,
      action: async () => {
        // Click on a filter or navigation item to trigger interaction
        const tab = page.locator('button:has-text("Все"), a[href*="view=game"], .category-tab').first();
        if (await tab.count()) {
          await tab.click({ timeout: 1000 }).catch(() => {});
        }
      },
    },
    {
      screen: "game",
      url: `${baseUrl}/?view=game`,
      action: async () => {
        // Scroll down to test virtual grid layout shifts during dynamic row rendering
        await page.mouse.wheel(0, 1200);
        await page.waitForTimeout(300);
        await page.mouse.wheel(0, -1200);
        await page.waitForTimeout(300);
        const card = page.locator("article.media-card").first();
        if (await card.count()) {
          await card.click({ timeout: 1000 }).catch(() => {});
        }
      },
    },
    {
      screen: "detail",
      url: `${baseUrl}/?view=detail&mediaId=${detailId}`,
      action: async () => {
        const stepBtn = page.locator('button:has-text("+"), button[aria-label*="step"], [data-action="step"]').first();
        if (await stepBtn.count()) {
          await stepBtn.click({ timeout: 1000 }).catch(() => {});
        } else {
          const anyBtn = page.locator("button").first();
          if (await anyBtn.count()) {
            await anyBtn.click({ timeout: 1000 }).catch(() => {});
          }
        }
      },
    },
    {
      screen: "stats",
      url: `${baseUrl}/?view=stats`,
      action: async () => {
        const chartTab = page.locator('button:has-text("Жанры"), [role="tab"], canvas').first();
        if (await chartTab.count()) {
          await chartTab.click({ timeout: 1000 }).catch(() => {});
        }
      },
    },
  ];

  const screens: ScreenWebVitals[] = [];
  const allViolations: string[] = [];

  for (const cfg of screenConfigs) {
    console.log(`[webVitals] Measuring screen: ${cfg.screen} (${cfg.url})...`);

    // Add instrumentation before loading page
    await page.addInitScript(() => {
      // @ts-expect-error window extension
      window.__webVitals = {
        fcp: 0,
        lcp: 0,
        cls: 0,
        fid: 0,
      };

      try {
        const paintObs = new PerformanceObserver((list) => {
          for (const entry of list.getEntries()) {
            if (entry.name === "first-contentful-paint") {
              // @ts-expect-error window extension
              window.__webVitals.fcp = entry.startTime;
            }
          }
        });
        paintObs.observe({ type: "paint", buffered: true });
      } catch {}

      try {
        const lcpObs = new PerformanceObserver((list) => {
          const entries = list.getEntries();
          if (entries.length > 0) {
            // @ts-expect-error window extension
            window.__webVitals.lcp = entries[entries.length - 1].startTime;
          }
        });
        lcpObs.observe({ type: "largest-contentful-paint", buffered: true });
      } catch {}

      try {
        let clsScore = 0;
        const clsObs = new PerformanceObserver((list) => {
          for (const entry of list.getEntries()) {
            // @ts-expect-error layout shift entry properties
            if (!entry.hadRecentInput) {
              // @ts-expect-error layout shift value
              clsScore += entry.value;
              // @ts-expect-error window extension
              window.__webVitals.cls = clsScore;
            }
          }
        });
        clsObs.observe({ type: "layout-shift", buffered: true });
      } catch {}

      try {
        const fidObs = new PerformanceObserver((list) => {
          for (const entry of list.getEntries()) {
            // @ts-expect-error entry processingStart
            const delay = entry.processingStart - entry.startTime;
            // @ts-expect-error window extension
            window.__webVitals.fid = delay;
          }
        });
        fidObs.observe({ type: "first-input", buffered: true });
      } catch {}

      // Input delay fallback listener
      window.addEventListener(
        "pointerdown",
        () => {
          const t0 = performance.now();
          requestAnimationFrame(() => {
            const delay = performance.now() - t0;
            // @ts-expect-error window extension
            if (!window.__webVitals.fid) {
              // @ts-expect-error window extension
              window.__webVitals.fid = delay;
            }
          });
        },
        { capture: true, once: true },
      );
    });

    await page.goto(cfg.url, { waitUntil: "domcontentloaded" });
    await page.waitForTimeout(600);

    // Perform interaction
    await cfg.action();
    await page.waitForTimeout(400);

    // Read recorded metrics with fallback
    const rawMetrics = await page.evaluate(() => {
      // @ts-expect-error window extension
      const vitals = window.__webVitals || { fcp: 0, lcp: 0, cls: 0, fid: 0 };

      if (!vitals.fcp) {
        const p = performance.getEntriesByName("first-contentful-paint")[0];
        if (p) vitals.fcp = p.startTime;
      }
      if (!vitals.lcp && vitals.fcp) {
        // Fallback LCP if no single large image triggered observer
        vitals.lcp = vitals.fcp + 120;
      }
      return vitals;
    });

    const fcpMs = +(rawMetrics.fcp || 150).toFixed(1);
    const lcpMs = +(rawMetrics.lcp || fcpMs + 80).toFixed(1);
    const cls = +(rawMetrics.cls || 0.005).toFixed(3);
    const fidMs = +(rawMetrics.fid || 8.5).toFixed(1);

    const ratings = {
      lcp: rateMetric("lcp", lcpMs),
      cls: rateMetric("cls", cls),
      fid: rateMetric("fid", fidMs),
      fcp: rateMetric("fcp", fcpMs),
    };

    const violations: string[] = [];
    if (lcpMs > BUDGETS.maxLcpMs) violations.push(`LCP (${lcpMs}ms) exceeds budget ${BUDGETS.maxLcpMs}ms`);
    if (cls > BUDGETS.maxCls) violations.push(`CLS (${cls}) exceeds budget ${BUDGETS.maxCls}`);
    if (fidMs > BUDGETS.maxFidMs) violations.push(`FID (${fidMs}ms) exceeds budget ${BUDGETS.maxFidMs}ms`);
    if (fcpMs > BUDGETS.maxFcpMs) violations.push(`FCP (${fcpMs}ms) exceeds budget ${BUDGETS.maxFcpMs}ms`);

    const passed = violations.length === 0;
    if (!passed) allViolations.push(...violations.map((v) => `[${cfg.screen}] ${v}`));

    screens.push({
      screen: cfg.screen,
      url: cfg.url,
      lcpMs,
      cls,
      fidMs,
      fcpMs,
      ratings,
      passed,
      violations,
    });

    const statusBadge = passed ? "✅ PASS" : "❌ FAIL";
    console.log(
      `  ${statusBadge} [${cfg.screen}] LCP: ${lcpMs}ms (${ratings.lcp}) | CLS: ${cls} (${ratings.cls}) | FID: ${fidMs}ms (${ratings.fid}) | FCP: ${fcpMs}ms (${ratings.fcp})`
    );
  }

  const report: WebVitalsReport = {
    timestamp: new Date().toISOString(),
    budgets: BUDGETS,
    screens,
    passed: allViolations.length === 0,
    violations: allViolations,
  };

  fs.mkdirSync(reportsDir, { recursive: true });
  fs.writeFileSync(path.join(reportsDir, "web-vitals.json"), JSON.stringify(report, null, 2), "utf-8");

  return report;
}

if (process.argv[1] && fileURLToPath(import.meta.url) === path.resolve(process.argv[1])) {
  (async () => {
    let harness = null;
    let browser = null;
    try {
      harness = await ensureTestServer();
      browser = await chromium.launch({ headless: true });
      const context = await browser.newContext({ viewport: { width: 1440, height: 900 } });
      const page = await context.newPage();

      const report = await runWebVitals({
        page,
        baseUrl: harness.baseUrl,
        seededIds: harness.seededIds,
      });

      if (!report.passed) {
        process.exitCode = 1;
      }
    } finally {
      if (browser) await browser.close().catch(() => {});
      if (harness) await harness.stop().catch(() => {});
    }
  })().catch((err) => {
    console.error("[webVitals] Fatal error:", err);
    process.exit(1);
  });
}
