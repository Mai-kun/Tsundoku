#!/usr/bin/env node
/**
 * scripts/measure-api-payloads.mjs
 * Measures API wire payload sizes (Raw, Gzip, Brotli) and server latency against strict budgets.
 */

import fs from "node:fs";
import path from "node:path";
import process from "node:process";
import { performance } from "node:perf_hooks";
import { fileURLToPath } from "node:url";
import zlib from "node:zlib";
import { ensureTestServer } from "../mediatracker-ui/checks/harness/testServerHarness.ts";

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const rootDir = path.resolve(__dirname, "..");
const reportsDir = path.resolve(rootDir, "reports");

if (!fs.existsSync(reportsDir)) {
  fs.mkdirSync(reportsDir, { recursive: true });
}

async function seedToTarget(baseUrl, targetCount = 500) {
  let existing = [];
  try {
    const res = await fetch(`${baseUrl}/api/media`);
    if (res.ok) {
      existing = await res.json();
    }
  } catch {
    // continue
  }

  const currentCount = Array.isArray(existing) ? existing.length : 0;
  if (currentCount >= targetCount) {
    console.log(`[API Payloads] Database already contains ${currentCount} items (target: ${targetCount}).`);
    return currentCount;
  }

  const toAdd = targetCount - currentCount;
  console.log(`[API Payloads] Seeding ${toAdd} additional items to reach ${targetCount}...`);
  const genres = ["Action", "Adventure", "RPG", "Sci-Fi", "Comedy", "Drama", "Fantasy", "Horror", "Cyberpunk", "Mystery"];
  const batchSize = 25;

  for (let b = 0; b < toAdd; b += batchSize) {
    const promises = [];
    for (let i = b; i < b + batchSize && i < toAdd; i++) {
      const type = i % 5 === 0 ? "game" : i % 5 === 1 ? "movie" : i % 5 === 2 ? "tvshow" : i % 5 === 3 ? "book" : "manga";
      const status = i % 4 === 0 ? 2 : i % 3 === 0 ? 1 : 0;
      const index = currentCount + i + 1;
      const item = {
        type,
        title: `Audit Payload Entity ${index}`,
        status,
        score: (i % 10) + 1,
        releaseYear: 1995 + (i % 30),
        releaseDate: new Date(Date.now() - (i % 60) * 86400000).toISOString(),
        genres: `${genres[i % genres.length]}, ${genres[(i + 3) % genres.length]}`,
        platform: type === "game" ? (i % 2 === 0 ? "PC" : "PlayStation 5") : undefined,
        hoursPlayed: type === "game" ? (i % 95) : undefined,
        durationMinutes: type === "movie" ? (90 + (i % 60)) : undefined,
        author: type === "book" || type === "manga" ? `Author ${index}` : undefined,
        totalPages: type === "book" ? (200 + (i % 400)) : undefined,
        totalChapters: type === "manga" ? (30 + (i % 200)) : undefined,
        description: `Detailed description for media payload benchmark item ${index} verifying server serialization and compression overhead.`,
      };

      promises.push(
        fetch(`${baseUrl}/api/media`, {
          method: "POST",
          headers: { "Content-Type": "application/json" },
          body: JSON.stringify(item),
        })
      );
    }
    await Promise.all(promises);
  }

  console.log(`[API Payloads] Successfully reached ${targetCount} media entries.`);
  return targetCount;
}

const BUDGETS = {
  "/api/media": { maxGzipKb: 60, maxLatencyMs: 80 },
  "/api/media?type=game&status=1": { maxGzipKb: 50, maxLatencyMs: 100 },
  "/api/media/stats/advanced": { maxGzipKb: 20, maxLatencyMs: 100 },
  "/api/media/stats/taste-profile": { maxGzipKb: 10, maxLatencyMs: 100 },
  "/api/media/calendar": { maxGzipKb: 25, maxLatencyMs: 100 },
  "/api/history": { maxGzipKb: 30, maxLatencyMs: 100 },
  "/api/lists": { maxGzipKb: 15, maxLatencyMs: 100 },
};

