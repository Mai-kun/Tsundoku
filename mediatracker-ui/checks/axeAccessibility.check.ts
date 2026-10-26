import fs from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";
import { chromium, type Page, type BrowserContext } from "playwright";
import AxeBuilder from "@axe-core/playwright";
import { ensureTestServer, type SeededIds } from "./testServerHarness.ts";

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const reportsDir = path.resolve(__dirname, "../../reports");

export interface AxeCheckViolationNode {
  target: string[];
  html: string;
  failureSummary: string;
}

export interface AxeCheckViolation {
  id: string;
  impact: string;
  description: string;
  help: string;
  helpUrl: string;
  nodes: AxeCheckViolationNode[];
}

export interface ScreenAxeResult {
  screen: string;
  url: string;
  violationsCount: number;
  criticalAndSeriousCount: number;
  violations: AxeCheckViolation[];
}

export interface AxeReport {
  timestamp: string;
  totalScreensScanned: number;
  totalCriticalAndSerious: number;
  passed: boolean;
  screens: ScreenAxeResult[];
}

export async function runAxeAccessibility(options: {
  page: Page;
  baseUrl: string;
  seededIds: SeededIds;
}): Promise<AxeReport> {
  const { page, baseUrl, seededIds } = options;
  await page.setViewportSize({ width: 1440, height: 900 });

  const screensToScan = [
    { name: "home", url: `${baseUrl}/?view=home` },
    { name: "game", url: `${baseUrl}/?view=game` },
    { name: "stats", url: `${baseUrl}/?view=stats` },
    { name: "lists", url: `${baseUrl}/?view=lists` },
    { name: "history", url: `${baseUrl}/?view=history` },
  ];

  const targetDetailId = seededIds.gameId || seededIds.tvshowId || seededIds.allIds[0];
  if (targetDetailId) {
    screensToScan.push({
      name: "detail",
      url: `${baseUrl}/?view=detail&mediaId=${targetDetailId}`,
    });
  }

  const results: ScreenAxeResult[] = [];
  let totalCriticalAndSerious = 0;

  for (const s of screensToScan) {
    await page.goto(s.url, { waitUntil: "domcontentloaded" });
    await page.waitForTimeout(600);

    const axeResult = await new AxeBuilder({ page })
      .withTags(["wcag2a", "wcag2aa", "wcag21a", "wcag21aa"])
      .analyze();

    const criticalAndSerious = axeResult.violations.filter(
      (v) => v.impact === "critical" || v.impact === "serious",
    );
    totalCriticalAndSerious += criticalAndSerious.length;

    results.push({
      screen: s.name,
      url: s.url,
      violationsCount: axeResult.violations.length,
      criticalAndSeriousCount: criticalAndSerious.length,
      violations: criticalAndSerious.map((v) => ({
        id: v.id,
        impact: v.impact || "unknown",
        description: v.description,
        help: v.help,
        helpUrl: v.helpUrl,
        nodes: v.nodes.map((n) => ({
          target: n.target.map((t) => (typeof t === "string" ? t : JSON.stringify(t))),
          html: n.html,
          failureSummary: n.failureSummary || "",
        })),
      })),
    });
  }

  // Check SearchModal
  await page.keyboard.press("Control+KeyK");
  await page.waitForTimeout(500);

  const searchAxe = await new AxeBuilder({ page })
    .withTags(["wcag2a", "wcag2aa", "wcag21a", "wcag21aa"])
    .analyze();

  const searchCS = searchAxe.violations.filter(
    (v) => v.impact === "critical" || v.impact === "serious",
  );
  totalCriticalAndSerious += searchCS.length;

  results.push({
    screen: "SearchModal",
    url: `${baseUrl}/#search`,
    violationsCount: searchAxe.violations.length,
    criticalAndSeriousCount: searchCS.length,
    violations: searchCS.map((v) => ({
      id: v.id,
      impact: v.impact || "unknown",
      description: v.description,
      help: v.help,
      helpUrl: v.helpUrl,
      nodes: v.nodes.map((n) => ({
        target: n.target.map((t) => (typeof t === "string" ? t : JSON.stringify(t))),
        html: n.html,
        failureSummary: n.failureSummary || "",
      })),
    })),
  });

  // Close search modal
  await page.keyboard.press("Escape");
  await page.waitForTimeout(300);

  const report: AxeReport = {
    timestamp: new Date().toISOString(),
    totalScreensScanned: results.length,
    totalCriticalAndSerious,
    passed: totalCriticalAndSerious === 0,
    screens: results,
  };

  fs.mkdirSync(reportsDir, { recursive: true });
  fs.writeFileSync(
    path.join(reportsDir, "axe-accessibility.json"),
    JSON.stringify(report, null, 2),
    "utf-8",
  );

  return report;
}

// Standalone execution
if (process.argv[1] && fileURLToPath(import.meta.url) === path.resolve(process.argv[1])) {
  (async () => {
    console.log("[axeAccessibility] Starting standalone axe-core accessibility audit...");
    const harness = await ensureTestServer();
    const browser = await chromium.launch({
      channel:
        process.env.TS_BROWSER_CHANNEL || (process.platform === "win32" ? "msedge" : undefined),
      headless: true,
    });
    const context: BrowserContext = await browser.newContext({
      viewport: { width: 1440, height: 900 },
    });
    const page = await context.newPage();

    try {
      const report = await runAxeAccessibility({
        page,
        baseUrl: harness.baseUrl,
        seededIds: harness.seededIds,
      });

      console.log("\n--- Axe Accessibility Summary ---");
      for (const s of report.screens) {
        console.log(
          `  ${s.screen.padEnd(20)} | Critical/Serious: ${s.criticalAndSeriousCount} | Total: ${s.violationsCount}`,
        );
        for (const v of s.violations) {
          console.log(`    - [${v.impact}] ${v.id}: ${v.help} (${v.nodes.length} nodes)`);
        }
      }

      if (!report.passed) {
        console.error(
          `\n[axeAccessibility] FAILED: ${report.totalCriticalAndSerious} critical/serious violations found!`,
        );
        process.exitCode = 1;
      } else {
        console.log("\n[axeAccessibility] PASSED: 0 critical/serious accessibility violations!");
      }
    } finally {
      await browser.close();
      await harness.stop();
    }
  })();
}
