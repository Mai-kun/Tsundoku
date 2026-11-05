#!/usr/bin/env node
/**
 * scripts/smoke-test-artifact.mjs
 *
 * Post-build artifact smoke test: boots the REAL published binary headless, verifies
 * the API, renders the frontend in headless Chromium (Playwright), scans the fresh
 * session log for [ERR]/[FTL] markers and checks the process shuts down cleanly.
 * Designed for CI (release.yml) but runnable locally:
 *
 *   node scripts/smoke-test-artifact.mjs publish/linux-x64/Tsundoku
 *   node scripts/smoke-test-artifact.mjs dist/Tsundoku-Portable/Tsundoku
 *
 * Exit codes: 0 = all checks passed, 1 = any check failed.
 */

import { spawn } from "node:child_process";
import fs from "node:fs";
import fsp from "node:fs/promises";
import os from "node:os";
import path from "node:path";
import process from "node:process";
import { fileURLToPath } from "node:url";

const __dirname = path.dirname(fileURLToPath(import.meta.url));

const args = process.argv.slice(2).filter((a) => a !== "--skip-browser");
const skipBrowser = process.argv.includes("--skip-browser");

if (args.length === 0) {
  console.error("Usage: node scripts/smoke-test-artifact.mjs <path-to-binary> [--skip-browser]");
  process.exit(1);
}

const BINARY = resolveBinary(args[0]);
const PORT = Number(process.env.SMOKE_PORT || 5055);
const BASE_URL = `http://127.0.0.1:${PORT}`;
const BOOT_TIMEOUT_MS = 15_000; // NativeAOT binaries start fast, but CI runners can stall
const API_ENDPOINTS = [
  "/api/settings/storage",
  "/api/goals",
  "/api/media",
  "/api/settings/offline-databases",
];

let serverProcess = null;
let dataDir = null;
let failures = 0;

const ok = (label) => console.log(`   ✅ ${label}`);
const fail = (label, details) => {
  failures += 1;
  console.error(`   ❌ ${label}`);
  if (details) console.error(indent(details));
};

function indent(text) {
  return String(text)
    .split("\n")
    .map((l) => `      ${l}`)
    .join("\n");
}

/** On Windows the CI step passes "Tsundoku" without the extension. */
function resolveBinary(rawPath) {
  if (fs.existsSync(rawPath)) return path.resolve(rawPath);
  const withExe = `${rawPath}.exe`;
  if (process.platform === "win32" && fs.existsSync(withExe)) {
    return path.resolve(withExe);
  }
  console.error(`Binary not found: ${rawPath}`);
  process.exit(1);
}

function sleep(ms) {
  return new Promise((resolve) => setTimeout(resolve, ms));
}

function collectStream(stream, buffer, maxLines = 40) {
  stream.setEncoding("utf8");
  stream.on("data", (chunk) => {
    buffer.push(...chunk.split(/\r?\n/).filter(Boolean));
    while (buffer.length > maxLines) buffer.shift();
  });
}

async function waitForServer() {
  const deadline = Date.now() + BOOT_TIMEOUT_MS;
  let lastError = "";

  while (Date.now() < deadline) {
    if (serverProcess.exitCode !== null || serverProcess.signalCode !== null) {
      throw new Error(
        `Server exited early (code=${serverProcess.exitCode}, signal=${serverProcess.signalCode}).\n` +
          `stdout tail:\n${serverOutput.stdout.join("\n")}\n` +
          `stderr tail:\n${serverOutput.stderr.join("\n")}`
      );
    }

    try {
      const res = await fetch(`${BASE_URL}/`, { signal: AbortSignal.timeout(1000) });
      // Any HTTP response means Kestrel is listening; 404/500 on "/" is fine at this stage.
      void res.body?.cancel();
      return res.status;
    } catch (err) {
      lastError = err.message;
      await sleep(250);
    }
  }

  throw new Error(`Server did not become reachable on ${BASE_URL} within 15s (last error: ${lastError})`);
}