export async function measureApiPayloads(existingHarness = null) {
  const harness = existingHarness || (await ensureTestServer());
  const shouldStopHarness = !existingHarness;

  try {
    const totalItems = await seedToTarget(harness.baseUrl, 500);

    const endpoints = [
      "/api/media",
      "/api/media?type=game&status=1",
      "/api/media/stats/advanced",
      "/api/media/stats/taste-profile",
      "/api/media/calendar",
      "/api/history",
      "/api/lists",
    ];

    console.log(`\n📡 [API Payloads] Auditing endpoints on ${harness.baseUrl} (Items: ${totalItems})...\n`);

    const results = [];
    let allPassed = true;

    for (const ep of endpoints) {
      const url = `${harness.baseUrl}${ep}`;
      const budget = BUDGETS[ep] || { maxGzipKb: 100, maxLatencyMs: 200 };

      // Warmup request
      try {
        await fetch(url);
      } catch {
        // ignore warmup fail
      }

      // Perform 3 measurements to get stable latency
      const latencies = [];
      let lastBody = "";
      let statusCode = 200;

      for (let run = 0; run < 3; run++) {
        const start = performance.now();
        const res = await fetch(url);
        const text = await res.text();
        const dur = performance.now() - start;
        latencies.push(dur);
        lastBody = text;
        statusCode = res.status;
      }

      latencies.sort((a, b) => a - b);
      const medianLatencyMs = +(latencies[1] || latencies[0]).toFixed(1);

      const rawBuffer = Buffer.from(lastBody, "utf-8");
      const gzipBuffer = zlib.gzipSync(rawBuffer);
      const brotliBuffer = zlib.brotliCompressSync(rawBuffer);

      const rawBytes = rawBuffer.length;
      const rawKb = +(rawBytes / 1024).toFixed(2);
      const gzipBytes = gzipBuffer.length;
      const gzipKb = +(gzipBytes / 1024).toFixed(2);
      const brotliBytes = brotliBuffer.length;
      const brotliKb = +(brotliBytes / 1024).toFixed(2);

      const savingsRatioPercent = rawBytes > 0 ? +((1 - gzipBytes / rawBytes) * 100).toFixed(1) : 0;
      const gzipPassed = gzipKb <= budget.maxGzipKb;
      const latencyPassed = medianLatencyMs <= budget.maxLatencyMs;
      const passed = gzipPassed && latencyPassed && statusCode === 200;

      if (!passed) allPassed = false;

      results.push({
        endpoint: ep,
        method: "GET",
        status: statusCode,
        rawBytes,
        rawKb,
        gzipBytes,
        gzipKb,
        brotliBytes,
        brotliKb,
        savingsRatioPercent,
        latencyMs: medianLatencyMs,
        budget,
        passed,
      });

      const statusBadge = passed ? "✅ PASS" : "❌ FAIL";
      console.log(
        `  ${statusBadge} ${ep.padEnd(32)} | Raw: ${rawKb.toString().padStart(6)} KB | Gzip: ${gzipKb.toString().padStart(5)} KB (${savingsRatioPercent}% saved) | Brotli: ${brotliKb.toString().padStart(5)} KB | Latency: ${medianLatencyMs.toString().padStart(5)} ms`
      );
    }

    const totalRawKb = +(results.reduce((s, r) => s + r.rawKb, 0)).toFixed(2);
    const totalGzipKb = +(results.reduce((s, r) => s + r.gzipKb, 0)).toFixed(2);
    const totalBrotliKb = +(results.reduce((s, r) => s + r.brotliKb, 0)).toFixed(2);
    const averageLatencyMs = +(results.reduce((s, r) => s + r.latencyMs, 0) / results.length).toFixed(1);

    const report = {
      timestamp: new Date().toISOString(),
      serverUrl: harness.baseUrl,
      totalItems,
      endpoints: results,
      summary: {
        totalRawKb,
        totalGzipKb,
        totalBrotliKb,
        overallCompressionRatio: +((1 - totalGzipKb / (totalRawKb || 1)) * 100).toFixed(1),
        averageLatencyMs,
      },
      passed: allPassed,
    };

    const outPath = path.join(reportsDir, "api-payloads.json");
    fs.writeFileSync(outPath, JSON.stringify(report, null, 2), "utf-8");

    // Also copy SQLite database to reports if available for inspect-sqlite-health
    if (harness.dataDir) {
      const srcDb = path.join(harness.dataDir, "tracker.db");
      const destDb = path.join(reportsDir, "tracker.db");
      if (fs.existsSync(srcDb)) {
        fs.copyFileSync(srcDb, destDb);
      }
    }

    console.log(`\n✨ [API Payloads] Summary: Raw: ${totalRawKb} KB -> Gzip: ${totalGzipKb} KB (Avg latency: ${averageLatencyMs} ms)`);
    return report;
  } finally {
    if (shouldStopHarness) {
      await harness.stop().catch(() => {});
    }
  }
}

if (process.argv[1] && fileURLToPath(import.meta.url) === path.resolve(process.argv[1])) {
  measureApiPayloads()
    .then((r) => {
      if (!r.passed) process.exitCode = 1;
    })
    .catch((err) => {
      console.error("❌ API Payload measurement failed:", err);
      process.exitCode = 1;
    });
}
