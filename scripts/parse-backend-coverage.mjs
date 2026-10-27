#!/usr/bin/env node
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const rootDir = path.resolve(__dirname, '..');
const reportsDir = path.join(rootDir, 'reports');

function findLatestCoverageFile(baseDir) {
  if (!fs.existsSync(baseDir)) return null;

  const results = [];
  function walk(currentDir) {
    const entries = fs.readdirSync(currentDir, { withFileTypes: true });
    for (const entry of entries) {
      const fullPath = path.join(currentDir, entry.name);
      if (entry.isDirectory()) {
        walk(fullPath);
      } else if (entry.name === 'coverage.cobertura.xml') {
        const stats = fs.statSync(fullPath);
        results.push({ path: fullPath, mtime: stats.mtimeMs });
      }
    }
  }

  walk(baseDir);
  if (results.length === 0) return null;
  results.sort((a, b) => b.mtime - a.mtime);
  return results[0].path;
}

export function parseBackendCoverage(coverageXmlPath) {
  const content = fs.readFileSync(coverageXmlPath, 'utf8');

  // Parse root attributes
  const coverageTagMatch = content.match(/<coverage\s+([^>]+)>/i);
  if (!coverageTagMatch) {
    throw new Error('Invalid Cobertura XML: <coverage> root not found');
  }

  const attrsStr = coverageTagMatch[1];
  const getAttr = (name) => {
    const m = attrsStr.match(new RegExp(`${name}="([^"]+)"`, 'i'));
    return m ? m[1] : null;
  };

  const lineRate = parseFloat(getAttr('line-rate') || '0');
  const branchRate = parseFloat(getAttr('branch-rate') || '0');
  const linesCovered = parseInt(getAttr('lines-covered') || '0', 10);
  const linesValid = parseInt(getAttr('lines-valid') || '0', 10);
  const branchesCovered = parseInt(getAttr('branches-covered') || '0', 10);
  const branchesValid = parseInt(getAttr('branches-valid') || '0', 10);

  // Group line hits by file
  // Match each <class ... filename="..."> ... </class>
  const classRegex = /<class\s+[^>]*filename="([^"]+)"[^>]*>([\s\S]*?)<\/class>/gi;
  const fileLines = new Map(); // filename -> Map(lineNumber -> hits)

  let classMatch;
  while ((classMatch = classRegex.exec(content)) !== null) {
    const filename = classMatch[1];
    if (filename.startsWith('obj/') || filename.startsWith('obj\\')) {
      continue;
    }

    if (!fileLines.has(filename)) {
      fileLines.set(filename, new Map());
    }
    const lineMap = fileLines.get(filename);

    const classBody = classMatch[2];
    const lineRegex = /<line\s+number="(\d+)"\s+hits="(\d+)"/gi;
    let lineMatch;
    while ((lineMatch = lineRegex.exec(classBody)) !== null) {
      const lineNum = parseInt(lineMatch[1], 10);
      const hits = parseInt(lineMatch[2], 10);
      const currentHits = lineMap.get(lineNum) || 0;
      lineMap.set(lineNum, Math.max(currentHits, hits));
    }
  }

  const filesSummary = [];
  const filesBelow80 = [];

  for (const [filename, lineMap] of fileLines.entries()) {
    const total = lineMap.size;
    if (total === 0) continue;

    let covered = 0;
    for (const hits of lineMap.values()) {
      if (hits > 0) covered++;
    }

    const pct = Math.round((covered / total) * 1000) / 10;
    const fileStat = {
      filename,
      lineCoveragePercent: pct,
      linesCovered: covered,
      linesValid: total,
    };

    filesSummary.push(fileStat);
    if (pct < 80.0) {
      filesBelow80.push(fileStat);
    }
  }

  filesBelow80.sort((a, b) => a.lineCoveragePercent - b.lineCoveragePercent);

  return {
    lineRate,
    lineCoveragePercent: Math.round(lineRate * 1000) / 10,
    branchRate,
    branchCoveragePercent: Math.round(branchRate * 1000) / 10,
    linesCovered,
    linesValid,
    branchesCovered,
    branchesValid,
    totalFiles: filesSummary.length,
    filesBelow80Count: filesBelow80.length,
    filesBelow80,
    generatedAt: new Date().toISOString(),
  };
}

if (process.argv[1] && import.meta.url.endsWith(path.basename(process.argv[1]))) {
  const coverageDir = path.join(reportsDir, 'coverage');
  const xmlPath = findLatestCoverageFile(coverageDir);

  if (!xmlPath) {
    console.error(`[parse-backend-coverage] No coverage.cobertura.xml found under ${coverageDir}`);
    process.exit(1);
  }

  const summary = parseBackendCoverage(xmlPath);
  const outPath = path.join(reportsDir, 'backend-coverage.json');
  fs.mkdirSync(path.dirname(outPath), { recursive: true });
  fs.writeFileSync(outPath, JSON.stringify(summary, null, 2), 'utf8');

  console.log(`[parse-backend-coverage] Coverage parsed from: ${xmlPath}`);
  console.log(`[parse-backend-coverage] Line coverage: ${summary.lineCoveragePercent}% (${summary.linesCovered}/${summary.linesValid})`);
  console.log(`[parse-backend-coverage] Branch coverage: ${summary.branchCoveragePercent}% (${summary.branchesCovered}/${summary.branchesValid})`);
  console.log(`[parse-backend-coverage] Files below 80%: ${summary.filesBelow80Count} / ${summary.totalFiles}`);
  console.log(`[parse-backend-coverage] Saved to: ${outPath}`);
}
