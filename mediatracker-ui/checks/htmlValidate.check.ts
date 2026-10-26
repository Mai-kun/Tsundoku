import assert from "node:assert/strict";
import fs from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const srcDir = path.resolve(__dirname, "../src");
const reportsDir = path.resolve(__dirname, "../../reports");
const autoFix = process.argv.includes("--fix");

interface HtmlIssue {
  file: string;
  line: number;
  type: "missing-button-type" | "nested-interactive" | "duplicate-id";
  message: string;
  fixed?: boolean;
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
const issues: HtmlIssue[] = [];

for (const filePath of svelteFiles) {
  const relPath = path.relative(srcDir, filePath);
  let content = fs.readFileSync(filePath, "utf-8");
  let modified = false;

  const lines = content.split(/\r?\n/);

  // 1. Check duplicate static IDs
  const seenIds = new Map<string, number>();
  for (let i = 0; i < lines.length; i++) {
    const line = lines[i];
    const idMatches = [...line.matchAll(/\bid="([^"{}]+)"/g)];
    for (const match of idMatches) {
      const id = match[1];
      if (seenIds.has(id)) {
        issues.push({
          file: relPath,
          line: i + 1,
          type: "duplicate-id",
          message: `Duplicate static id="${id}" (first seen on line ${seenIds.get(id)})`,
        });
      } else {
        seenIds.set(id, i + 1);
      }
    }
  }

  // 2. Check <button> without type attribute and fix if requested
  const buttonRegex = /<button(?![^>]*\btype=)(\s|>)/g;
  if (buttonRegex.test(content)) {
    // Find line numbers for reporting
    for (let i = 0; i < lines.length; i++) {
      if (/<button(?![^>]*\btype=)(\s|>)/.test(lines[i])) {
        issues.push({
          file: relPath,
          line: i + 1,
          type: "missing-button-type",
          message: '<button> is missing explicit type attribute (expected type="button" or type="submit")',
          fixed: autoFix,
        });
      }
    }

    if (autoFix) {
      content = content.replace(/<button(?![^>]*\btype=)(\s|>)/g, '<button type="button"$1');
      modified = true;
    }
  }

  // 3. Strict nested interactive check (ensuring the parent button is not closed before the inner tag)
  const nestedButtonRegex = /<button\b[^>]*>(?:(?!<\/button\s*>)[\s\S])*?<button\b/gi;
  const nestedAnchorRegex = /<button\b[^>]*>(?:(?!<\/button\s*>)[\s\S])*?<a\b/gi;
  const buttonInsideAnchorRegex = /<a\b[^>]*>(?:(?!<\/a\s*>)[\s\S])*?<button\b/gi;

  let m: RegExpExecArray | null;
  while ((m = nestedButtonRegex.exec(content)) !== null) {
    const lineNo = content.slice(0, m.index).split("\n").length;
    issues.push({
      file: relPath,
      line: lineNo,
      type: "nested-interactive",
      message: "Forbidden nested <button> inside <button>",
    });
  }
  while ((m = nestedAnchorRegex.exec(content)) !== null) {
    const lineNo = content.slice(0, m.index).split("\n").length;
    issues.push({
      file: relPath,
      line: lineNo,
      type: "nested-interactive",
      message: "Forbidden nested <a> inside <button>",
    });
  }
  while ((m = buttonInsideAnchorRegex.exec(content)) !== null) {
    const lineNo = content.slice(0, m.index).split("\n").length;
    issues.push({
      file: relPath,
      line: lineNo,
      type: "nested-interactive",
      message: "Forbidden nested <button> inside <a>",
    });
  }

  if (modified) {
    fs.writeFileSync(filePath, content, "utf-8");
  }
}

if (!fs.existsSync(reportsDir)) {
  fs.mkdirSync(reportsDir, { recursive: true });
}

const reportPath = path.join(reportsDir, "html-validate.json");
const summary = {
  timestamp: new Date().toISOString(),
  totalFilesChecked: svelteFiles.length,
  totalIssues: issues.length,
  fixedIssues: issues.filter((i) => i.fixed).length,
  remainingIssues: issues.filter((i) => !i.fixed).length,
  issues,
};

fs.writeFileSync(reportPath, JSON.stringify(summary, null, 2), "utf-8");

console.log("\n🔍 [check:html] Template Structural Validation Report:");
console.log(`- Files scanned: ${svelteFiles.length}`);
console.log(`- Total issues found: ${issues.length}`);
console.log(`- Issues fixed: ${summary.fixedIssues}`);
console.log(`- Remaining issues: ${summary.remainingIssues}`);

if (issues.length > 0) {
  console.table(
    issues.map((iss) => ({
      File: `${iss.file}:${iss.line}`,
      Type: iss.type,
      Fixed: iss.fixed ? "YES" : "NO",
      Message: iss.message,
    })),
  );
}

if (!autoFix && summary.remainingIssues > 0) {
  assert.fail(
    `[check:html] Found ${summary.remainingIssues} structural HTML errors. Run with --fix or fix them manually.`,
  );
}

console.log("✅ [check:html] All Svelte template HTML structures are valid.");