async function checkApiEndpoints() {
  console.log("🔎 API endpoints:");
  for (const endpoint of API_ENDPOINTS) {
    try {
      const res = await fetch(`${BASE_URL}${endpoint}`, { signal: AbortSignal.timeout(10_000) });
      void res.body?.cancel();
      if (res.status === 200) {
        ok(`GET ${endpoint} -> 200`);
      } else {
        fail(`GET ${endpoint} -> ${res.status} (expected 200)`);
      }
    } catch (err) {
      fail(`GET ${endpoint} request failed`, err.message);
    }
  }
}

async function checkFrontend() {
  if (skipBrowser) {
    console.log("⏭️  Browser phase skipped (--skip-browser)");
    return;
  }

  console.log("🔎 Frontend (headless Chromium):");
  let playwright;
  try {
    playwright = await import("playwright");
  } catch (err) {
    fail("Playwright module unavailable", `${err.message}\nInstall it with: npm install && npx playwright install chromium`);
    return;
  }

  let browser;
  try {
    browser = await playwright.chromium.launch({ headless: true });
  } catch (err) {
    fail("Chromium launch failed", `${err.message}\nInstall the browser with: npx playwright install chromium`);
    return;
  }

  try {
    const page = await browser.newPage();

    const pageErrors = [];
    page.on("pageerror", (err) => pageErrors.push(String(err)));
    page.on("console", (msg) => {
      if (msg.type() !== "error") return;
      const text = msg.text();
      // Net failures (e.g. missing favicon) are expected noise; JS errors are not.
      if (/ReferenceError|Uncaught|TypeError|SyntaxError/i.test(text)) {
        pageErrors.push(`console.${msg.type()}: ${text}`);
      }
    });

    await page.goto(BASE_URL, { waitUntil: "domcontentloaded", timeout: 15_000 });

    // The boot spinner styles #app:empty; once Vue mounts, the selector stops matching.
    try {
      await page.waitForFunction(
        () => {
          const app = document.querySelector("#app");
          return app !== null && app.children.length > 0;
        },
        { timeout: 4000 }
      );
      ok("#app mounted (no hanging boot spinner)");
    } catch {
      fail("#app:empty spinner never went away — likely a white screen / JS crash");
    }

    const hasMarkup = await page.evaluate(
      () => Boolean(document.querySelector("header")) && Boolean(document.querySelector("main"))
    );
    if (hasMarkup) {
      ok("App markup present (header + main)");
    } else {
      fail("Expected app markup missing (header or main not found)");
    }

    if (pageErrors.length > 0) {
      fail(`Browser JS errors (${pageErrors.length})`, pageErrors.slice(0, 10).join("\n"));
    } else {
      ok("No uncaught JS errors in console");
    }
  } finally {
    await browser.close();
  }
}

function findNewestSessionLog(root) {
  const matches = [];
  const walk = (dir) => {
    let entries;
    try {
      entries = fs.readdirSync(dir, { withFileTypes: true });
    } catch {
      return;
    }
    for (const entry of entries) {
      const full = path.join(dir, entry.name);
      if (entry.isDirectory()) walk(full);
      else if (entry.isFile() && /^session_.*\.log$/.test(entry.name)) matches.push(full);
    }
  };
  walk(root);
  if (matches.length === 0) return null;
  return matches.sort((a, b) => fs.statSync(b).mtimeMs - fs.statSync(a).mtimeMs)[0];
}

async function checkServerLog() {
  console.log("🔎 Server log scan:");
  const logPath = dataDir ? findNewestSessionLog(dataDir) : null;
  if (!logPath) {
    fail("No session_*.log found under the smoke data dir");
    return;
  }

  const content = await fsp.readFile(logPath, "utf8");
  const errorLines = content
    .split("\n")
    .filter((line) => /\[(ERR|FTL)\]/.test(line))
    // The browser may probe favicon.ico before the SPA provides it; that 404 is expected.
    .filter((line) => !/favicon/i.test(line));

  if (errorLines.length === 0) {
    ok(`Clean boot log: ${path.basename(logPath)} (${content.split("\n").length} lines)`);
  } else {
    fail(`Log contains ${errorLines.length} [ERR]/[FTL] line(s)`, errorLines.slice(0, 15).join("\n"));
  }
}

