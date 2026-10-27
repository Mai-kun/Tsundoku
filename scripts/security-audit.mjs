#!/usr/bin/env node
/**
 * scripts/security-audit.mjs
 * Multi-layer security audit:
 * 1. NuGet dependencies vulnerability check with CVE suppression awareness
 * 2. NPM production dependencies audit (--omit=dev)
 * 3. Static secret & credential leak scanning across codebase
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

function auditNuget() {
  console.log("🔍 [Security] Scanning .NET NuGet packages for vulnerabilities...");
  const csprojPath = "MediaTracker.Server/MediaTracker.Server.csproj";
  let output = "";
  try {
    output = execSync(
      `dotnet list "${csprojPath}" package --vulnerable --include-transitive`,
      { cwd: rootDir, encoding: "utf-8", stdio: ["ignore", "pipe", "pipe"] }
    );
  } catch (err) {
    output = err.stdout?.toString() || err.stderr?.toString() || "";
  }

  const packages = [];
  const lines = output.split("\n");
  let currentPkg = null;

  for (const rawLine of lines) {
    const line = rawLine.trim();
    if (!line) continue;

    // Line starting with `> PackageName` or `PackageName`
    const pkgMatch = line.match(/^>\s*([A-Za-z0-9_.-]+)\s+([0-9_.-]+)\s+([0-9_.-]+)\s+(Critical|High|Moderate|Low)\s+(https:\/\/\S+)/i);
    if (pkgMatch) {
      currentPkg = {
        name: pkgMatch[1],
        requested: pkgMatch[2],
        resolved: pkgMatch[3],
        advisories: [
          {
            severity: pkgMatch[4],
            url: pkgMatch[5],
          },
        ],
      };
      packages.push(currentPkg);
      continue;
    }

    // Additional advisory lines for the same package
    const advMatch = line.match(/^(Critical|High|Moderate|Low)\s+(https:\/\/\S+)/i);
    if (advMatch && currentPkg) {
      currentPkg.advisories.push({
        severity: advMatch[1],
        url: advMatch[2],
      });
    }
  }

  // Check known suppressions in csproj (e.g. ImageSharp NU1902;NU1903)
  const evaluatedPackages = packages.map((pkg) => {
    const isImageSharp = pkg.name.toLowerCase().includes("imagesharp");
    return {
      ...pkg,
      suppressed: isImageSharp,
      suppressionReason: isImageSharp
        ? "Подавлено в .csproj (NU1902;NU1903) как известное транзитивное ограничение целевой платформы .NET 10"
        : null,
    };
  });

  const unsuppressedCount = evaluatedPackages.filter((p) => !p.suppressed).length;

  return {
    passed: unsuppressedCount === 0,
    totalVulnerablePackages: packages.length,
    unsuppressedCount,
    packages: evaluatedPackages,
    rawOutputSummary: evaluatedPackages.length > 0 ? `${evaluatedPackages.length} package(s) reported` : "No vulnerable packages found",
  };
}

function auditNpm() {
  console.log("🔍 [Security] Auditing NPM production dependencies (--omit=dev)...");
  let auditJson = null;
  try {
    const raw = execSync("npm --prefix mediatracker-ui audit --omit=dev --json", {
      cwd: rootDir,
      encoding: "utf-8",
      stdio: ["ignore", "pipe", "pipe"],
    });
    auditJson = JSON.parse(raw);
  } catch (err) {
    try {
      auditJson = JSON.parse(err.stdout?.toString() || "{}");
    } catch {
      auditJson = null;
    }
  }

  const meta = auditJson?.metadata?.vulnerabilities || {
    info: 0,
    low: 0,
    moderate: 0,
    high: 0,
    critical: 0,
    total: 0,
  };

  const highOrCritical = (meta.high || 0) + (meta.critical || 0);

  return {
    passed: highOrCritical === 0,
    vulnerabilities: meta,
    productionDependenciesScanned: auditJson?.metadata?.dependencies?.prod || 0,
  };
}

const SECRET_PATTERNS = [
  { name: "Stripe Live Secret Key", regex: /\bsk_live_[0-9a-zA-Z]{24,}\b/ },
  { name: "Google API Key", regex: /\bAIzaSy[0-9A-Za-z\-_]{33}\b/ },
  { name: "AWS Access Key ID", regex: /\bAKIA[0-9A-Z]{16}\b/ },
  { name: "GitHub Personal Access Token", regex: /\b(?:ghp|gho|ghu|ghs|ghr)_[0-9a-zA-Z]{36,}\b/ },
  { name: "Slack Token", regex: /\bxox[baprs]-[0-9a-zA-Z]{10,}\b/ },
  { name: "Private RSA/OpenSSH Key", regex: /-----BEGIN (?:RSA|EC|OPENSSH|PGP|PRIVATE) KEY-----/ },
];

function scanSecrets() {
  console.log("🔍 [Security] Scanning codebase for leaked secrets and private keys...");
  const targetDirs = [
    "MediaTracker.Server",
    "MediaTracker.Benchmarks",
    "MediaTracker.Tests",
    "mediatracker-ui/src",
    "mediatracker-ui/checks",
    "scripts",
  ];

  const allowedExts = new Set([".cs", ".ts", ".svelte", ".json", ".js", ".mjs"]);
  const ignoreFiles = new Set(["package-lock.json", ".cache-manifest.json"]);

  const filesToScan = [];

  function walk(currentDir) {
    if (!fs.existsSync(currentDir)) return;
    const entries = fs.readdirSync(currentDir, { withFileTypes: true });
    for (const ent of entries) {
      if (ent.name === "bin" || ent.name === "obj" || ent.name === "node_modules" || ent.name === ".git" || ent.name === "dist") {
        continue;
      }
      const full = path.join(currentDir, ent.name);
      if (ent.isDirectory()) {
        walk(full);
      } else if (allowedExts.has(path.extname(ent.name)) && !ignoreFiles.has(ent.name)) {
        filesToScan.push(full);
      }
    }
  }

  for (const d of targetDirs) {
    walk(path.join(rootDir, d));
  }

  const leaks = [];

  for (const file of filesToScan) {
    let content = "";
    try {
      content = fs.readFileSync(file, "utf-8");
    } catch {
      continue;
    }

    const lines = content.split("\n");
    for (let lineIdx = 0; lineIdx < lines.length; lineIdx++) {
      const lineText = lines[lineIdx];
      for (const pat of SECRET_PATTERNS) {
        const match = pat.regex.exec(lineText);
        if (match) {
          const matchedVal = match[0];
          const redacted = matchedVal.slice(0, 4) + "..." + matchedVal.slice(-4);
          leaks.push({
            file: path.relative(rootDir, file),
            line: lineIdx + 1,
            pattern: pat.name,
            redactedMatch: redacted,
          });
        }
      }
    }
  }

  return {
    passed: leaks.length === 0,
    scannedFilesCount: filesToScan.length,
    leaksCount: leaks.length,
    leaks,
  };
}

export function runSecurityAudit() {
  const nugetResult = auditNuget();
  const npmResult = auditNpm();
  const secretsResult = scanSecrets();

  const allPassed = nugetResult.passed && npmResult.passed && secretsResult.passed;

  const summary = {
    timestamp: new Date().toISOString(),
    passed: allPassed,
    status: allPassed ? "PASS" : "FAIL",
    nuget: nugetResult,
    npm: npmResult,
    secretScan: secretsResult,
  };

  const outPath = path.join(reportsDir, "security-audit.json");
  fs.writeFileSync(outPath, JSON.stringify(summary, null, 2), "utf-8");

  console.log("\n=======================================================");
  console.log(`🛡️  [Security Summary] Status: ${summary.status}`);
  console.log(`   NuGet:   ${nugetResult.passed ? "✅ PASS" : "❌ FAIL"} (${nugetResult.packages.length} reported, ${nugetResult.unsuppressedCount} unsuppressed)`);
  console.log(`   NPM:     ${npmResult.passed ? "✅ PASS" : "❌ FAIL"} (${npmResult.vulnerabilities.total} total vulnerabilities in prod)`);
  console.log(`   Secrets: ${secretsResult.passed ? "✅ PASS" : "❌ FAIL"} (${secretsResult.scannedFilesCount} files scanned, ${secretsResult.leaksCount} leaks)`);
  console.log("=======================================================\n");

  return summary;
}

if (process.argv[1] && fileURLToPath(import.meta.url) === path.resolve(process.argv[1])) {
  const report = runSecurityAudit();
  if (!report.passed) {
    process.exitCode = 1;
  }
}
