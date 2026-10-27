#!/usr/bin/env node
/**
 * scripts/inspect-sqlite-health.mjs
 * Inspects SQLite database file health, WAL size, fragmentation, and page integrity.
 */

import { execSync } from "node:child_process";
import fs from "node:fs";
import path from "node:path";
import process from "node:process";
import { fileURLToPath } from "node:url";

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const rootDir = path.resolve(__dirname, "..");
const reportsDir = path.resolve(rootDir, "reports");

if (!fs.existsSync(reportsDir)) {
  fs.mkdirSync(reportsDir, { recursive: true });
}

function findDatabasePath() {
  const cliArg = process.argv[2];
  if (cliArg && fs.existsSync(cliArg)) return path.resolve(cliArg);

  const candidates = [
    path.join(reportsDir, "tracker.db"),
    path.join(rootDir, "data/tracker.dev.db"),
    path.join(rootDir, "data/tracker.db"),
    path.join(rootDir, "MediaTracker.Server/verify-data/tracker.db"),
    path.join(rootDir, "mediatracker-ui/checks/__fixtures__/tracker.db"),
  ];

  for (const c of candidates) {
    if (fs.existsSync(c)) return c;
  }

  // Fallback: create empty report DB if none exist
  const defaultPath = path.join(reportsDir, "tracker.db");
  const fixture = path.join(rootDir, "mediatracker-ui/checks/__fixtures__/tracker.db");
  if (fs.existsSync(fixture)) {
    fs.copyFileSync(fixture, defaultPath);
    return defaultPath;
  }
  return null;
}

function runSqlitePragma(dbPath, pragma) {
  try {
    const stdout = execSync(`sqlite3 "${dbPath}" "${pragma}"`, {
      encoding: "utf-8",
      stdio: ["ignore", "pipe", "pipe"],
    });
    return stdout.trim();
  } catch (err) {
    // Fallback to python3 sqlite3 if sqlite3 CLI had an issue
    try {
      const pythonCmd = `python3 -c "import sqlite3; con=sqlite3.connect('${dbPath}'); cur=con.cursor(); print(cur.execute('${pragma}').fetchall())"`;
      const res = execSync(pythonCmd, { encoding: "utf-8" });
      return res.trim();
    } catch {
      throw new Error(`Failed to execute PRAGMA ${pragma}: ${err.message}`);
    }
  }
}

export function inspectSqliteHealth(targetDb) {
  const dbPath = targetDb || findDatabasePath();
  if (!dbPath || !fs.existsSync(dbPath)) {
    throw new Error(`Database file not found at ${dbPath}`);
  }

  const stat = fs.statSync(dbPath);
  const dbSizeKb = +(stat.size / 1024).toFixed(2);

  const walPath = `${dbPath}-wal`;
  const walSizeKb = fs.existsSync(walPath) ? +(fs.statSync(walPath).size / 1024).toFixed(2) : 0;

  const shmPath = `${dbPath}-shm`;
  const shmSizeKb = fs.existsSync(shmPath) ? +(fs.statSync(shmPath).size / 1024).toFixed(2) : 0;

  const pageCountRaw = runSqlitePragma(dbPath, "PRAGMA page_count;");
  const pageSizeRaw = runSqlitePragma(dbPath, "PRAGMA page_size;");
  const freelistRaw = runSqlitePragma(dbPath, "PRAGMA freelist_count;");
  const integrityStatusRaw = runSqlitePragma(dbPath, "PRAGMA integrity_check;");
  const checkpointRaw = runSqlitePragma(dbPath, "PRAGMA wal_checkpoint(PASSIVE);");

  const pageCount = parseInt(pageCountRaw, 10) || 0;
  const pageSize = parseInt(pageSizeRaw, 10) || 4096;
  const freelistCount = parseInt(freelistRaw, 10) || 0;
  const integrityStatus = integrityStatusRaw.toLowerCase().includes("ok") ? "ok" : integrityStatusRaw;

  const fragmentationPercent = pageCount > 0 ? +((freelistCount / pageCount) * 100).toFixed(2) : 0;
  const needsVacuum = fragmentationPercent > 15 || freelistCount > 100;
  const status = needsVacuum ? "WARN" : "PASS";
  const recommendation = needsVacuum
    ? "Фрагментация превышает порог. Рекомендуется выполнить PRAGMA vacuum; для сжатия базы."
    : "База данных компактна и дефрагментирована. Оптимизация VACUUM не требуется.";

  const report = {
    dbPath: path.relative(rootDir, dbPath),
    dbSizeKb,
    walSizeKb,
    shmSizeKb,
    pageSize,
    pageCount,
    freelistCount,
    fragmentationPercent,
    integrityStatus,
    walCheckpoint: checkpointRaw || "0|0|0",
    needsVacuum,
    status,
    recommendation,
    inspectedAt: new Date().toISOString(),
  };

  const outputPath = path.join(reportsDir, "sqlite-health.json");
  fs.writeFileSync(outputPath, JSON.stringify(report, null, 2), "utf-8");

  console.log(`\n🗄️  [SQLite Health] DB: ${report.dbPath}`);
  console.log(`   Size: ${dbSizeKb} KB | WAL: ${walSizeKb} KB | Pages: ${pageCount} (Size: ${pageSize} B)`);
  console.log(`   Freelist Pages: ${freelistCount} | Fragmentation: ${fragmentationPercent}%`);
  console.log(`   Integrity: ${integrityStatus} | Needs VACUUM: ${needsVacuum} (${status})`);

  return report;
}

if (process.argv[1] && fileURLToPath(import.meta.url) === path.resolve(process.argv[1])) {
  try {
    inspectSqliteHealth();
  } catch (err) {
    console.error("❌ SQLite Health inspection failed:", err.message);
    process.exit(1);
  }
}
