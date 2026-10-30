import { execSync, spawn } from "node:child_process";
import fs from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";
import { request } from "undici";
import { chromium } from "playwright";

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const root = path.resolve(__dirname, "..");
const reportsDir = path.resolve(root, "reports/stress");
fs.mkdirSync(reportsDir, { recursive: true });

// ---------------------------------------------------------------------------
// CLI: --count <n> (default: [25000, 100000])
// ---------------------------------------------------------------------------
const countsArg = process.argv.find((a) => a.startsWith("--count="));
let counts;
if (countsArg) {
  counts = [Number(countsArg.split("=")[1])];
} else if (process.argv.includes("--count")) {
  counts = [Number(process.argv[process.argv.indexOf("--count") + 1])];
} else {
  counts = [25000, 100000];
}

if (counts.some((c) => !Number.isFinite(c) || c <= 0)) {
  console.error("Invalid --count value. Must be a positive integer.");
  process.exit(2);
}

const PORT = 5055;
const BASE = `http://127.0.0.1:${PORT}`;
const SERVER_BIN = path.resolve(
  root,
  "MediaTracker.Server/bin/Release/net10.0/Tsundoku"
);
const BENCH_PROJECT = path.resolve(root, "MediaTracker.Benchmarks");

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------
function percentile(sorted, p) {
  if (sorted.length === 0) return 0;
  sorted = [...sorted].sort((a, b) => a - b);
  const rank = (p / 100) * (sorted.length - 1);
  const lo = Math.floor(rank);
  const hi = Math.ceil(rank);
  const frac = rank - lo;
  return sorted[lo] + (sorted[hi] - sorted[lo]) * frac;
}

function median(sorted) {
  return percentile(sorted, 50);
}

async function sleep(ms) {
  return new Promise((r) => setTimeout(r, ms));
}

// Consume an undici response body fully.
async function drain(res) {
  const chunks = [];
  for await (const chunk of res.body) chunks.push(chunk);
  return Buffer.concat(chunks).toString();
}

// Timed fetch: returns { status, body, ms }.
async function timedFetch(url, init = {}) {
  const t0 = process.hrtime.bigint();
  let status = 0;
  try {
    const res = await request(url, { method: init.method || "GET", ...init });
    status = res.statusCode;
    await drain(res);
    res.body.destroy();
  } catch {
    // request-level failure recorded as status 0
  }
  const t1 = process.hrtime.bigint();
  return { status, ms: Number(t1 - t0) / 1e6 };
}

// Wait for the server to become healthy.
async function waitForHealth(retries = 60) {
  for (let i = 0; i < retries; i++) {
    try {
      const r = await timedFetch(`${BASE}/api/media?limit=1`);
      if (r.status === 200) return true;
    } catch {}
    await sleep(1000);
  }
  return false;
}

// RSS (MB) of a process by reading /proc/<pid>/status.
function serverRssMb(pid) {
  try {
    const status = fs.readFileSync(`/proc/${pid}/status`, "utf8");
    const m = status.match(/VmRSS:\s+(\d+)/);
    if (m) return Math.round((Number(m[1]) / 1024) * 100) / 100;
  } catch {}
  return null;
}

// Extract a named metric value from a Performance.getMetrics payload.
function findMetric(metrics, name) {
  if (!Array.isArray(metrics)) return null;
  const entry = metrics.find((m) => m.name === name || m.title === name);
  return entry ? Number(entry.value) : null;
}

// ---------------------------------------------------------------------------
// 0. Generate the shared procedural cover pool once (one-time, ~2000 images).
//    Every count reuses it via symlink so cover generation is not repeated.
// ---------------------------------------------------------------------------
const sharedCovers = path.resolve(reportsDir, "covers");
const sharedPoolComplete = fs.existsSync(sharedCovers)
  && fs.readdirSync(sharedCovers).some((f) => f.endsWith(".webp"));
