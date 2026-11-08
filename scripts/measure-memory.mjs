#!/usr/bin/env node
/**
 * Memory benchmark: boots a throwaway Tsundoku server, walks it through
 * cold idle -> stress load -> hibernation (POST /api/system/trim-memory)
 * and reports RSS / GC heap at each stage, both as a console table and as
 * reports/memory-benchmark.json.
 *
 * Usage: node scripts/measure-memory.mjs [--keep]
 *   --keep  keep the temporary server data dir for inspection
 */
import { spawn, execSync } from "node:child_process";
import fs from "node:fs";
import net from "node:net";
import os from "node:os";
import path from "node:path";
import process from "node:process";
import { fileURLToPath } from "node:url";

const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);
const rootDir = path.resolve(__dirname, "..");
const reportsDir = path.resolve(rootDir, "reports");
const keepData = process.argv.includes("--keep");

fs.mkdirSync(reportsDir, { recursive: true });

/**
 * Finds the server to measure. The published NativeAOT binary is the real desktop artifact and
 * has a completely different RSS profile (no JIT, no CoreCLR runtime), so it is preferred; the
 * framework-dependent DLL is the dev-mode fallback.
 */
function findServerBinary() {
  const candidates = [
    { file: "dist/Tsundoku-Portable/Tsundoku", argv: [] },
    { file: "MediaTracker.Server/bin/Release/net10.0/Tsundoku.dll", argv: [] },
    { file: "MediaTracker.Server/bin/Debug/net10.0/Tsundoku.dll", argv: [] },
  ].map(({ file, argv }) => ({ file: path.resolve(rootDir, file), argv }));
  for (const candidate of candidates) {
    if (fs.existsSync(candidate.file)) return candidate;
  }
  return null;
}

function findFreePort() {
  return new Promise((resolve, reject) => {
    const srv = net.createServer();
    srv.listen(0, "127.0.0.1", () => {
      const address = srv.address();
      if (!address || typeof address === "string") {
        srv.close(() => reject(new Error("Unable to determine free port")));
        return;
      }
      const port = address.port;
      srv.close((err) => (err ? reject(err) : resolve(port)));
    });
    srv.on("error", reject);
  });
}

async function waitForServer(url, timeoutMs = 60_000) {
  const start = Date.now();
  while (Date.now() - start < timeoutMs) {
    try {
      const res = await fetch(`${url}/health`, { signal: AbortSignal.timeout(1500) });
      if (res.ok) return;
    } catch {
      // not up yet
    }
    await sleep(500);
  }
  throw new Error(`Server did not become healthy at ${url} within ${timeoutMs}ms`);
}

const sleep = (ms) => new Promise((resolve) => setTimeout(resolve, ms));

/** RSS of the process in MB: /proc on Linux, ps on macOS. */
function readRssMb(pid) {
  try {
    if (process.platform === "linux") {
      const status = fs.readFileSync(`/proc/${pid}/status`, "utf8");
      const match = status.match(/VmRSS:\s+(\d+)\s+kB/);
      if (match) return Math.round((Number(match[1]) / 1024) * 10) / 10;
    } else {
      const out = execSync(`ps -o rss= -p ${pid}`).toString();
      return Math.round((Number(out.trim()) / 1024) * 10) / 10;
    }
  } catch {
    // process gone
  }
  return null;
}

/** GC heap + working set straight from the server itself. */
async function readServerMemory(baseUrl) {
  const res = await fetch(`${baseUrl}/api/system/trim-memory`, { method: "POST" });
  if (!res.ok) throw new Error(`trim-memory answered ${res.status}`);
  return res.json();
}

