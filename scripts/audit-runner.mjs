#!/usr/bin/env node
/**
 * scripts/audit-runner.mjs
 * Cross-platform task orchestrator with checksum-based caching for C# benchmarks and profiling.
 * Commands: fix | audit | visual | visual:approve | report
 */

import { spawn, spawnSync } from "node:child_process";
import crypto from "node:crypto";
import fs from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const rootDir = path.resolve(__dirname, "..");
const reportsDir = path.join(rootDir, "reports");
const manifestPath = path.join(reportsDir, ".cache-manifest.json");

if (!fs.existsSync(reportsDir)) {
  fs.mkdirSync(reportsDir, { recursive: true });
}

function run(command, args, options = {}) {
  const displayCmd = `${command} ${args.join(" ")}`;
  console.log(`\n🚀 [run] ${displayCmd}`);
  const startTime = Date.now();
  const res = spawnSync(command, args, {
    stdio: "inherit",
    cwd: rootDir,
    ...options,
  });
  const duration = ((Date.now() - startTime) / 1000).toFixed(2);
  if (res.status !== 0) {
    console.error(`❌ [fail] Command failed with exit code ${res.status} (${duration}s): ${displayCmd}`);
    process.exit(res.status ?? 1);
  }
  console.log(`✅ [done] Finished in ${duration}s: ${displayCmd}`);
}

function runAsync(command, args, options = {}) {
  const displayCmd = `${command} ${args.join(" ")}`;
  return new Promise((resolve, reject) => {
    const startTime = Date.now();
    const child = spawn(command, args, {
      stdio: "pipe",
      cwd: rootDir,
      ...options,
    });
    let output = "";
    child.stdout?.on("data", (d) => { output += d; });
    child.stderr?.on("data", (d) => { output += d; });
    child.on("close", (code) => {
      const duration = ((Date.now() - startTime) / 1000).toFixed(2);
      if (code === 0) {
        console.log(`  ✅ [parallel] ${displayCmd} (${duration}s)`);
        resolve({ code, output, duration });
      } else {
        console.error(`  ❌ [parallel-fail] ${displayCmd} (${duration}s):\n${output}`);
        reject(new Error(`Command failed with code ${code}: ${displayCmd}`));
      }
    });
    child.on("error", (err) => {
      reject(err);
    });
  });
}

function getCsharpChecksum() {
  const hash = crypto.createHash("sha256");
  const dirs = [
    path.join(rootDir, "MediaTracker.Server"),
    path.join(rootDir, "MediaTracker.Benchmarks"),
  ];

  const files = [];
  function scan(dir) {
    if (!fs.existsSync(dir)) return;
    const entries = fs.readdirSync(dir, { withFileTypes: true });
    for (const ent of entries) {
      if (ent.name === "bin" || ent.name === "obj" || ent.name === ".git") continue;
      const full = path.join(dir, ent.name);
      if (ent.isDirectory()) {
        scan(full);
      } else if (ent.name.endsWith(".cs") || ent.name.endsWith(".csproj")) {
        files.push(full);
      }
    }
  }

  for (const d of dirs) scan(d);
  files.sort();

  for (const f of files) {
    hash.update(path.relative(rootDir, f));
    hash.update(fs.readFileSync(f));
  }

  return hash.digest("hex");
}

function loadCacheManifest() {
  if (!fs.existsSync(manifestPath)) return {};
  try {
    return JSON.parse(fs.readFileSync(manifestPath, "utf-8"));
  } catch {
    return {};
  }
}

function saveCacheManifest(manifest) {
  fs.writeFileSync(manifestPath, JSON.stringify(manifest, null, 2), "utf-8");
}

const command = process.argv[2] || "audit";

const totalStart = Date.now();
console.log(`\n======================================================`);
console.log(`⚡ Tsundoku Audit Runner: '${command}'`);
console.log(`======================================================`);