async function shutdownGracefully() {
  console.log("🔎 Graceful shutdown:");
  if (serverProcess.exitCode !== null || serverProcess.signalCode !== null) {
    fail("Server already exited before shutdown request");
    return;
  }

  try {
    const res = await fetch(`${BASE_URL}/api/system/shutdown`, { method: "POST", signal: AbortSignal.timeout(5000) });
    void res.body?.cancel();
    if (res.status >= 200 && res.status < 300) {
      ok(`POST /api/system/shutdown -> ${res.status}`);
    } else {
      fail(`POST /api/system/shutdown -> ${res.status} (expected 2xx)`);
    }
  } catch (err) {
    fail("POST /api/system/shutdown request failed", err.message);
  }

  const exited = await new Promise((resolve) => {
    const timer = setTimeout(() => resolve(false), 3000);
    serverProcess.once("exit", () => {
      clearTimeout(timer);
      resolve(true);
    });
  });

  if (exited) {
    ok("Process exited within 3s");
  } else {
    fail("Process did not exit within 3s after shutdown request");
  }
}

function killServer() {
  if (!serverProcess || serverProcess.exitCode !== null || serverProcess.signalCode !== null) return;
  if (process.platform === "win32") {
    spawn("taskkill", ["/PID", String(serverProcess.pid), "/F", "/T"], { stdio: "ignore" });
  } else {
    serverProcess.kill("SIGKILL");
  }
}

async function main() {
  console.log(`🚀 Artifact smoke test: ${BINARY}`);
  if (!fs.existsSync(BINARY)) {
    console.error(`Binary not found: ${BINARY}`);
    process.exit(1);
  }

  dataDir = await fsp.mkdtemp(path.join(os.tmpdir(), "tsundoku-smoke-"));
  console.log(`   Data dir: ${dataDir}`);

  const startTime = Date.now();
  serverProcess = spawn(BINARY, ["--headless", "--port", String(PORT), "--data-dir", dataDir], {
    cwd: path.dirname(BINARY),
    stdio: ["ignore", "pipe", "pipe"],
  });
  const serverOutput = { stdout: [], stderr: [] };
  collectStream(serverProcess.stdout, serverOutput.stdout);
  collectStream(serverProcess.stderr, serverOutput.stderr);

  try {
    let rootStatus;
    try {
      rootStatus = await waitForServer();
      ok(`Server reachable on ${BASE_URL} (root / -> ${rootStatus}) in ${Date.now() - startTime}ms`);
    } catch (err) {
      fail("Server boot", err.message);
      return;
    }

    await checkApiEndpoints();
    await checkFrontend();
    await checkServerLog();
    await shutdownGracefully();
  } finally {
    killServer();
    const logPath = dataDir ? findNewestSessionLog(dataDir) : null;
    if (failures > 0 && serverOutput.stdout.length + serverOutput.stderr.length > 0) {
      console.error("\n--- server output tail ---");
      console.error(indent([...serverOutput.stdout, ...serverOutput.stderr].slice(-30).join("\n")));
    }
    if (failures > 0 && logPath) {
      console.error(`   (session log kept for inspection: ${logPath})`);
    }
    await fsp.rm(dataDir, { recursive: true, force: true }).catch(() => {});
  }

  if (failures > 0) {
    console.error(`\n💥 Artifact smoke test FAILED: ${failures} check(s) failed.`);
    process.exit(1);
  }

  console.log("\n✅ All artifact smoke checks passed!");
}

process.on("exit", () => killServer());
main().catch((err) => {
  console.error("Smoke test crashed:", err);
  killServer();
  process.exit(1);
});