/** Seeds N lightweight rows so the list/stats queries have real payload to chew on. */
async function seedItems(baseUrl, count) {
  const types = ["movie", "tvshow", "anime", "manga", "book", "game"];
  const batchSize = 50;
  for (let offset = 0; offset < count; offset += batchSize) {
    const promises = [];
    for (let i = offset; i < Math.min(offset + batchSize, count); i++) {
      const type = types[i % types.length];
      promises.push(
        fetch(`${baseUrl}/api/media`, {
          method: "POST",
          headers: { "Content-Type": "application/json" },
          body: JSON.stringify({
            type,
            title: `Memory Bench Item ${i}: ${type}`,
            status: i % 5,
            score: i % 10,
            author: type === "book" || type === "manga" ? `Author ${i}` : undefined,
            totalChapters: type === "manga" ? 120 : undefined,
            totalPages: type === "book" ? 350 : undefined,
            durationMinutes: type === "movie" ? 110 : undefined,
            platform: type === "game" ? "PC" : undefined,
            description: `Synthetic description row ${i} for the memory benchmark. `.repeat(8),
          }),
        }),
      );
    }
    await Promise.allSettled(promises);
  }
}

/** Concurrent mixed load: big list reads, stats, offline search. */
async function stress(baseUrl, seconds = 8) {
  const endpoints = [
    "/api/media",
    "/api/media?type=manga",
    "/api/media/stats/advanced",
    "/api/media/stats/taste-profile",
    "/api/lists",
    "/api/media/calendar",
    "/api/external/search?type=all&query=NORAGAMI%20STRESS%20PROBE",
  ];
  const deadline = Date.now() + seconds * 1000;
  let requests = 0;
  while (Date.now() < deadline) {
    await Promise.allSettled(endpoints.map((endpoint) => fetch(`${baseUrl}${endpoint}`)));
    requests += endpoints.length;
  }
  return requests;
}

function mb(value) {
  return value === null || value === undefined ? "n/a" : `${value} МБ`;
}

function printTable(rows) {
  const columns = [
    { title: "Состояние", width: 22 },
    { title: "RSS (МБ)", width: 13, key: "rss" },
    { title: "GC Heap (МБ)", width: 13, key: "gc" },
  ];
  const line = (left, middle, right) =>
    `┌${"─".repeat(columns[0].width + 2)}┬${"─".repeat(columns[1].width + 2)}┬${"─".repeat(columns[2].width + 2)}┐`;
  const row = (cells) =>
    `│ ${String(cells[0]).padEnd(columns[0].width)} │ ${String(cells[1]).padStart(columns[1].width)} │ ${String(cells[2]).padStart(columns[2].width)} │`;
  const divider = (left, fill, mid, right) =>
    `${left}${fill.repeat(columns[0].width + 2)}${mid}${fill.repeat(columns[1].width + 2)}${mid}${fill.repeat(columns[2].width + 2)}${right}`;

  console.log(line());
  console.log(row(columns.map((c) => c.title)));
  console.log(divider("├", "─", "┼", "┤"));
  for (const entry of rows) {
    console.log(row([entry.label, entry.rss ?? "n/a", entry.gc ?? "n/a"]));
  }
  console.log(divider("└", "─", "┴", "┘"));
}

