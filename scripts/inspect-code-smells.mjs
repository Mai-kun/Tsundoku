#!/usr/bin/env node
/**
 * scripts/inspect-code-smells.mjs
 * Bi-directional micro-optimization inspector for C# (.NET 10 / EF Core) and Svelte 5 / TypeScript.
 * Finds suboptimal performance patterns, generates actionable diff suggestions, and supports --fix.
 */

import fs from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const rootDir = path.resolve(__dirname, "..");
const reportsDir = path.join(rootDir, "reports");

const isFix = process.argv.includes("--fix");

if (!fs.existsSync(reportsDir)) {
  fs.mkdirSync(reportsDir, { recursive: true });
}

function walkDir(dir, extensions) {
  const results = [];
  if (!fs.existsSync(dir)) return results;
  const entries = fs.readdirSync(dir, { withFileTypes: true });
  for (const entry of entries) {
    if (entry.name === "bin" || entry.name === "obj" || entry.name === "node_modules" || entry.name === ".git") {
      continue;
    }
    const fullPath = path.join(dir, entry.name);
    if (entry.isDirectory()) {
      results.push(...walkDir(fullPath, extensions));
    } else if (extensions.some(ext => entry.name.endsWith(ext))) {
      results.push(fullPath);
    }
  }
  return results;
}

function makeUnifiedDiff(oldCode, newCode) {
  const oldLines = oldCode.trim().split("\n");
  const newLines = newCode.trim().split("\n");
  const diffLines = [];
  for (const line of oldLines) {
    diffLines.push(`- ${line}`);
  }
  for (const line of newLines) {
    diffLines.push(`+ ${line}`);
  }
  return diffLines.join("\n");
}

