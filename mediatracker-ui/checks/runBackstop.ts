import { spawn } from "node:child_process";
import fs from "node:fs";
import path from "node:path";
import process from "node:process";
import { fileURLToPath } from "node:url";
import { ensureTestServer } from "./testServerHarness.ts";

const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);
const uiDir = path.resolve(__dirname, "..");
const rootDir = path.resolve(uiDir, "..");
const reportsDir = path.resolve(rootDir, "reports");
const summaryPath = path.resolve(reportsDir, "backstop-summary.json");
const htmlReportDir = path.resolve(reportsDir, "backstop_data/html_report");

fs.mkdirSync(reportsDir, { recursive: true });

async function runBackstopCli(command: "reference" | "test", targetUrl: string): Promise<number> {
  console.log(`\n[runBackstop] Executing "backstop ${command}" for ${targetUrl}...`);

  return new Promise((resolve) => {
    const proc = spawn("npx", ["backstop", command, "--config=backstop.config.cjs"], {
      cwd: uiDir,
      stdio: "inherit",
      env: {
        ...process.env,
        TARGET_URL: targetUrl,
      },
    });

    proc.on("close", (code) => {
      resolve(code ?? 0);
    });
    proc.on("error", (err) => {
      console.error("[runBackstop] Failed to spawn BackstopJS:", err);
      resolve(1);
    });
  });
}

function parseBackstopReport(exitCode: number) {
  const configJsPath = path.resolve(htmlReportDir, "config.js");
  let tests = [];

  if (fs.existsSync(configJsPath)) {
    try {
      const content = fs.readFileSync(configJsPath, "utf-8");
      // Format is report({ ... });
      const jsonStr = content.replace(/^\s*report\s*\(\s*/, "").replace(/\s*\)\s*;\s*$/, "");
      const reportData = JSON.parse(jsonStr);
      tests = reportData.tests || [];
    } catch (err) {
      console.warn("[runBackstop] Could not parse config.js report:", err);
    }
  }

  const results = tests.map((t: any) => {
    const pair = t.pair || {};
    return {
      label: pair.label || "unknown",
      viewport: pair.viewportLabel || "unknown",
      width: pair.viewport?.width,
      height: pair.viewport?.height,
      status: t.status || (pair.diff ? "pass" : "fail"),
      misMatchPercentage: pair.diff?.misMatchPercentage ?? 0,
      diffImage: pair.diffImage,
    };
  });

  const passedCount = results.filter((r) => r.status === "pass").length;
  const failedCount = results.filter((r) => r.status === "fail").length;

  const summary = {
    timestamp: new Date().toISOString(),
    command: "test",
    totalScenarios: results.length,
    passedCount,
    failedCount,
    allPassed: exitCode === 0 && failedCount === 0,
    htmlReportPath: "reports/backstop_data/html_report/index.html",
    scenarios: results,
  };

  fs.writeFileSync(summaryPath, JSON.stringify(summary, null, 2), "utf-8");
  console.log(`\n=== BackstopJS Summary written to ${summaryPath} ===`);
  console.log(`Total tests: ${results.length} (Passed: ${passedCount}, Failed: ${failedCount})`);
  console.log(`Interactive HTML Report with Before/After slider: ${htmlReportDir}/index.html\n`);

  return summary;
}

async function main() {
  const mode = process.argv[2] === "reference" || process.argv[2] === "approve" ? "reference" : "test";
  console.log(`=== BackstopJS Visual Regression Suite (Mode: ${mode}) ===`);

  const harness = await ensureTestServer();
  try {
    const exitCode = await runBackstopCli(mode, harness.baseUrl);

    if (mode === "test") {
      const summary = parseBackstopReport(exitCode);
      if (!summary.allPassed) {
        console.error("❌ Visual regression tests found mismatches!");
        process.exit(exitCode !== 0 ? exitCode : 1);
      } else {
        console.log("✅ All visual scenarios matched references perfectly!");
      }
    } else {
      console.log(`\n✅ References generated and approved successfully in mediatracker-ui/checks/backstop_data/bitmaps_reference`);
    }
  } finally {
    await harness.stop();
  }
}

main().catch((err) => {
  console.error("Backstop run failed:", err);
  process.exit(1);
});
