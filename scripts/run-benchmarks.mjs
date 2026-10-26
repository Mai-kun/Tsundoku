#!/usr/bin/env node
import { spawn } from "node:child_process";
import fs from "node:fs";
import path from "node:path";
import process from "node:process";
import { fileURLToPath } from "node:url";

const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);
const rootDir = path.resolve(__dirname, "..");
const reportsDir = path.resolve(rootDir, "reports");
const benchmarksArtifactsDir = path.resolve(reportsDir, "benchmarks");
const summaryPath = path.resolve(reportsDir, "benchmarks-summary.json");

fs.mkdirSync(benchmarksArtifactsDir, { recursive: true });

// Budgets in nanoseconds and bytes
const BUDGETS = {
  CalculateAdvancedStats: { maxMeanNs: 15_000_000, maxAllocatedBytes: 2_000_000 },
  CalculateTasteProfile: { maxMeanNs: 15_000_000, maxAllocatedBytes: 2_000_000 },
  EvaluateSmartList: { maxMeanNs: 10_000_000, maxAllocatedBytes: 200_000 },
  EvaluateCandidates: { maxMeanNs: 200_000, maxAllocatedBytes: 40_000 },
  NormalizeGenres: { maxMeanNs: 50_000, maxAllocatedBytes: 50_000 },
  ParseMangalibJson: { maxMeanNs: 5_000_000, maxAllocatedBytes: 500_000 },
  ReadAnyRecordsCsv: { maxMeanNs: 5_000_000, maxAllocatedBytes: 500_000 },
};

function formatTime(ns) {
  if (ns >= 1_000_000_000) return `${(ns / 1_000_000_000).toFixed(2)} s`;
  if (ns >= 1_000_000) return `${(ns / 1_000_000).toFixed(2)} ms`;
  if (ns >= 1_000) return `${(ns / 1_000).toFixed(2)} μs`;
  return `${ns.toFixed(1)} ns`;
}

function formatBytes(bytes) {
  if (bytes === null || bytes === undefined) return "N/A";
  if (bytes >= 1_048_576) return `${(bytes / 1_048_576).toFixed(2)} MB`;
  if (bytes >= 1024) return `${(bytes / 1024).toFixed(2)} KB`;
  return `${bytes} B`;
}

async function runBenchmarks() {
  console.log("=== Running BenchmarkDotNet (Release, ShortRunJob) ===");
  const args = [
    "run",
    "-c",
    "Release",
    "--project",
    "MediaTracker.Benchmarks",
    "--",
    "--filter",
    "*",
    "--exporters",
    "json",
    "github",
    "--artifacts",
    "./reports/benchmarks",
  ];

  await new Promise((resolve, reject) => {
    const child = spawn("dotnet", args, {
      cwd: rootDir,
      stdio: "inherit",
      env: { ...process.env, DOTNET_CLI_TELEMETRY_OPTOUT: "1" },
    });
    child.on("close", (code) => {
      if (code === 0) resolve();
      else reject(new Error(`BenchmarkDotNet exited with code ${code}`));
    });
    child.on("error", reject);
  });
}