function getClassBodyAt(content, index) {
  const before = content.slice(0, index);
  const classMatches = [...before.matchAll(/(?:public|internal|private)?\s*(?:sealed\s+)?class\s+(\w+)[^{]*\{/gs)];
  if (classMatches.length === 0) return null;
  const lastMatch = classMatches[classMatches.length - 1];
  const afterHeader = content.slice(lastMatch.index + lastMatch[0].length);
  let depth = 1;
  let end = afterHeader.length;
  for (let i = 0; i < afterHeader.length; i++) {
    if (afterHeader[i] === "{") depth++;
    else if (afterHeader[i] === "}") {
      depth--;
      if (depth === 0) {
        end = i;
        break;
      }
    }
  }
  return {
    className: lastMatch[1],
    body: afterHeader.slice(0, end)
  };
}

const findings = [];
const seenKeys = new Set();
let totalFixed = 0;

function addFinding(f) {
  const key = `${f.file}:${f.line}:${f.ruleId}`;
  if (seenKeys.has(key)) return;
  seenKeys.add(key);
  findings.push(f);
}

// ==========================================
// 1. C# BACKEND INSPECTOR (.NET 10 / EF Core)
// ==========================================
const csDirs = [
  path.join(rootDir, "MediaTracker.Server/Features"),
  path.join(rootDir, "MediaTracker.Server/Domain"),
  path.join(rootDir, "MediaTracker.Server/Infrastructure"),
];

const csFiles = csDirs.flatMap(d => walkDir(d, [".cs"]));

for (const filePath of csFiles) {
  let content = fs.readFileSync(filePath, "utf-8");
  const relPath = path.relative(rootDir, filePath);
  let fileModified = false;
  const lines = content.split("\n");

  // ----------------------------------------------------
  // RULE 1: EF-NoTracking
  // ----------------------------------------------------
  const efQueryRegex = /db\.([A-Z]\w+)([\s\S]*?)\.(ToListAsync|FirstOrDefaultAsync|SingleOrDefaultAsync|ToArrayAsync)\s*\(/g;
  let efMatch;
  while ((efMatch = efQueryRegex.exec(content)) !== null) {
    const entitySet = efMatch[1];
    const chain = efMatch[2];
    const terminalMethod = efMatch[3];
    const matchIndex = efMatch.index;

    // Skip if already has AsNoTracking or is an update operation
    if (chain.includes(".AsNoTracking()") || chain.includes(".ExecuteUpdateAsync")) {
      continue;
    }

    // Determine the enclosing class scope
    const classInfo = getClassBodyAt(content, matchIndex);
    if (!classInfo) continue;

    // If the class contains SaveChangesAsync or AutoRefreshRunner, tracking is required
    if (
      classInfo.body.includes("SaveChangesAsync") ||
      classInfo.body.includes("AutoRefreshRunner")
    ) {
      continue;
    }

    const lineNum = content.slice(0, matchIndex).split("\n").length;
    const currentCodeLines = lines.slice(Math.max(0, lineNum - 1), Math.min(lines.length, lineNum + 4)).join("\n");
    
    let replacement;
    let suggestedCode;
    if (chain.startsWith("\n")) {
      const indentMatch = chain.match(/^\n(\s*)/);
      const indent = indentMatch ? indentMatch[1] : "            ";
      replacement = `db.${entitySet}\n${indent}.AsNoTracking()`;
      suggestedCode = currentCodeLines.replace(`db.${entitySet}\n`, `db.${entitySet}\n${indent}.AsNoTracking()\n`);
    } else {
      replacement = `db.${entitySet}.AsNoTracking()`;
      suggestedCode = currentCodeLines.replace(`db.${entitySet}`, `db.${entitySet}.AsNoTracking()`);
    }

    const finding = {
      file: relPath,
      line: lineNum,
      ruleId: "EF-NoTracking",
      severity: "warning",
      title: "Отсутствует .AsNoTracking() в read-only запросе EF Core",
      description: `Запрос к 'db.${entitySet}' завершается терминальным '${terminalMethod}()' в классе '${classInfo.className}' без SaveChangesAsync. Включение .AsNoTracking() устраняет затраты на Change Tracker и аллокацию снимков сущностей.`,
      currentCode: currentCodeLines.trim(),
      suggestedCode: suggestedCode.trim(),
      diff: makeUnifiedDiff(currentCodeLines.trim(), suggestedCode.trim()),
      fixed: false,
    };

    if (isFix) {
      content = content.slice(0, matchIndex) + replacement + content.slice(matchIndex + `db.${entitySet}`.length);
      finding.fixed = true;
      fileModified = true;
      totalFixed++;
    }

    addFinding(finding);
  }

  // Check un-tracked tables inside .Join(db.<EntitySet>...
  const joinQueryRegex = /\.Join\(\s*db\.([A-Z]\w+)\s*\.Where\(/g;
  let joinMatch;
  while ((joinMatch = joinQueryRegex.exec(content)) !== null) {
    const entitySet = joinMatch[1];
    const matchIndex = joinMatch.index;
    const lineNum = content.slice(0, matchIndex).split("\n").length;
    const oldCode = `.Join(db.${entitySet}.Where(`;
    const newCode = `.Join(db.${entitySet}.AsNoTracking().Where(`;

    const finding = {
      file: relPath,
      line: lineNum,
      ruleId: "EF-NoTracking",
      severity: "warning",
      title: `Отсутствует .AsNoTracking() для joined таблицы db.${entitySet}`,
      description: `Присоединение таблицы db.${entitySet} в read-only запросе без .AsNoTracking() приводит к отслеживанию строк в контексте.`,
      currentCode: oldCode,
      suggestedCode: newCode,
      diff: makeUnifiedDiff(oldCode, newCode),
      fixed: false,
    };

    if (isFix) {
      content = content.replace(oldCode, newCode);
      finding.fixed = true;
      fileModified = true;
      totalFixed++;
    }
    addFinding(finding);
  }

  // ----------------------------------------------------
  // RULE 2: LINQ-Optimizations
  // ----------------------------------------------------
  const whereCountRegex = /\.Where\s*\(([^()]+(?:\([^()]*\)[^()]*)*)\)\s*\.Count\s*\(\s*\)/g;
  let wcMatch;
  while ((wcMatch = whereCountRegex.exec(content)) !== null) {
    const lineNum = content.slice(0, wcMatch.index).split("\n").length;
    const pred = wcMatch[1].trim();
    const oldCode = wcMatch[0];
    const newCode = `.Count(${pred})`;
    const finding = {
      file: relPath,
      line: lineNum,
      ruleId: "LINQ-Optimizations",
      severity: "warning",
      title: "Неоптимальная цепочка LINQ: .Where(...).Count()",
      description: "Фильтрация .Where(...) перед вызовом .Count() создает промежуточный итератор. Используйте перегрузку .Count(predicate).",
      currentCode: oldCode,
      suggestedCode: newCode,
      diff: makeUnifiedDiff(oldCode, newCode),
      fixed: false,
    };
    if (isFix) {
      content = content.replace(oldCode, newCode);
      finding.fixed = true;
      fileModified = true;
      totalFixed++;
    }
    addFinding(finding);
  }

  const whereFirstRegex = /\.Where\s*\(([^()]+(?:\([^()]*\)[^()]*)*)\)\s*\.FirstOrDefault\s*\(\s*\)/g;
  let wfMatch;
  while ((wfMatch = whereFirstRegex.exec(content)) !== null) {
    const lineNum = content.slice(0, wfMatch.index).split("\n").length;
    const pred = wfMatch[1].trim();
    const oldCode = wfMatch[0];
    const newCode = `.FirstOrDefault(${pred})`;
    const finding = {
      file: relPath,
      line: lineNum,
      ruleId: "LINQ-Optimizations",
      severity: "warning",
      title: "Неоптимальная цепочка LINQ: .Where(...).FirstOrDefault()",
      description: "Вызов .Where(...) перед .FirstOrDefault() создает лишнюю обертку. Используйте перегрузку .FirstOrDefault(predicate).",
      currentCode: oldCode,
      suggestedCode: newCode,
      diff: makeUnifiedDiff(oldCode, newCode),
      fixed: false,
    };
    if (isFix) {
      content = content.replace(oldCode, newCode);
      finding.fixed = true;
      fileModified = true;
      totalFixed++;
    }
    addFinding(finding);
  }

  const whereFirstAsyncRegex = /\.Where\s*\(([^()]+(?:\([^()]*\)[^()]*)*)\)\s*\.FirstOrDefaultAsync\s*\(([^()]*)\)/g;
  let wfaMatch;
  while ((wfaMatch = whereFirstAsyncRegex.exec(content)) !== null) {
    const lineNum = content.slice(0, wfaMatch.index).split("\n").length;
    const pred = wfaMatch[1].trim();
    const arg = wfaMatch[2].trim();
    const oldCode = wfaMatch[0];
    const newCode = arg ? `.FirstOrDefaultAsync(${pred}, ${arg})` : `.FirstOrDefaultAsync(${pred})`;
    const finding = {
      file: relPath,
      line: lineNum,
      ruleId: "LINQ-Optimizations",
      severity: "warning",
      title: "Неоптимальная цепочка LINQ: .Where(...).FirstOrDefaultAsync()",
      description: "Вызов .Where(...) перед .FirstOrDefaultAsync() создает лишний LINQ-узел. Используйте перегрузку .FirstOrDefaultAsync(predicate, ct).",
      currentCode: oldCode,
      suggestedCode: newCode,
      diff: makeUnifiedDiff(oldCode, newCode),
      fixed: false,
    };
    if (isFix) {
      content = content.replace(oldCode, newCode);
      finding.fixed = true;
      fileModified = true;
      totalFixed++;
    }
    addFinding(finding);
  }

  const whereAnyRegex = /\.Where\s*\(([^()]+(?:\([^()]*\)[^()]*)*)\)\s*\.Any\s*\(\s*\)/g;
  let waMatch;
  while ((waMatch = whereAnyRegex.exec(content)) !== null) {
    const lineNum = content.slice(0, waMatch.index).split("\n").length;
    const pred = waMatch[1].trim();
    const oldCode = waMatch[0];
    const newCode = `.Any(${pred})`;
    const finding = {
      file: relPath,
      line: lineNum,
      ruleId: "LINQ-Optimizations",
      severity: "warning",
      title: "Неоптимальная цепочка LINQ: .Where(...).Any()",
      description: "Вызов .Where(...) перед .Any() создает промежуточный энумератор. Используйте перегрузку .Any(predicate).",
      currentCode: oldCode,
      suggestedCode: newCode,
      diff: makeUnifiedDiff(oldCode, newCode),
      fixed: false,
    };
    if (isFix) {
      content = content.replace(oldCode, newCode);
      finding.fixed = true;
      fileModified = true;
      totalFixed++;
    }
    addFinding(finding);
  }

  const countZeroRegex = /(\b[\w.]+)\.Count\(\)\s*==\s*0/g;
  let czMatch;
  while ((czMatch = countZeroRegex.exec(content)) !== null) {
    const lineNum = content.slice(0, czMatch.index).split("\n").length;
    const target = czMatch[1];
    const oldCode = czMatch[0];
    const newCode = `!${target}.Any()`;
    const finding = {
      file: relPath,
      line: lineNum,
      ruleId: "LINQ-Optimizations",
      severity: "warning",
      title: "Замена .Count() == 0 на !.Any()",
      description: "Вызов .Count() для проверки на пустоту производит полный обход последовательности O(N), тогда как .Any() завершается на первом элементе O(1).",
      currentCode: oldCode,
      suggestedCode: newCode,
      diff: makeUnifiedDiff(oldCode, newCode),
      fixed: false,
    };
    if (isFix) {
      content = content.replace(oldCode, newCode);
      finding.fixed = true;
      fileModified = true;
      totalFixed++;
    }
    addFinding(finding);
  }

  const countGtZeroRegex = /(\b[\w.]+)\.Count\(\)\s*>\s*0/g;
  let cgtMatch;
  while ((cgtMatch = countGtZeroRegex.exec(content)) !== null) {
    const lineNum = content.slice(0, cgtMatch.index).split("\n").length;
    const target = cgtMatch[1];
    const oldCode = cgtMatch[0];
    const newCode = `${target}.Any()`;
    const finding = {
      file: relPath,
      line: lineNum,
      ruleId: "LINQ-Optimizations",
      severity: "warning",
      title: "Замена .Count() > 0 на .Any()",
      description: "Вызов .Count() для проверки наличия элементов требует полного обхода коллекции O(N), тогда как .Any() завершается на первом элементе O(1).",
      currentCode: oldCode,
      suggestedCode: newCode,
      diff: makeUnifiedDiff(oldCode, newCode),
      fixed: false,
    };
    if (isFix) {
      content = content.replace(oldCode, newCode);
      finding.fixed = true;
      fileModified = true;
      totalFixed++;
    }
    addFinding(finding);
  }

  // ----------------------------------------------------
  // RULE 3: Generated-Regex
  // ----------------------------------------------------
  const regexInstantiationPattern = /(?:private|public|protected|internal)?\s*(?:static\s+)?(?:readonly\s+)?Regex\s+(\w+)\s*=\s*new\s*\(([^;]+)\);/g;
  let regMatch;
  while ((regMatch = regexInstantiationPattern.exec(content)) !== null) {
    const lineNum = content.slice(0, regMatch.index).split("\n").length;
    const name = regMatch[1];
    const args = regMatch[2].trim();
    const oldCode = regMatch[0];
    const suggestedMethod = `[GeneratedRegex(${args})]\n    private static partial Regex ${name}();`;

    addFinding({
      file: relPath,
      line: lineNum,
      ruleId: "Generated-Regex",
      severity: "warning",
      title: `Использование new Regex вместо [GeneratedRegex] для '${name}'`,
      description: "Создание экземпляров Regex во время выполнения требует динамической компиляции и увеличивает время старта и аллокации. В .NET 10 используйте генератор исходного кода [GeneratedRegex].",
      currentCode: oldCode,
      suggestedCode: suggestedMethod,
      diff: makeUnifiedDiff(oldCode, suggestedMethod),
      fixed: false,
    });
  }

  // ----------------------------------------------------
  // RULE 4: Span-Allocations
  // ----------------------------------------------------
  for (let i = 0; i < lines.length; i++) {
    const line = lines[i];
    if (/\b(for|foreach|while)\s*\(/.test(line) || /ParseYear|Tokens/i.test(line)) {
      const loopEnd = Math.min(lines.length, i + 15);
      for (let j = i; j < loopEnd; j++) {
        const loopLine = lines[j];
        if (/\.Split\s*\(/.test(loopLine) && !loopLine.includes("MemoryExtensions")) {
          let suggestedCode;
          if (loopLine.includes("Split('-')")) {
            suggestedCode = loopLine.replace(/int\.TryParse\([^.]+\.Split\('-'\)\[0\][^)]*\)/, "SpanParserExtensions.ParseYearFromDateString(value)");
          } else {
            suggestedCode = `// ReadOnlySpan<char> / MemoryExtensions.Split\n${loopLine.trim()}`;
          }
          addFinding({
            file: relPath,
            line: j + 1,
            ruleId: "Span-Allocations",
            severity: "info",
            title: "Аллокация массива через string.Split внутри цикла / парсера",
            description: "Вызов string.Split приводит к созданию строковых массивов в куче. Рассмотрите MemoryExtensions.Split, SpanParserExtensions или ReadOnlySpan<char>.",
            currentCode: loopLine.trim(),
            suggestedCode: suggestedCode.trim(),
            diff: makeUnifiedDiff(loopLine.trim(), suggestedCode.trim()),
            fixed: false,
          });
          break;
        }
      }
    }
  }

  if (fileModified) {
    fs.writeFileSync(filePath, content, "utf-8");
  }
}

// ==========================================
// 2. FRONTEND INSPECTOR (TypeScript / Svelte 5)
// ==========================================
const uiSrcDir = path.join(rootDir, "mediatracker-ui/src");
const uiFiles = walkDir(uiSrcDir, [".svelte", ".ts"]);

for (const filePath of uiFiles) {
  const content = fs.readFileSync(filePath, "utf-8");
  const relPath = path.relative(rootDir, filePath);
  const lines = content.split("\n");

  // RULE 5: Svelte-Uncached-Regex
  if (filePath.endsWith(".svelte")) {
    const scriptRegex = /<script(?![^>]*\bmodule\b)[^>]*>([\s\S]*?)<\/script>/gi;
    let sMatch;
    while ((sMatch = scriptRegex.exec(content)) !== null) {
      const scriptBody = sMatch[1];
      const scriptStartIndex = sMatch.index;
      const scriptLines = scriptBody.split("\n");

      for (let i = 0; i < scriptLines.length; i++) {
        const line = scriptLines[i];
        if (/^\s*(?:import|\/\/|\/\*|\*)/.test(line)) continue;

        const regexLiteralMatch = line.match(/(?<!\/)\/([^\/\n\r]+)\/([gimsuy]*)\s*\.(?:test|exec|match|replace)\s*\(/);
        if (regexLiteralMatch) {
          const lineNum = content.slice(0, scriptStartIndex).split("\n").length + i;
          const matchedRegex = `/${regexLiteralMatch[1]}/${regexLiteralMatch[2]}`;
          addFinding({
            file: relPath,
            line: lineNum,
            ruleId: "Svelte-Uncached-Regex",
            severity: "warning",
            title: `Некешированное регулярное выражение ${matchedRegex} в теле компонента`,
            description: "Литерал регулярного выражения внутри <script> пересоздается при каждом ререндере компонента. Вынесите его в <script module> или файл утилит.",
            currentCode: line.trim(),
            suggestedCode: `<script module>\n  const CACHED_REGEX = ${matchedRegex};\n</script>\n// В теле компонента:\n${line.trim().replace(matchedRegex, "CACHED_REGEX")}`,
            diff: makeUnifiedDiff(line.trim(), `// В <script module>: const CACHED_REGEX = ${matchedRegex};\n${line.trim().replace(matchedRegex, "CACHED_REGEX")}`),
            fixed: false,
          });
        }
      }
    }
  }

  // RULE 6: Svelte-Collection-StateRaw
  const entityCollectionPattern = /let\s+(\w+)\s*=\s*\$state<((?:MediaItem|ExternalMedia|CustomListSummary|SourceInfo|HistoryEvent|RecommendationItem|GameAchievementItem|RelatedEntry|CustomFolderItem)[^>]*)>\s*\(\s*\[\]\s*\)/g;
  let rawMatch;
  while ((rawMatch = entityCollectionPattern.exec(content)) !== null) {
    const lineNum = content.slice(0, rawMatch.index).split("\n").length;
    const varName = rawMatch[1];
    const typeName = rawMatch[2];
    const oldCode = rawMatch[0];
    const newCode = `let ${varName} = $state.raw<${typeName}>([]);`;

    addFinding({
      file: relPath,
      line: lineNum,
      ruleId: "Svelte-Collection-StateRaw",
      severity: "warning",
      title: `Использование глубокого $state вместо $state.raw для коллекции '${varName}'`,
      description: `Переменная '${varName}' хранит массив сущностей API ('${typeName}'). Использование $state создает реактивные Proxy для каждого элемента и поля, что приводит к оверхеду памяти. Рекомендуется $state.raw.`,
      currentCode: oldCode,
      suggestedCode: newCode,
      diff: makeUnifiedDiff(oldCode, newCode),
      fixed: false,
    });
  }

  // RULE 7: Heavy-Event-Debounce
  if (filePath.endsWith(".svelte")) {
    for (let i = 0; i < lines.length; i++) {
      const line = lines[i];
      if (/(?:oninput|onscroll)\s*=\s*\{([^}]+)\}/.test(line)) {
        const handlerMatch = line.match(/(?:oninput|onscroll)\s*=\s*\{([^}]+)\}/);
        const handlerName = handlerMatch ? handlerMatch[1].trim() : "handler";
        if (/search|query|filter|scroll/i.test(handlerName) && !line.includes("debounce")) {
          addFinding({
            file: relPath,
            line: i + 1,
            ruleId: "Heavy-Event-Debounce",
            severity: "info",
            title: `Событие ввода/скролла без debounce: ${handlerName}`,
            description: `Обработчик '${handlerName}' вызывается на каждый тик события. Убедитесь, что сетевые запросы или тяжелые фильтрации защищены debounce (например, progressDebounce или setTimeout).`,
            currentCode: line.trim(),
            suggestedCode: line.trim().replace(handlerName, `debounce(${handlerName}, 300)`),
            diff: makeUnifiedDiff(line.trim(), line.trim().replace(handlerName, `debounce(${handlerName}, 300)`)),
            fixed: false,
          });
        }
      }
    }
  }

  // RULE 8: Layout-Thrashing-Pattern (144 Hz frame budget = 6.94 ms)
  if (filePath.endsWith(".svelte") || filePath.endsWith(".ts")) {
    const baseName = path.basename(filePath);
    const ignoreList = ["virtualGrid.ts", "PopoverMenu.svelte"];
    if (!ignoreList.includes(baseName)) {
      const readRe = /\.getBoundingClientRect\s*\(|\.(?:scrollTop|offsetHeight|offsetWidth|clientHeight|clientWidth|scrollHeight|scrollWidth)\b/;
      const writeRe = /\.\s*style\s*\.|\.setAttribute\s*\(\s*['"]style['"]\s*,|\.scrollTop\s*=|style\s*=/;
      const deferRe = /requestAnimationFrame|\$effect|setTimeout|ResizeObserver|\$effect\.pre|\$effect\.snapshot/;

      // Split content into top-level function bodies (rough brace scan).
      let depth = 0;
      let fnStart = -1;
      let inFn = false;
      for (let i = 0; i < lines.length; i++) {
        const line = lines[i];
        const open = (line.match(/\{/g) || []).length;
        const close = (line.match(/\}/g) || []).length;
        if (!inFn) {
          // Detect a function-like declaration start.
          if (/(?:function\s+\w+|const\s+\w+\s*[:=]\s*(?:\([^)]*\)\s*)?=>|async\s+function\s+\w+|[\w$]+\s*[:=]\s*(?:\([^)]*\)\s*)?=>)\s*$|\{/.test(line) && /function|=>/.test(line)) {
            fnStart = i;
            inFn = true;
          }
        }
        depth += open - close;
        if (inFn && depth === 0) {
          const body = lines.slice(fnStart, i + 1).join("\n");
          const bodyStartLine = fnStart + 1;
          fnStart = -1;
          inFn = false;
          depth = 0;

          // Deferred callbacks never force a synchronous reflow.
          if (deferRe.test(body)) continue;

          const reads = body.match(readRe);
          const writes = body.match(writeRe);
          if (reads && writes) {
            // Order check: first read index must precede first write index.
            let firstRead = Infinity;
            let firstWrite = Infinity;
            for (const r of reads) {
              const idx = body.indexOf(r);
              if (idx >= 0 && idx < firstRead) firstRead = idx;
            }
            for (const w of writes) {
              const idx = body.indexOf(w);
              if (idx >= 0 && idx < firstWrite) firstWrite = idx;
            }
            if (firstRead < firstWrite) {
              addFinding({
                file: relPath,
                line: bodyStartLine,
                ruleId: "Layout-Thrashing-Pattern",
                severity: "warning",
                title: "Forced synchronous reflow (layout thrashing) внутри функции",
                description: `Функция читает свойства макета (${reads.join(", ")}) и сразу же записывает стили (${writes.join(", ")}) в том же синхронном потоке. При 144 Hz (бюджет кадра 6.94 ms) принудительный пересчет макета ломает плавность скролла. Разделяйте фазы чтения и записи, оберните запись в requestAnimationFrame или вынесите в $effect.`,
                currentCode: body.trim().slice(0, 200),
                suggestedCode: `// Чтение макета в одной фазе, запись стилей — в requestAnimationFrame / $effect:\nrequestAnimationFrame(() => {\n  // ...запись стилей...\n});`,
                diff: makeUnifiedDiff(body.trim().slice(0, 200), "//(requestAnimationFrame around writes)"),
                fixed: false,
              });
            }
          }
        }
      }
    }
  }
}

// ==========================================
// 3. WRITE REPORTS AND DISPLAY CONSOLE SUMMARY
// ==========================================
const outputPath = path.join(reportsDir, "code-smells.json");
fs.writeFileSync(outputPath, JSON.stringify(findings, null, 2), "utf-8");

console.log("\n========================================================");
console.log(`🔎 Умный инспектор микрооптимизаций Tsundoku (C# & Svelte 5)`);
console.log(`Режим: ${isFix ? "🛠️ AUTO-FIX (--fix)" : "🔍 CHECK-ONLY"}`);
console.log("========================================================\n");

const ruleStats = {};
for (const f of findings) {
  if (!ruleStats[f.ruleId]) {
    ruleStats[f.ruleId] = { total: 0, fixed: 0, severity: f.severity };
  }
  ruleStats[f.ruleId].total++;
  if (f.fixed) ruleStats[f.ruleId].fixed++;
}

console.log("📊 Сводка по проверенным правилам:");
const summaryTable = Object.entries(ruleStats).map(([rule, stat]) => ({
  "Правило": rule,
  "Уровень": stat.severity === "warning" ? "⚠️ Warning" : "💡 Info",
  "Найдено": stat.total,
  "Исправлено (--fix)": stat.fixed,
  "Требует внимания": stat.total - stat.fixed,
}));
console.table(summaryTable);

const totalFilesScanned = csFiles.length + uiFiles.length;
const totalFindings = findings.length;
const totalRemaining = totalFindings - totalFixed;

console.log(`\n📁 Всего проверено файлов: ${totalFilesScanned} (C#: ${csFiles.length}, Svelte/TS: ${uiFiles.length})`);
console.log(`✨ Автоматически исправлено (--fix): ${totalFixed}`);
console.log(`💡 Рекомендаций в отчете: ${totalRemaining}`);
console.log(`📄 Полный отчет сохранен в: reports/code-smells.json\n`);