async function main() {
  const server = findServerBinary();
  if (!server) {
    console.error("Server binary not found. Run: dotnet publish MediaTracker.Server -c Release -r linux-x64");
    process.exit(1);
  }
  const isNative = !server.file.endsWith(".dll");

  const port = await findFreePort();
  const dataDir = fs.mkdtempSync(path.join(os.tmpdir(), "tsundoku-membench-"));
  const baseUrl = `http://127.0.0.1:${port}`;

  console.log(
    `Starting MediaTracker.Server on port ${port} (data: ${dataDir}, ` +
      `${isNative ? "NativeAOT binary" : "JIT dll"})...`,
  );
  const serverProc = spawn(
    isNative ? server.file : "dotnet",
    [...(isNative ? [] : [server.file]), "--headless", "--port", port.toString(), "--data-dir", dataDir],
    {
      cwd: path.resolve(rootDir, "MediaTracker.Server"),
      stdio: "pipe",
      env: {
        ...process.env,
        ASPNETCORE_ENVIRONMENT: "Production",
        // Same glibc arena caps the real AppRun exports; without them the measured RSS is
        // not representative of the shipped desktop binary.
        MALLOC_ARENA_MAX: "2",
        MALLOC_TRIM_THRESHOLD_: "131072",
      },
    },
  );
  serverProc.stdout.on("data", () => {});
  serverProc.stderr.on("data", () => {});

  const result = {
    generatedAt: new Date().toISOString(),
    platform: `${process.platform}/${os.arch()}`,
    binary: isNative ? "NativeAOT" : "JIT dll",
    pid: serverProc.pid,
    stages: {},
  };

  try {
    await waitForServer(baseUrl);

    // ── 1. Старт (Cold Idle) ────────────────────────────────────────────────
    // 4s: the server runs its own post-startup baseline trim 3s after ApplicationStarted, so
    // sampling at 2s measured the pre-trim peak and Cold Idle could never show the new floor.
    await sleep(4000); // let the start-up migrations, shell hooks and baseline trim settle
    let rss = readRssMb(serverProc.pid);
    let mem = await readServerMemory(baseUrl);
    result.stages.coldIdle = { rssMb: rss, gcHeapMb: mem.after.gcHeapMb, workingSetMb: mem.after.workingSetMb };
    console.log(`Старт: RSS ${mb(rss)}, GC heap ${mb(mem.after.gcHeapMb)}`);

    // ── 2. Нагрузка (Stress) ────────────────────────────────────────────────
    console.log("Seeding 500 items...");
    await seedItems(baseUrl, 500);
    console.log("Stress load for 10s...");
    const requests = await stress(baseUrl, 10);
    rss = readRssMb(serverProc.pid);
    mem = await readServerMemory(baseUrl);
    result.stressRequests = requests;
    result.stages.peakLoad = { rssMb: rss, gcHeapMb: mem.before.gcHeapMb, workingSetMb: mem.before.workingSetMb };
    console.log(`Нагрузка (${requests} req): RSS ${mb(rss)}, GC heap ${mb(mem.before.gcHeapMb)}`);

    // ── 3. Режим сна (Sleep) — trim уже выполнен запросом выше ─────────────
    // Второй проход с паузой: часть страниц ядро возвращает с задержкой (madvise/finalizers),
    // поэтому фиксируем дно, а не первый после трима замер.
    await sleep(2500);
    mem = await readServerMemory(baseUrl);
    rss = readRssMb(serverProc.pid);
    result.stages.sleepMode = { rssMb: rss, gcHeapMb: mem.after.gcHeapMb, workingSetMb: mem.after.workingSetMb };
    console.log(`Сон: RSS ${mb(rss)}, GC heap ${mb(mem.after.gcHeapMb)}`);

    // ── 4. Мгновенность ответа после сна ───────────────────────────────────
    const t0 = performance.now();
    const list = await fetch(`${baseUrl}/api/media`);
    await list.json();
    result.firstRequestAfterSleepMs = Math.round(performance.now() - t0);

    const freed = {
      workingSetMb: mem.freedWorkingSetMb,
      gcHeapMb: mem.freedGcHeapMb,
    };
    printTable([
      { label: "Старт (Cold Idle)", rss: result.stages.coldIdle.rssMb, gc: result.stages.coldIdle.gcHeapMb },
      { label: "Нагрузка (Stress)", rss: result.stages.peakLoad.rssMb, gc: result.stages.peakLoad.gcHeapMb },
      { label: "Режим сна (Sleep)", rss: result.stages.sleepMode.rssMb, gc: result.stages.sleepMode.gcHeapMb },
    ]);
    console.log(
      `\nОсвобождено тримом: working set ${mb(freed.workingSetMb)}, GC heap ${mb(freed.gcHeapMb)}. ` +
        `Первый запрос после сна: ${result.firstRequestAfterSleepMs} мс.`,
    );

    const reportPath = path.resolve(reportsDir, "memory-benchmark.json");
    fs.writeFileSync(reportPath, JSON.stringify(result, null, 2));
    console.log(`\nОтчёт: ${reportPath}`);
  } finally {
    serverProc.kill("SIGTERM");
    await sleep(1500);
    if (!serverProc.killed) serverProc.kill("SIGKILL");
    if (!keepData) {
      fs.rmSync(dataDir, { recursive: true, force: true });
    }
  }
}

main().catch((error) => {
  console.error(error);
  process.exit(1);
});