function parseReports() {
  const resultsDir = path.resolve(benchmarksArtifactsDir, "results");
  if (!fs.existsSync(resultsDir)) {
    throw new Error(`Results directory not found: ${resultsDir}`);
  }

  let files = fs
    .readdirSync(resultsDir)
    .filter(
      (f) =>
        f.endsWith("-report-full-compressed.json") ||
        f.endsWith("-report-full.json") ||
        f.endsWith("-report.json")
    );
  if (files.length === 0) {
    throw new Error(`No *-report-full.json files found in ${resultsDir}`);
  }

  const benchmarkItems = [];
  let allBudgetsPassed = true;

  for (const file of files) {
    const filePath = path.join(resultsDir, file);
    const content = JSON.parse(fs.readFileSync(filePath, "utf-8"));

    const benchmarks = content.Benchmarks || [];
    for (const b of benchmarks) {
      const methodName = b.Method || b.TargetMethod || b.DisplayInfo;
      const stats = b.Statistics;
      const memory = b.Memory;

      const meanNs = stats?.Mean ?? 0;
      let allocatedBytes = memory?.BytesAllocatedPerOperation ?? 0;
      let gen0 = memory?.Gen0Collections ?? 0;
      let gen1 = memory?.Gen1Collections ?? 0;
      let gen2 = memory?.Gen2Collections ?? 0;

      if (Array.isArray(b.Metrics)) {
        for (const m of b.Metrics) {
          if (m.Descriptor?.Id === "Allocated Memory" || m.Descriptor?.DisplayName === "Allocated") {
            allocatedBytes = m.Value ?? allocatedBytes;
          }
          if (m.Descriptor?.Id === "Gen0Collects" || m.Descriptor?.DisplayName === "Gen0") {
            gen0 = m.Value ?? gen0;
          }
          if (m.Descriptor?.Id === "Gen1Collects" || m.Descriptor?.DisplayName === "Gen1") {
            gen1 = m.Value ?? gen1;
          }
          if (m.Descriptor?.Id === "Gen2Collects" || m.Descriptor?.DisplayName === "Gen2") {
            gen2 = m.Value ?? gen2;
          }
        }
      }

      const budget = BUDGETS[methodName];
      let passed = true;
      const violations = [];

      if (budget) {
        if (meanNs > budget.maxMeanNs) {
          passed = false;
          violations.push(`Time ${formatTime(meanNs)} > budget ${formatTime(budget.maxMeanNs)}`);
        }
        if (allocatedBytes > budget.maxAllocatedBytes) {
          passed = false;
          violations.push(
            `Allocated ${formatBytes(allocatedBytes)} > budget ${formatBytes(budget.maxAllocatedBytes)}`
          );
        }
      }

      if (!passed) allBudgetsPassed = false;

      benchmarkItems.push({
        method: methodName,
        type: b.Type || content.Title || file.replace("-report-full.json", ""),
        meanNs,
        meanFormatted: formatTime(meanNs),
        allocatedBytes,
        allocatedFormatted: formatBytes(allocatedBytes),
        gen0,
        gen1,
        gen2,
        budgetPassed: passed,
        violations,
      });
    }
  }

  const summary = {
    generatedAt: new Date().toISOString(),
    totalBenchmarks: benchmarkItems.length,
    allBudgetsPassed,
    benchmarks: benchmarkItems,
  };

  fs.writeFileSync(summaryPath, JSON.stringify(summary, null, 2), "utf-8");
  console.log(`\n=== Benchmarks Summary written to ${summaryPath} ===`);
  console.table(
    benchmarkItems.map((b) => ({
      Method: b.method,
      Mean: b.meanFormatted,
      Allocated: b.allocatedFormatted,
      "Gen0/1/2": `${b.gen0}/${b.gen1}/${b.gen2}`,
      Passed: b.budgetPassed ? "PASS" : "FAIL",
    }))
  );

  if (!allBudgetsPassed) {
    console.warn("\n⚠️ Some benchmarks violated their budget limits:");
    for (const b of benchmarkItems.filter((x) => !x.budgetPassed)) {
      console.warn(` - ${b.method}: ${b.violations.join(", ")}`);
    }
  } else {
    console.log("\n✅ All benchmark budgets satisfied!");
  }

  return { summary, allBudgetsPassed };
}

async function main() {
  try {
    if (!process.argv.includes("--skip-run")) {
      await runBenchmarks();
    }
    const { allBudgetsPassed } = parseReports();
    if (!allBudgetsPassed) {
      console.warn("Notice: Benchmarks finished with budget warnings (non-fatal for pipeline).");
    }
  } catch (err) {
    console.error("Benchmark run failed:", err);
    process.exit(1);
  }
}

main();