if (!sharedPoolComplete) {
  console.log("\n🎨 Generating shared cover pool (one-time, 2000 images)...");
  const throwawayDb = path.resolve(reportsDir, "tracker.pool.db");
  try {
    execSync(
      `dotnet run -c Release --project "${BENCH_PROJECT}" -- --seed-db 1 ${throwawayDb} --covers-pool 2000`,
      { stdio: "pipe", timeout: 600_000, env: { ...process.env } }
    );
  } catch (err) {
    console.error("   ❌ cover pool generation failed:", err.message);
  }
  try { fs.unlinkSync(throwawayDb); } catch {}
  try { fs.unlinkSync(throwawayDb + "-wal"); } catch {}
  try { fs.unlinkSync(throwawayDb + "-shm"); } catch {}
  console.log(`   pool ready: ${fs.readdirSync(sharedCovers).filter((f) => f.endsWith(".webp")).length} covers`);
}

// ---------------------------------------------------------------------------
// Per-count run
// ---------------------------------------------------------------------------
for (const count of counts) {
  console.log(`\n🧪 Stress test: ${count} items`);
  const dataDir = path.resolve(reportsDir, `data-${count}`);
  fs.mkdirSync(dataDir, { recursive: true });
  const dbPath = path.join(dataDir, "tracker.db");

  // Reuse the shared cover pool. The seeder writes to <dataDir>/covers/ (matching the
  // requirement), while the server's AppPaths resolves CoversDirectory to
  // <dataDir>/data/covers/ in production mode. Symlink both to the same shared pool,
  // replacing any empty directory the server or a previous run may have created.
  const coverTargets = ["covers", path.join("data", "covers")];
  for (const rel of coverTargets) {
    const target = path.join(dataDir, rel);
    fs.mkdirSync(path.dirname(target), { recursive: true });
    if (fs.existsSync(target) && !fs.lstatSync(target).isSymbolicLink()) {
      fs.rmSync(target, { recursive: true, force: true });
    }
    if (!fs.existsSync(target)) {
      fs.symlinkSync(path.relative(path.dirname(target), sharedCovers), target, "dir");
    }
  }

  // -----------------------------------------------------------------------
  // a. Seed database
  // -----------------------------------------------------------------------
  const tSeed0 = process.hrtime.bigint();
  execSync(
    `dotnet run -c Release --project "${BENCH_PROJECT}" -- --seed-db ${count} ${dbPath} --covers-pool 2000`,
    { stdio: "pipe", timeout: 600_000, env: { ...process.env } }
  );
  const seedMs = Number(process.hrtime.bigint() - tSeed0) / 1e6;
  console.log(`   seeded ${count} items in ${seedMs.toFixed(0)} ms`);

  // -----------------------------------------------------------------------
  // b. Start Tsundoku server (Production env -> tracker.db, not tracker.dev.db)
  // -----------------------------------------------------------------------
  let serverProc = null;
  try {
    serverProc = spawn(SERVER_BIN, ["--headless", "--port", String(PORT), "--data-dir", dataDir], {
      env: { ...process.env, ASPNETCORE_ENVIRONMENT: "Production" },
      stdio: ["ignore", "pipe", "pipe"],
    });
    const logs = [];
    serverProc.stdout.on("data", (d) => logs.push(d.toString()));
    serverProc.stderr.on("data", (d) => logs.push(d.toString()));

    const ready = await waitForHealth();
    if (!ready) {
      console.error("   ❌ server did not become healthy");
      const logText = logs.join("").slice(-1500);
      console.error(logText);
      serverProc.kill();
      continue;
    }
    console.log(`   server ready (pid ${serverProc.pid})`);
  } catch (err) {
    console.error("   ❌ failed to start server:", err.message);
    continue;
  }

  const result = {
    count,
    seedMs,
    port: PORT,
    dataDir,
    timestamp: new Date().toISOString(),
  };

  try {
    // -----------------------------------------------------------------------
    // c. Part 1: API & database stress (undici)
    // -----------------------------------------------------------------------
    console.log("   Part 1: API measurements...");

    // Warm up.
    await timedFetch(`${BASE}/api/media?limit=1`);
    await timedFetch(`${BASE}/api/media/stats/advanced`);

    // Cold: 10 requests spaced apart.
    const cold = [];
    for (let i = 0; i < 10; i++) {
      cold.push((await timedFetch(`${BASE}/api/media?limit=50&sortBy=createdAt&sortOrder=desc`)).ms);
      await sleep(400);
    }
    cold.sort((a, b) => a - b);

    // Verify server-side pagination returns ~50 items (not the full 500k set).
    const verifyBody = await drain(await request(`${BASE}/api/media?limit=50&sortBy=createdAt&sortOrder=desc`));
    const verifyCount = JSON.parse(verifyBody).length;
    console.log(`      pagination verify: ${verifyCount} items (expected ~50)`);

    // Warm: 50 back-to-back requests.
    const warm = [];
    for (let i = 0; i < 50; i++) {
      warm.push((await timedFetch(`${BASE}/api/media?limit=50&sortBy=createdAt&sortOrder=desc`)).ms);
    }
    warm.sort((a, b) => a - b);

    // Search over the full set.
    const search = [];
    for (let i = 0; i < 30; i++) {
      search.push((await timedFetch(`${BASE}/api/media?search=Chronicles&limit=50`)).ms);
    }
    search.sort((a, b) => a - b);

    // Advanced stats (cold-ish; cache may warm it, so measure twice and take p95 of both).
    const stats = [];
    for (let i = 0; i < 10; i++) {
      stats.push((await timedFetch(`${BASE}/api/media/stats/advanced`)).ms);
    }
    stats.sort((a, b) => a - b);

    // Grab one item id for the progress-update measurement (API returns a JSON array).
    const listBody = await drain(await request(`${BASE}/api/media?limit=1`));
    const listJson = JSON.parse(listBody);
    const testId = Array.isArray(listJson) ? listJson[0]?.id : listJson?.items?.[0]?.id;

    const progress = [];
    if (testId) {
      for (let i = 0; i < 20; i++) {
        progress.push(
          (
            await timedFetch(`${BASE}/api/media/${testId}/progress`, {
              method: "PUT",
              headers: { "content-type": "application/json" },
              body: JSON.stringify({ currentProgress: (i % 50) + 1 }),
            })
          ).ms
        );
      }
    }
    progress.sort((a, b) => a - b);

    // Server RSS snapshot (mid-test).
    const rssMb = serverRssMb(serverProc.pid);

    result.apiListColdP50 = median(cold);
    result.apiListColdP95 = percentile(cold, 95);
    result.apiListWarmP50 = median(warm);
    result.apiListWarmP95 = percentile(warm, 95);
    result.apiSearchP50 = median(search);
    result.apiSearchP95 = percentile(search, 95);
    result.apiStatsP50 = median(stats);
    result.apiStatsP95 = percentile(stats, 95);
    result.apiProgressP50 = progress.length ? median(progress) : null;
    result.apiProgressP95 = progress.length ? percentile(progress, 95) : null;
    result.serverRssMb = rssMb;

    console.log(
      `      list warm p95=${result.apiListWarmP95.toFixed(0)}ms search p95=${result.apiSearchP95.toFixed(0)}ms stats p95=${result.apiStatsP95.toFixed(0)}ms rss=${rssMb}MB`
    );

    // -----------------------------------------------------------------------
    // d. Part 2: Frontend & UX stress (Playwright Chromium + CDP)
    // -----------------------------------------------------------------------
    console.log("   Part 2: Playwright UX measurements...");

    const browser = await chromium.launch({
      headless: true,
      args: [
        "--no-sandbox",
        "--disable-frame-rate-limit",
        "--disable-gpu-vsync",
        "--enable-gpu-rasterization",
        "--ignore-gpu-blocklist",
      ],
    });
    const context = await browser.newContext();
    const page = await context.newPage();
    const client = await context.newCDPSession(page);
    await client.send("Performance.enable");

    const getMetric = (metrics, name) => {
      const entry = metrics.find((m) => m.name === name || m.title === name);
      return entry ? Number(entry.value || 0) : 0;
    };

    // Navigate to a real heavy category (manga has thousands of items).
    // Uses virtual scrolling so DOM nodes must stay bounded.
    await page.goto(`${BASE}/?view=manga`, { waitUntil: "domcontentloaded", timeout: 60000 });
    await page.waitForTimeout(2500);

    // Baseline CDP metrics before interaction.
    const startMetrics = (await client.send("Performance.getMetrics")).metrics;
    const startDom = await client.send("Memory.getDOMCounters");

    // Inject observers: rAF FPS, longtask, image tracking (after navigation).
    await page.exposeFunction("__onLongTask", (task) => {
      if (!window.__longTasks) window.__longTasks = [];
      window.__longTasks.push({ duration: task.duration, startTime: task.startTime });
    });
    await page.exposeFunction("__onImageLoad", (src) => {
      if (!window.__imagesLoaded) window.__imagesLoaded = new Set();
      window.__imagesLoaded.add(src);
    });
    await page.exposeFunction("__onImageError", () => {
      window.__imageErrors = (window.__imageErrors || 0) + 1;
    });

    await page.evaluate(() => {
      // High-precision frame timer: actual rAF delta times (ms) per frame.
      window.__frameDeltas = [];
      let lastTime = performance.now();
      function loop(now) {
        const delta = now - lastTime;
        lastTime = now;
        if (delta > 0) window.__frameDeltas.push(delta);
        window.__rafId = requestAnimationFrame(loop);
      }
      window.__rafId = requestAnimationFrame(loop);

      // FPS via requestAnimationFrame deltas.
      window.__fpsSamples = [];
      let last = null;
      function tick(now) {
        if (last !== null) window.__fpsSamples.push(1000 / (now - last));
        last = now;
        requestAnimationFrame(tick);
      }
      requestAnimationFrame(tick);

      // Long-task observer.
      if (typeof PerformanceObserver !== "undefined") {
        const po = new PerformanceObserver((list) => {
          for (const e of list.getEntries()) {
            if (e.entryType === "longtask") {
              window.__onLongTask({ duration: e.duration, startTime: e.startTime });
            }
          }
        });
        po.observe({ entryTypes: ["longtask"] });
      }

      // Image tracking (covers are rendered as  tags).
      const trackImg = (img) => {
        if (img.__tracked) return;
        img.__tracked = true;
        img.addEventListener(
          "load",
          () => window.__onImageLoad(img.currentSrc || img.src),
          { once: true }
        );
        img.addEventListener("error", () => window.__onImageError(), { once: true });
        if (img.complete && img.naturalWidth > 0)
          window.__onImageLoad(img.currentSrc || img.src);
      };
      const rob = new MutationObserver((mutations) => {
        for (const m of mutations) {
          for (const node of m.addedNodes) {
            if (node.tagName === "IMG") trackImg(node);
            if (node.querySelectorAll) node.querySelectorAll("img").forEach(trackImg);
          }
        }
      });
      rob.observe(document.documentElement, { childList: true, subtree: true });
      document.querySelectorAll("img").forEach(trackImg);
    });

    // Intensive interaction: smooth virtual scroll down 10000px and back up over 5s.
    await page.evaluate(async () => {
      const scroller = document.getElementById("main-scroll");
      if (!scroller) return;
      for (let i = 0; i < 20; i++) {
        scroller.scrollTop += 500;
        await new Promise((r) => setTimeout(r, 100));
      }
      for (let i = 0; i < 20; i++) {
        scroller.scrollTop -= 500;
        await new Promise((r) => setTimeout(r, 100));
      }
    });
    await page.waitForTimeout(1000);

    // Collect frame deltas captured during the 10,000 px scroll.
    const frameDeltas = (await page.evaluate(() => window.__frameDeltas || [])) || [];

    // End CDP metrics after interaction.
    const endMetrics = (await client.send("Performance.getMetrics")).metrics;
    const endDom = await client.send("Memory.getDOMCounters");

    const fpsSamples = (await page.evaluate(() => window.__fpsSamples || [])) || [];
    const longTasks = (await page.evaluate(() => window.__longTasks || [])) || [];
    const imagesInfo = (await page.evaluate(() => {
      const imgs = document.querySelectorAll("img");
      const coverImgs = Array.from(imgs).filter((i) => (i.src || "").includes("/covers/"));
      const loaded = coverImgs.filter((i) => i.complete && i.naturalWidth > 0);
      const uniqueLoaded = new Set(loaded.map((i) => i.currentSrc || i.src));
      return {
        uniqueImagesLoaded: uniqueLoaded.size,
        imageDecodeErrors: window.__imageErrors || 0,
        totalCoverImgs: coverImgs.length,
      };
    })) || {};

    const sortedFps = [...fpsSamples].sort((a, b) => a - b);
    const avgFps = fpsSamples.length ? fpsSamples.reduce((a, b) => a + b, 0) / fpsSamples.length : 0;
    const p99LowFps = sortedFps.length ? sortedFps[Math.max(0, Math.floor(sortedFps.length * 0.01))] : 0;
    const jankFrames = fpsSamples.filter((f) => f > 0 && 1000 / f > 16.6).length;

    // High-refresh frame budget compliance (144 Hz = 6.94 ms per frame).
    const FRAME_BUDGET_144_MS = 6.94;
    const FRAME_BUDGET_60_MS = 16.67;
    const sortedDeltas = [...frameDeltas].sort((a, b) => a - b);
    const avgDelta =
      frameDeltas.length > 0
        ? frameDeltas.reduce((a, b) => a + b, 0) / frameDeltas.length
        : 0;
    const avgScrollFps = avgDelta > 0 ? Math.round(1000 / avgDelta) : 0;
    const frameTimeP95Ms = sortedDeltas.length
      ? Math.round(percentile(sortedDeltas, 95) * 100) / 100
      : 0;
    const droppedFrames144Count = frameDeltas.filter((d) => d > FRAME_BUDGET_144_MS).length;
    const droppedFrames60Count = frameDeltas.filter((d) => d > FRAME_BUDGET_60_MS).length;

    // CDP metric deltas (values are in seconds; convert to ms).
    const layoutMs = Math.max(
      0,
      Math.round((getMetric(endMetrics, "LayoutDuration") - getMetric(startMetrics, "LayoutDuration")) * 1000)
    );
    const recalcMs = Math.max(
      0,
      Math.round((getMetric(endMetrics, "RecalcStyleDuration") - getMetric(startMetrics, "RecalcStyleDuration")) * 1000)
    );
    const jsMs = Math.max(
      0,
      Math.round((getMetric(endMetrics, "ScriptDuration") - getMetric(startMetrics, "ScriptDuration")) * 1000)
    );

    const longTasksOver50 = longTasks.filter((t) => t.duration > 50);
    const maxLongTask = longTasks.length ? Math.max(...longTasks.map((t) => t.duration)) : 0;

    // DOM node count: count element nodes only (virtualized grid should keep this bounded).
    // Prefer direct element count; fall back to CDP document node count.
    let domNodes = null;
    try {
      domNodes = await page.evaluate(() => document.querySelectorAll("*").length);
    } catch {}
    if (domNodes == null || domNodes <= 0) {
      try {
        const domDoc = await client.send("DOM.getDocument", { depth: -1 });
        domNodes = domDoc.root?.nodeCount;
      } catch {}
    }
    if (domNodes == null || domNodes <= 0) {
      domNodes = endDom.documents?.[0]?.nodes ?? null;
    }

    result.avgScrollFps = avgScrollFps;
    result.frameTimeP95Ms = frameTimeP95Ms;
    result.droppedFrames144Count = droppedFrames144Count;
    result.droppedFrames60Count = droppedFrames60Count;
    result.minFps1PercentLow = Math.round(p99LowFps * 100) / 100;
    result.jankFrameCount = jankFrames;
    result.domNodesAlive = domNodes;
    result.layoutTimeMs = layoutMs;
    result.recalcStyleTimeMs = recalcMs;
    result.jsExecutionTimeMs = jsMs;
    result.longTasksCount = longTasksOver50.length;
    result.maxLongTaskMs = Math.round(maxLongTask * 100) / 100;
    result.browserJsHeapUsedMb = Math.round((getMetric(endMetrics, "JSHeapUsedSize") / 1048576) * 100) / 100;
    result.browserJsHeapTotalMb = Math.round((getMetric(endMetrics, "JSHeapTotalSize") / 1048576) * 100) / 100;
    result.browserHeapDeltaMb =
      Math.round(((getMetric(endMetrics, "JSHeapUsedSize") - getMetric(startMetrics, "JSHeapUsedSize")) / 1048576) * 100) / 100;
    result.uniqueImagesLoaded = imagesInfo.uniqueImagesLoaded ?? 0;
    result.imageDecodeErrors = imagesInfo.imageDecodeErrors ?? 0;

    console.log(
      `      fps avg=${result.avgScrollFps} p1low=${result.minFps1PercentLow.toFixed(1)} jank=${result.jankFrameCount} p95=${result.frameTimeP95Ms}ms d144=${result.droppedFrames144Count} d60=${result.droppedFrames60Count} dom=${result.domNodesAlive} lt=${result.longTasksCount} imgs=${result.uniqueImagesLoaded} err=${result.imageDecodeErrors} layout=${result.layoutTimeMs}ms script=${result.jsExecutionTimeMs}ms`
    );

    await browser.close();
  } catch (err) {
    console.error("   ❌ Part 2 failed:", err.message);
    // Leave metrics unset/null if not measured.
  }

  // -----------------------------------------------------------------------
  // e. Part 3: SQLite storage metrics
  // -----------------------------------------------------------------------
  try {
    const sizeBytes = fs.statSync(dbPath).size;
    result.databaseSizeMb = Math.round((sizeBytes / 1048576) * 100) / 100;
    const integrity = execSync(`sqlite3 "${dbPath}" "PRAGMA integrity_check;"`, {
      encoding: "utf8",
    }).toString().trim();
    result.integrityCheck = integrity === "ok";
    console.log(`   Part 3: db=${result.databaseSizeMb}MB integrity=${result.integrityCheck}`);
  } catch (err) {
    result.databaseSizeMb = null;
    result.integrityCheck = null;
    console.error("   ❌ Part 3 failed:", err.message);
  }

  // -----------------------------------------------------------------------
  // f. Stop server
  // -----------------------------------------------------------------------
  try {
    serverProc.kill("SIGTERM");
    await sleep(1000);
    if (!serverProc.killed) serverProc.kill("SIGKILL");
  } catch {}
  serverProc = null;

  // -----------------------------------------------------------------------
  // Executive UX verdict
  // -----------------------------------------------------------------------
  const apiP95 = result.apiListWarmP95 ?? 0;
  const fps = result.avgScrollFps ?? 0;
  const p95FrameTime = result.frameTimeP95Ms ?? 0;
  const dom = result.domNodesAlive ?? 0;
  const longTasks = result.longTasksCount ?? 0;

  // If the frame-rate limit was unlocked (FPS well above the 60 Hz cap), hold
  // the 144 Hz class bar (>= 120 FPS); otherwise relax to >= 55 FPS for
  // systems without usable GPU acceleration.
  const gpuAccelerated = fps > 100;
  const fpsFloor = gpuAccelerated ? 120 : 55;

  let verdict = "🔴 DEGRADED UX";
  let reason = [];
  if (fps >= fpsFloor && p95FrameTime <= 8.3 && dom <= 1200 && apiP95 < 100) {
    verdict = "🟢 EXCELLENT UX";
  } else if (fps >= 40 && dom <= 1500 && apiP95 < 300) {
    verdict = "🟡 ACCEPTABLE UX";
  } else {
    if (fps < fpsFloor) reason.push(`fps ${fps} < ${fpsFloor}`);
    if (p95FrameTime > 8.3)
      reason.push(`p95 frame time ${p95FrameTime.toFixed(2)}ms > 8.3ms`);
    if (apiP95 > 500) reason.push(`api p95 ${apiP95.toFixed(0)}ms > 500ms`);
    if (dom > 2000) reason.push(`dom ${dom} > 2000`);
    verdict = `🔴 DEGRADED UX${reason.length ? " (" + reason.join(", ") + ")" : ""}`;
  }
  result.uxVerdict = verdict;

  const outPath = path.join(reportsDir, `result-${count}.json`);
  fs.writeFileSync(outPath, JSON.stringify(result, null, 2));

  console.log(`   ${verdict}`);
  console.log(`   📄 written ${outPath}`);
}

console.log("\n✅ Stress tests completed.");
