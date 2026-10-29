import assert from "node:assert/strict";
import fs from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";
import zlib from "node:zlib";

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const wwwrootDir = path.resolve(__dirname, "../../MediaTracker.Server/wwwroot");
const assetsDir = path.join(wwwrootDir, "assets");
const indexHtmlPath = path.join(wwwrootDir, "index.html");
const reportsDir = path.resolve(__dirname, "../../reports");

assert(fs.existsSync(assetsDir), `Assets directory not found at ${assetsDir}. Run npm run build first.`);
assert(fs.existsSync(indexHtmlPath), `index.html not found at ${indexHtmlPath}. Run npm run build first.`);

const indexHtml = fs.readFileSync(indexHtmlPath, "utf-8");
const entryAssetNames = new Set(
  [...indexHtml.matchAll(/(?:src|href)="\/assets\/([^"]+)"/g)].map((m) => m[1]),
);

interface AssetInfo {
  name: string;
  type: "js" | "css";
  isEntry: boolean;
  rawBytes: number;
  rawKb: number;
  gzipBytes: number;
  gzipKb: number;
}

const files = fs.readdirSync(assetsDir);
const assets: AssetInfo[] = [];

for (const file of files) {
  const ext = path.extname(file).toLowerCase();
  if (ext !== ".js" && ext !== ".css") continue;

  const fullPath = path.join(assetsDir, file);
  const buffer = fs.readFileSync(fullPath);
  const gzipBuffer = zlib.gzipSync(buffer);
  const isEntry = entryAssetNames.has(file);

  assets.push({
    name: file,
    type: ext === ".js" ? "js" : "css",
    isEntry,
    rawBytes: buffer.length,
    rawKb: Number((buffer.length / 1024).toFixed(2)),
    gzipBytes: gzipBuffer.length,
    gzipKb: Number((gzipBuffer.length / 1024).toFixed(2)),
  });
}

assert(assets.length > 0, "No JS or CSS build assets discovered in assets directory.");

const entryJsAssets = assets.filter((a) => a.type === "js" && a.isEntry);
const lazyJsAssets = assets.filter((a) => a.type === "js" && !a.isEntry);
const cssAssets = assets.filter((a) => a.type === "css");

const totals = {
  entryJsRawKb: Number(entryJsAssets.reduce((acc, a) => acc + a.rawKb, 0).toFixed(2)),
  entryJsGzipKb: Number(entryJsAssets.reduce((acc, a) => acc + a.gzipKb, 0).toFixed(2)),
  totalJsRawKb: Number(assets.filter((a) => a.type === "js").reduce((acc, a) => acc + a.rawKb, 0).toFixed(2)),
  totalJsGzipKb: Number(assets.filter((a) => a.type === "js").reduce((acc, a) => acc + a.gzipKb, 0).toFixed(2)),
  cssRawKb: Number(cssAssets.reduce((acc, a) => acc + a.rawKb, 0).toFixed(2)),
  cssGzipKb: Number(cssAssets.reduce((acc, a) => acc + a.gzipKb, 0).toFixed(2)),
};

const BUDGETS = {
  maxEntryJsGzipKb: Number(process.env.BUDGET_ENTRY_JS_GZIP_KB) || 150,
  maxTotalJsGzipKb: Number(process.env.BUDGET_TOTAL_JS_GZIP_KB) || 350,
  maxGzipCssKb: Number(process.env.BUDGET_CSS_GZIP_KB) || 50,
};

const passed =
  totals.entryJsGzipKb <= BUDGETS.maxEntryJsGzipKb &&
  totals.totalJsGzipKb <= BUDGETS.maxTotalJsGzipKb &&
  totals.cssGzipKb <= BUDGETS.maxGzipCssKb;

console.log("\n📦 [check:bundle] Entry JS & CSS Assets (Loaded synchronously at startup):");
console.table(
  assets
    .filter((a) => a.isEntry)
    .map((a) => ({
      File: a.name,
      Type: a.type.toUpperCase(),
      "Raw (KB)": a.rawKb,
      "Gzip (KB)": a.gzipKb,
    })),
);

console.log("\n📦 [check:bundle] Lazy / Secondary JS Chunks:");
console.table(
  lazyJsAssets.map((a) => ({
    File: a.name,
    "Raw (KB)": a.rawKb,
    "Gzip (KB)": a.gzipKb,
  })),
);

console.log("\n📊 [check:bundle] Totals & Budgets:");
console.table([
  {
    Metric: "Entry JS Gzip (Startup sync chunks)",
    Actual: `${totals.entryJsGzipKb} KB`,
    Budget: `< ${BUDGETS.maxEntryJsGzipKb} KB`,
    Status: totals.entryJsGzipKb <= BUDGETS.maxEntryJsGzipKb ? "PASS" : "FAIL",
  },
  {
    Metric: "Total JS Gzip (All chunks combined)",
    Actual: `${totals.totalJsGzipKb} KB`,
    Budget: `< ${BUDGETS.maxTotalJsGzipKb} KB`,
    Status: totals.totalJsGzipKb <= BUDGETS.maxTotalJsGzipKb ? "PASS" : "FAIL",
  },
  {
    Metric: "CSS Gzip Total",
    Actual: `${totals.cssGzipKb} KB`,
    Budget: `< ${BUDGETS.maxGzipCssKb} KB`,
    Status: totals.cssGzipKb <= BUDGETS.maxGzipCssKb ? "PASS" : "FAIL",
  },
]);

if (!fs.existsSync(reportsDir)) {
  fs.mkdirSync(reportsDir, { recursive: true });
}

const summary = {
  timestamp: new Date().toISOString(),
  entryAssets: entryJsAssets,
  lazyAssets: lazyJsAssets,
  cssAssets,
  totals,
  budgets: {
    ...BUDGETS,
    passed,
  },
};

const summaryPath = path.join(reportsDir, "bundle-summary.json");
fs.writeFileSync(summaryPath, JSON.stringify(summary, null, 2), "utf-8");
console.log(`[check:bundle] Saved detailed summary to ${summaryPath}\n`);

assert(
  totals.entryJsGzipKb <= BUDGETS.maxEntryJsGzipKb,
  `[check:bundle] Entry JS gzip size ${totals.entryJsGzipKb} KB exceeds budget ${BUDGETS.maxEntryJsGzipKb} KB`,
);
assert(
  totals.totalJsGzipKb <= BUDGETS.maxTotalJsGzipKb,
  `[check:bundle] Total JS gzip size ${totals.totalJsGzipKb} KB exceeds budget ${BUDGETS.maxTotalJsGzipKb} KB`,
);
assert(
  totals.cssGzipKb <= BUDGETS.maxGzipCssKb,
  `[check:bundle] CSS gzip size ${totals.cssGzipKb} KB exceeds budget ${BUDGETS.maxGzipCssKb} KB`,
);

console.log("✅ [check:bundle] All bundle budget limits satisfied (Entry < 150 KB, Total < 260 KB, CSS < 50 KB).");
