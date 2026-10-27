import fs from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";
import { chromium, type BrowserContext, type Page } from "playwright";
import pixelmatch from "pixelmatch";
import { PNG } from "pngjs";
import { ensureTestServer, type SeededIds } from "../harness/testServerHarness.ts";

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const snapshotsDir = path.resolve(__dirname, "../harness/__snapshots__");
const reportsDir = path.resolve(__dirname, "../../../reports");
const diffsDir = path.resolve(reportsDir, "visual-diffs");

export interface SnapshotResult {
  name: string;
  selector: string;
  status: "created" | "matched" | "updated" | "mismatch";
  totalPixels: number;
  diffPixels: number;
  diffRatio: number;
  diffImagePath?: string;
  baselinePath: string;
}

export interface VisualReport {
  timestamp: string;
  totalSnapshots: number;
  matched: number;
  mismatched: number;
  created: number;
  updated: number;
  passed: boolean;
  snapshots: SnapshotResult[];
}

const STABILIZATION_CSS = `
  *, *::before, *::after {
    transition-duration: 0s !important;
    transition-delay: 0s !important;
    animation-duration: 0s !important;
    animation-delay: 0s !important;
    caret-color: transparent !important;
  }
`;

async function stabilizePage(page: Page): Promise<void> {
  await page.addStyleTag({ content: STABILIZATION_CSS });
  await page.evaluate(async () => {
    if (document.fonts) {
      await document.fonts.ready;
    }
  });
  await page.waitForTimeout(200);
}

function comparePng(
  baselineBuf: Buffer,
  currentBuf: Buffer,
  threshold = 0.1,
): { diffPixels: number; diffRatio: number; diffPng?: PNG } {
  const img1 = PNG.sync.read(baselineBuf);
  const img2 = PNG.sync.read(currentBuf);

  if (img1.width !== img2.width || img1.height !== img2.height) {
    // Pad to largest dimensions for comparison
    const width = Math.max(img1.width, img2.width);
    const height = Math.max(img1.height, img2.height);

    const pad1 = new PNG({ width, height });
    const pad2 = new PNG({ width, height });

    PNG.bitblt(img1, pad1, 0, 0, img1.width, img1.height, 0, 0);
    PNG.bitblt(img2, pad2, 0, 0, img2.width, img2.height, 0, 0);

    const diff = new PNG({ width, height });
    const diffPixels = pixelmatch(pad1.data, pad2.data, diff.data, width, height, { threshold });
    const diffRatio = diffPixels / (width * height);
    return { diffPixels, diffRatio, diffPng: diff };
  }

  const { width, height } = img1;
  const diff = new PNG({ width, height });
  const diffPixels = pixelmatch(img1.data, img2.data, diff.data, width, height, { threshold });
  const diffRatio = diffPixels / (width * height);
  return { diffPixels, diffRatio, diffPng: diff };
}

