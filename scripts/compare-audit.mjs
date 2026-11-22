import { createRequire } from "node:module";
import fs from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const require = createRequire(path.join(__dirname, "../mediatracker-ui/package.json"));
const pixelmatchPkg = require("pixelmatch");
const pixelmatch = pixelmatchPkg.default || pixelmatchPkg;
const { PNG } = require("pngjs");

const SVELTE_DIR = process.env.TS_SVELTE_DIR || "/tmp/tsundoku-pixel-audit/svelte";
const FLUTTER_DIR = process.env.TS_FLUTTER_DIR || "/tmp/tsundoku-pixel-audit/flutter";
const DIFF_DIR = process.env.TS_DIFF_DIR || "/tmp/tsundoku-pixel-audit/diff";

fs.mkdirSync(DIFF_DIR, { recursive: true });

const files = fs.readdirSync(SVELTE_DIR).filter((f) => f.endsWith(".png")).sort();

console.log(`\n========================================================================`);
console.log(`🔍 PIXEL PARITY AUDIT AT 1920x1080 (Svelte vs Flutter)`);
console.log(`========================================================================\n`);

let totalDiffRatio = 0;
const results = [];

for (const file of files) {
  const sveltePath = path.join(SVELTE_DIR, file);
  const flutterPath = path.join(FLUTTER_DIR, file);

  if (!fs.existsSync(flutterPath)) {
    console.warn(`⚠️ Missing Flutter screenshot: ${flutterPath}`);
    continue;
  }

  const imgSvelte = PNG.sync.read(fs.readFileSync(sveltePath));
  const imgFlutter = PNG.sync.read(fs.readFileSync(flutterPath));

  const { width, height } = imgSvelte;
  const diff = new PNG({ width, height });

  const numDiffPixels = pixelmatch(
    imgSvelte.data,
    imgFlutter.data,
    diff.data,
    width,
    height,
    { threshold: 0.15, includeAA: false }
  );

  const totalPixels = width * height;
  const diffPercent = ((numDiffPixels / totalPixels) * 100).toFixed(2);
  const matchPercent = (100 - (numDiffPixels / totalPixels) * 100).toFixed(2);

  const diffPath = path.join(DIFF_DIR, file);
  fs.writeFileSync(diffPath, PNG.sync.write(diff));

  results.push({ file, numDiffPixels, diffPercent, matchPercent });
  console.log(
    `[${file}] -> Match: ${matchPercent}% | Diff Pixels: ${numDiffPixels} (${diffPercent}%) | Diff saved to ${diffPath}`
  );
}

console.log(`\n========================================================================\n`);
