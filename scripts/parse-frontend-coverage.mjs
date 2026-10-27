#!/usr/bin/env node
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const rootDir = path.resolve(__dirname, '..');
const reportsDir = path.join(rootDir, 'reports');

export function parseFrontendCoverage(summaryJsonPath) {
  if (!fs.existsSync(summaryJsonPath)) {
    throw new Error(`Frontend coverage summary not found at: ${summaryJsonPath}`);
  }

  const raw = JSON.parse(fs.readFileSync(summaryJsonPath, 'utf8'));
  const total = raw.total || {};

  const files = [];
  const filesBelow80 = [];
  const filesAbove80 = [];

  for (const [filePath, stats] of Object.entries(raw)) {
    if (filePath === 'total') continue;

    // Normalize path to relative from mediatracker-ui/
    let normalized = filePath.replace(/\\/g, '/');
    const marker = 'mediatracker-ui/';
    const markerIdx = normalized.indexOf(marker);
    if (markerIdx !== -1) {
      normalized = normalized.substring(markerIdx + marker.length);
    }

    const linePct = stats.lines?.pct ?? 0;
    const branchPct = stats.branches?.pct ?? 0;
    const funcPct = stats.functions?.pct ?? 0;

    const fileStat = {
      filename: normalized,
      lineCoveragePercent: linePct,
      branchCoveragePercent: branchPct,
      functionsCoveragePercent: funcPct,
      linesCovered: stats.lines?.covered ?? 0,
      linesValid: stats.lines?.total ?? 0,
    };

    files.push(fileStat);
    if (linePct < 80.0) {
      filesBelow80.push(fileStat);
    } else {
      filesAbove80.push(fileStat);
    }
  }

  filesBelow80.sort((a, b) => a.lineCoveragePercent - b.lineCoveragePercent);
  filesAbove80.sort((a, b) => b.lineCoveragePercent - a.lineCoveragePercent);

  return {
    lineCoveragePercent: total.lines?.pct ?? 0,
    branchCoveragePercent: total.branches?.pct ?? 0,
    functionsCoveragePercent: total.functions?.pct ?? 0,
    statementsCoveragePercent: total.statements?.pct ?? 0,
    linesCovered: total.lines?.covered ?? 0,
    linesValid: total.lines?.total ?? 0,
    branchesCovered: total.branches?.covered ?? 0,
    branchesValid: total.branches?.total ?? 0,
    functionsCovered: total.functions?.covered ?? 0,
    functionsValid: total.functions?.total ?? 0,
    totalFiles: files.length,
    filesAbove80Count: filesAbove80.length,
    filesBelow80Count: filesBelow80.length,
    filesAbove80,
    filesBelow80,
    generatedAt: new Date().toISOString(),
  };
}

if (process.argv[1] && import.meta.url.endsWith(path.basename(process.argv[1]))) {
  const summaryPath = path.join(reportsDir, 'coverage', 'frontend', 'coverage-summary.json');
  const summary = parseFrontendCoverage(summaryPath);
  const outPath = path.join(reportsDir, 'frontend-coverage.json');
  fs.mkdirSync(path.dirname(outPath), { recursive: true });
  fs.writeFileSync(outPath, JSON.stringify(summary, null, 2), 'utf8');

  console.log(`[parse-frontend-coverage] Coverage parsed from: ${summaryPath}`);
  console.log(`[parse-frontend-coverage] Line coverage: ${summary.lineCoveragePercent}% (${summary.linesCovered}/${summary.linesValid})`);
  console.log(`[parse-frontend-coverage] Branch coverage: ${summary.branchCoveragePercent}% (${summary.branchesCovered}/${summary.branchesValid})`);
  console.log(`[parse-frontend-coverage] Functions coverage: ${summary.functionsCoveragePercent}% (${summary.functionsCovered}/${summary.functionsValid})`);
  console.log(`[parse-frontend-coverage] Files >= 80%: ${summary.filesAbove80Count} / ${summary.totalFiles}`);
  console.log(`[parse-frontend-coverage] Files < 80%: ${summary.filesBelow80Count} / ${summary.totalFiles}`);
  console.log(`[parse-frontend-coverage] Saved to: ${outPath}`);
}
