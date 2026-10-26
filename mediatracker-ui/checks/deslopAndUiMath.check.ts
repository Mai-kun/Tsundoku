import assert from "node:assert/strict";
import fs from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const srcDir = path.resolve(__dirname, "../src");
const reportsDir = path.resolve(__dirname, "../../reports");
const autoFix = process.argv.includes("--fix");

interface DeslopIssue {
  file: string;
  line: number;
  rule:
    | "no-transition-all"
    | "no-gradient-text"
    | "no-aggressive-scale"
    | "no-sluggish-interactive-transition";
  message: string;
  matchedText: string;
  fixed: boolean;
}

function walkSvelteFiles(dir: string): string[] {
  const results: string[] = [];
  const entries = fs.readdirSync(dir, { withFileTypes: true });
  for (const entry of entries) {
    const full = path.join(dir, entry.name);
    if (entry.isDirectory()) {
      results.push(...walkSvelteFiles(full));
    } else if (entry.isFile() && entry.name.endsWith(".svelte")) {
      results.push(full);
    }
  }
  return results;
}

const svelteFiles = walkSvelteFiles(srcDir);
const issues: DeslopIssue[] = [];
let totalFixedFiles = 0;

for (const filePath of svelteFiles) {
  const relPath = path.relative(srcDir, filePath);
  let content = fs.readFileSync(filePath, "utf-8");
  let modified = false;

  const lines = content.split(/\r?\n/);

  for (let i = 0; i < lines.length; i++) {
    const line = lines[i];
    const lineNo = i + 1;

    // 1. Check & Fix transition-all
    if (/\btransition-all\b/.test(line)) {
      issues.push({
        file: relPath,
        line: lineNo,
        rule: "no-transition-all",
        message: "Prohibited 'transition-all' triggers layout thrashing in WebView2",
        matchedText: "transition-all",
        fixed: autoFix,
      });

      if (autoFix) {
        // Smart replacement based on surrounding classes:
        // If it's a progress bar (width/h), use transition-[width] or transition-[height]
        // If it has scale/translate/rotate, use transition-transform
        // Otherwise use transition or transition-colors
        lines[i] = lines[i].replace(/\btransition-all\b/g, (match) => {
          if (/style=["'][^"']*\bwidth\b|w-\[|h-\[/.test(line)) {
            return "transition-[width]";
          }
          if (/scale-|translate-|rotate-/.test(line)) {
            return "transition-transform";
          }
          return "transition";
        });
        modified = true;
      }
    }

    // 2. Check Gradient Text (AI slop: bg-clip-text text-transparent)
    if (/bg-clip-text\s+text-transparent|text-transparent\s+bg-clip-text/.test(line)) {
      issues.push({
        file: relPath,
        line: lineNo,
        rule: "no-gradient-text",
        message: "Forbidden AI-slop gradient text (bg-clip-text text-transparent)",
        matchedText: "bg-clip-text text-transparent",
        fixed: autoFix,
      });

      if (autoFix) {
        lines[i] = lines[i]
          .replace(/\b(bg-clip-text\s+text-transparent|text-transparent\s+bg-clip-text)\b/g, "")
          .replace(/from-purple-\d+\s+(via-pink-\d+\s+)?to-[a-z]+-\d+/g, "");
        modified = true;
      }
    }

    // 3. Check Aggressive Hover Scale (hover:scale-110, hover:scale-125, group-hover:scale-110, etc.)
    if (/(?:hover|group-hover|focus):scale-(?:110|125|150)/.test(line)) {
      issues.push({
        file: relPath,
        line: lineNo,
        rule: "no-aggressive-scale",
        message: "Aggressive card/element zoom causes jarring motion (limit to hover:scale-[1.03])",
        matchedText: line.match(/(?:hover|group-hover|focus):scale-(?:110|125|150)/)?.[0] ?? "",
        fixed: autoFix,
      });

      if (autoFix) {
        lines[i] = lines[i].replace(
          /(hover|group-hover|focus):scale-(?:110|125|150)/g,
          "$1:scale-[1.03]",
        );
        modified = true;
      }
    }

    // 4. Check Sluggish interactive transitions (duration-500, duration-700 on interactive buttons)
    if (
      /<button\b|<a\b|class=["'][^"']*\b(?:btn|tab|tap)\b/.test(line) &&
      /\bduration-(?:500|700)\b/.test(line)
    ) {
      issues.push({
        file: relPath,
        line: lineNo,
        rule: "no-sluggish-interactive-transition",
        message: "Sluggish duration-500/700 on interactive control degrades responsiveness",
        matchedText: line.match(/\bduration-(?:500|700)\b/)?.[0] ?? "",
        fixed: autoFix,
      });

      if (autoFix) {
        lines[i] = lines[i].replace(/\bduration-(?:500|700)\b/g, "duration-200");
        modified = true;
      }
    }
  }

  if (modified) {
    fs.writeFileSync(filePath, lines.join("\n"), "utf-8");
    totalFixedFiles++;
  }
}

if (!fs.existsSync(reportsDir)) {
  fs.mkdirSync(reportsDir, { recursive: true });
}

const summary = {
  timestamp: new Date().toISOString(),
  totalFilesScanned: svelteFiles.length,
  totalIssuesFound: issues.length,
  issuesFixed: issues.filter((i) => i.fixed).length,
  remainingIssues: issues.filter((i) => !i.fixed).length,
  fixedFilesCount: totalFixedFiles,
  issues,
};

const summaryPath = path.join(reportsDir, "deslop-summary.json");
fs.writeFileSync(summaryPath, JSON.stringify(summary, null, 2), "utf-8");

console.log("\n🧹 [check:deslop] De-Slop & Refactoring UI Validation Report:");
console.log(`- Files scanned: ${svelteFiles.length}`);
console.log(`- Issues found: ${issues.length}`);
console.log(`- Issues fixed: ${summary.issuesFixed}`);
console.log(`- Remaining issues: ${summary.remainingIssues}`);
console.log(`- Files modified: ${totalFixedFiles}`);

if (issues.length > 0) {
  console.table(
    issues.map((i) => ({
      File: `${i.file}:${i.line}`,
      Rule: i.rule,
      Fixed: i.fixed ? "YES" : "NO",
      Match: i.matchedText,
    })),
  );
}

console.log(`\n📄 [check:deslop] Saved report to ${summaryPath}`);

if (!autoFix && summary.remainingIssues > 0) {
  assert.fail(
    `[check:deslop] Found ${summary.remainingIssues} UI slop violations. Run with --fix to clean automatically.`,
  );
}

console.log("✅ [check:deslop] UI code is 100% slop-free and optimized for WebView2 60 FPS.");
