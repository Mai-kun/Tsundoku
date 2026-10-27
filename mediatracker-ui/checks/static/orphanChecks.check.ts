import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const ROOT_DIR = path.resolve(__dirname, '../../../');
const UI_DIR = path.resolve(ROOT_DIR, 'mediatracker-ui');
const CHECKS_DIR = path.resolve(UI_DIR, 'checks');
const SCRIPTS_DIR = path.resolve(ROOT_DIR, 'scripts');
const REPORTS_DIR = path.resolve(ROOT_DIR, 'reports');

function walk(dir: string, filter: (f: string) => boolean): string[] {
  if (!fs.existsSync(dir)) return [];
  const entries = fs.readdirSync(dir, { withFileTypes: true });
  const files: string[] = [];
  for (const entry of entries) {
    const full = path.join(dir, entry.name);
    if (entry.isDirectory()) {
      if (['__fixtures__', '__snapshots__', 'backstop_data', 'node_modules'].includes(entry.name)) continue;
      files.push(...walk(full, filter));
    } else if (filter(entry.name)) {
      files.push(full);
    }
  }
  return files;
}

// 1. Поиск всех проверяемых файлов на диске
const discoveredFiles: string[] = [
  ...walk(CHECKS_DIR, f => f.endsWith('.check.ts') || f.endsWith('.runner.ts') || f === 'testServerHarness.ts' || f === 'backstopOnReady.js'),
  ...walk(SCRIPTS_DIR, f => f.endsWith('.mjs')),
  ...walk(path.resolve(UI_DIR, 'src'), f => f.endsWith('.test.ts'))
];

// 2. Сбор текстового контекста контура запуска
const executionSources: string[] = [
  path.resolve(ROOT_DIR, 'Taskfile.yml'),
  path.resolve(ROOT_DIR, 'package.json'),
  path.resolve(UI_DIR, 'package.json'),
  path.resolve(SCRIPTS_DIR, 'audit-runner.mjs'),
  path.resolve(CHECKS_DIR, 'audit/browserSuite.runner.ts'),
  path.resolve(UI_DIR, 'vitest.config.ts')
];

let pipelineContext = '';
for (const src of executionSources) {
  if (fs.existsSync(src)) {
    pipelineContext += fs.readFileSync(src, 'utf8') + '\n';
  }
}

// 3. Проверка регистрации каждого файла
const orphans: string[] = [];
const registered: string[] = [];

for (const file of discoveredFiles) {
  const baseName = path.basename(file);
  const relPath = path.relative(ROOT_DIR, file).replace(/\\/g, '/');

  // Файл зарегистрирован, если его имя или относительный путь явно упоминается в файлах запуска,
  // либо он является юнит-тестом Vitest (src/**/__tests__/*.test.ts)
  const isReferenced = pipelineContext.includes(baseName) || pipelineContext.includes(relPath);
  const isVitestTest = file.includes('__tests__') && file.endsWith('.test.ts');
  const isImportedModule = baseName === 'testServerHarness.ts' || baseName === 'backstopOnReady.js';

  if (isReferenced || isVitestTest || isImportedModule) {
    registered.push(relPath);
  } else {
    orphans.push(relPath);
  }
}

// 4. Сохранение отчета
if (!fs.existsSync(REPORTS_DIR)) fs.mkdirSync(REPORTS_DIR, { recursive: true });
fs.writeFileSync(path.resolve(REPORTS_DIR, 'orphan-checks.json'), JSON.stringify({
  totalDiscovered: discoveredFiles.length,
  totalRegistered: registered.length,
  orphans,
  status: orphans.length === 0 ? 'PASS' : 'WARN'
}, null, 2));

console.log(`[orphanChecks] Scanned ${discoveredFiles.length} check files & scripts across repo.`);
if (orphans.length > 0) {
  console.warn(`⚠️ [orphanChecks] Found ${orphans.length} unreferenced check file(s) on disk:`);
  orphans.forEach(o => console.warn(`   -> ${o}`));
  if (process.argv.includes('--strict')) process.exit(1);
} else {
  console.log(`✅ [orphanChecks] 100% of check scripts and test files (${registered.length}/${discoveredFiles.length}) are actively registered in the execution pipeline.`);
}