export async function runVisualSnapshots(options: {
  page: Page;
  baseUrl: string;
  seededIds: SeededIds;
  updateSnapshots?: boolean;
}): Promise<VisualReport> {
  const { page, baseUrl, seededIds } = options;
  const shouldUpdate =
    options.updateSnapshots ||
    process.argv.includes("--update") ||
    process.env.UPDATE_SNAPSHOTS === "1";

  fs.mkdirSync(snapshotsDir, { recursive: true });
  fs.mkdirSync(diffsDir, { recursive: true });
  await page.setViewportSize({ width: 1440, height: 900 });

  const targets = [
    {
      name: "Header",
      view: "home",
      selector: '[data-widget="header"]',
    },
    {
      name: "Sidebar",
      view: "home",
      selector: '[data-widget="sidebar"]',
    },
    {
      name: "FirstMediaCard",
      view: "game",
      selector: "article.media-card:visible",
    },
    {
      name: "StatsHeroBanner",
      view: "stats",
      selector: '[data-widget="stats-hero"]',
    },
    {
      name: "DetailSidebar",
      view: `detail&mediaId=${seededIds.gameId || seededIds.tvshowId || seededIds.allIds[0]}`,
      selector: '[data-widget="detail-sidebar"]',
    },
  ];

  const results: SnapshotResult[] = [];
  let matchedCount = 0;
  let mismatchedCount = 0;
  let createdCount = 0;
  let updatedCount = 0;

  for (const t of targets) {
    console.log(`[visualSnapshots] Navigating to ${t.view} for widget ${t.name}...`);
    const url = `${baseUrl}/?view=${t.view}`;
    await page.goto(url, { waitUntil: "domcontentloaded" });
    const locator = page.locator(t.selector).first();
    await locator.waitFor({ state: "visible", timeout: 15000 });
    await page
      .waitForSelector(".animate-pulse", { state: "detached", timeout: 10000 })
      .catch(() => {});
    await stabilizePage(page);
    await locator.scrollIntoViewIfNeeded().catch(() => {});
    await page.waitForTimeout(200);

    console.log(`[visualSnapshots] Taking screenshot of "${t.name}"...`);
    const currentBuffer = await locator.screenshot({ type: "png", timeout: 10000 });
    const baselineFile = path.join(snapshotsDir, `${t.name}.png`);

    if (!fs.existsSync(baselineFile) || shouldUpdate) {
      const isNew = !fs.existsSync(baselineFile);
      fs.writeFileSync(baselineFile, currentBuffer);
      if (isNew) createdCount++;
      else updatedCount++;

      results.push({
        name: t.name,
        selector: t.selector,
        status: isNew ? "created" : "updated",
        totalPixels: 0,
        diffPixels: 0,
        diffRatio: 0,
        baselinePath: baselineFile,
      });
      continue;
    }

    const baselineBuffer = fs.readFileSync(baselineFile);
    const { diffPixels, diffRatio, diffPng } = comparePng(baselineBuffer, currentBuffer, 0.1);
    const maxAllowedRatio = 0.005; // 0.5% tolerance

    const isMatch = diffRatio <= maxAllowedRatio;

    let diffImagePath: string | undefined;
    if (!isMatch && diffPng) {
      mismatchedCount++;
      diffImagePath = path.join(diffsDir, `${t.name}-diff.png`);
      fs.writeFileSync(diffImagePath, PNG.sync.write(diffPng));
    } else {
      matchedCount++;
    }

    results.push({
      name: t.name,
      selector: t.selector,
      status: isMatch ? "matched" : "mismatch",
      totalPixels: diffPng ? diffPng.width * diffPng.height : 0,
      diffPixels,
      diffRatio: Number(diffRatio.toFixed(5)),
      diffImagePath,
      baselinePath: baselineFile,
    });
  }

  const report: VisualReport = {
    timestamp: new Date().toISOString(),
    totalSnapshots: results.length,
    matched: matchedCount,
    mismatched: mismatchedCount,
    created: createdCount,
    updated: updatedCount,
    passed: mismatchedCount === 0,
    snapshots: results,
  };

  fs.mkdirSync(reportsDir, { recursive: true });
  fs.writeFileSync(
    path.join(reportsDir, "visual-snapshots.json"),
    JSON.stringify(report, null, 2),
    "utf-8",
  );

  return report;
}

// Standalone execution
if (process.argv[1] && fileURLToPath(import.meta.url) === path.resolve(process.argv[1])) {
  (async () => {
    console.log("[visualSnapshots] Starting visual snapshot comparison...");
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
      const report = await runVisualSnapshots({
        page,
        baseUrl: harness.baseUrl,
        seededIds: harness.seededIds,
      });

      console.log("\n--- Visual Snapshots Summary ---");
      for (const s of report.snapshots) {
        console.log(
          `  ${s.name.padEnd(20)} | Status: ${s.status.padEnd(8)} | Diff: ${(s.diffRatio * 100).toFixed(2)}% (${s.diffPixels} px)`,
        );
      }

      if (!report.passed) {
        console.error(`\n[visualSnapshots] FAILED: ${report.mismatched} snapshot mismatches detected!`);
        process.exitCode = 1;
      } else {
        console.log(`\n[visualSnapshots] PASSED! (Matched: ${report.matched}, Created: ${report.created}, Updated: ${report.updated})`);
      }
    } finally {
      await browser.close();
      await harness.stop();
    }
  })();
}