switch (command) {
  case "fix": {
    console.log(`\n▶ Запуск быстрого контура автофикса и статических проверок...`);
    // 1. Frontend format fix
    run("npm", ["--prefix", "mediatracker-ui", "run", "format:fix"]);

    // 2. C# checks with checksum caching
    const csharpHash = getCsharpChecksum();
    const manifest = loadCacheManifest();

    if (manifest.csharpFixChecksum !== csharpHash) {
      const formatCheck = spawnSync("dotnet", ["format", "--verify-no-changes"], { stdio: "inherit", cwd: rootDir });
      if (formatCheck.status !== 0) {
        console.log(`⚠️ Formatting changes needed, running dotnet format...`);
        run("dotnet", ["format"]);
      }
      run("dotnet", ["run", "--project", "MediaTracker.Server/MediaTracker.Server.csproj", "--no-build", "--", "--selfcheck"]);
      manifest.csharpFixChecksum = csharpHash;
      saveCacheManifest(manifest);
    } else {
      console.log(`⚡ [CACHE HIT] C# код не менялся. Быстрый selfcheck без пересборки...`);
      run("dotnet", ["run", "--project", "MediaTracker.Server/MediaTracker.Server.csproj", "--no-build", "--", "--selfcheck"]);
    }

    // 3. Parallel execution of all 10 independent frontend checks
    console.log(`\n🚀 [parallel] Запуск 10 статических проверок фронтенда параллельно...`);
    const pStart = Date.now();
    try {
      await Promise.all([
        runAsync("npm", ["--prefix", "mediatracker-ui", "run", "check"]),
        runAsync("npm", ["--prefix", "mediatracker-ui", "run", "lint:es"]),
        runAsync("npm", ["--prefix", "mediatracker-ui", "run", "lint:css"]),
        runAsync("npm", ["--prefix", "mediatracker-ui", "run", "check:html"]),
        runAsync("npm", ["--prefix", "mediatracker-ui", "run", "check:deslop"]),
        runAsync("npm", ["--prefix", "mediatracker-ui", "run", "check:state-raw"]),
        runAsync("npm", ["--prefix", "mediatracker-ui", "run", "check:perf-marks"]),
        runAsync("npm", ["--prefix", "mediatracker-ui", "run", "check:deadcode"]),
        runAsync("npm", ["--prefix", "mediatracker-ui", "run", "check:i18n"]),
        runAsync("npm", ["--prefix", "mediatracker-ui", "run", "check:leading-chars"]),
      ]);
      const pDur = ((Date.now() - pStart) / 1000).toFixed(2);
      console.log(`✨ [parallel-done] Все 10 проверок фронтенда завершены за ${pDur}s`);
    } catch (err) {
      console.error(`❌ Ошибка в параллельных проверках:`, err.message);
      process.exit(1);
    }
    break;
  }

  case "audit": {
    console.log(`\n▶ Запуск полного автономного комбайна аудита...`);

    // 1. Fast checks
    run("node", ["scripts/audit-runner.mjs", "fix"]);

    // 2. Build frontend and verify bundle budget
    run("npm", ["--prefix", "mediatracker-ui", "run", "check:bundle"]);

    // 3. Browser suite (Playwright CDP, geometry, a11y, snapshots)
    run("npm", ["--prefix", "mediatracker-ui", "run", "check:browser-suite"]);

    // 4. Checksum check for C# benchmarks and macroprofiling
    const csharpHash = getCsharpChecksum();
    const manifest = loadCacheManifest();
    const cachedHash = manifest.csharpChecksum;

    const benchmarksExist = fs.existsSync(path.join(reportsDir, "benchmarks-summary.json")) &&
                            fs.existsSync(path.join(reportsDir, "sqlite-query-plans.json"));
    const backendProfileExists = fs.existsSync(path.join(reportsDir, "backend-profile-summary.json"));

    if (benchmarksExist && cachedHash === csharpHash) {
      console.log(`\n⚡ [CACHE HIT] C# код не менялся (SHA-256: ${csharpHash.slice(0, 12)}). Пропускаем BenchmarkDotNet & SQLite план.`);
    } else {
      console.log(`\n🔨 [CACHE MISS] Изменение в C# или отчеты отсутствуют. Запуск BenchmarkDotNet...`);
      run("node", ["scripts/run-benchmarks.mjs"]);
      manifest.benchmarksGeneratedAt = new Date().toISOString();
    }

    if (backendProfileExists && cachedHash === csharpHash) {
      console.log(`\n⚡ [CACHE HIT] C# код не менялся (SHA-256: ${csharpHash.slice(0, 12)}). Пропускаем макропрофилирование бэкенда.`);
    } else {
      console.log(`\n🔨 [CACHE MISS] Изменение в C# или отчеты отсутствуют. Запуск profile-backend.mjs...`);
      run("node", ["scripts/profile-backend.mjs"]);
      manifest.backendProfileGeneratedAt = new Date().toISOString();
    }

    manifest.csharpChecksum = csharpHash;
    manifest.csharpFixChecksum = csharpHash;
    saveCacheManifest(manifest);

    // 5. Generate summary report
    run("node", ["scripts/generate-audit-report.mjs"]);
    break;
  }

  case "visual": {
    console.log(`\n▶ Запуск визуального теста BackstopJS...`);
    run("npm", ["--prefix", "mediatracker-ui", "run", "visual:test"]);
    run("node", ["scripts/generate-audit-report.mjs"]);
    break;
  }

  case "visual:approve": {
    console.log(`\n▶ Утверждение референсных скриншотов BackstopJS...`);
    run("npm", ["--prefix", "mediatracker-ui", "run", "visual:approve"]);
    run("node", ["scripts/generate-audit-report.mjs"]);
    break;
  }

  case "report": {
    run("node", ["scripts/generate-audit-report.mjs"]);
    break;
  }

  default:
    console.error(`Неизвестная команда: ${command}`);
    console.log(`Использование: node scripts/audit-runner.mjs [fix | audit | visual | visual:approve | report]`);
    process.exit(1);
}

const totalDuration = ((Date.now() - totalStart) / 1000).toFixed(2);
console.log(`\n======================================================`);
console.log(`✨ Все задачи '${command}' успешно завершены за ${totalDuration}s`);
console.log(`======================================================\n`);
