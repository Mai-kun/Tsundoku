import assert from "node:assert/strict";
import fs from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const srcDir = path.resolve(__dirname, "../src/views");

interface ExpectedBinding {
  file: string;
  variableName: string;
  pattern: RegExp;
}

const EXPECTED_RAW_BINDINGS: ExpectedBinding[] = [
  {
    file: "CategoryView.svelte",
    variableName: "allItems",
    pattern: /let\s+allItems\s*=\s*\$state\.raw\s*(?:<[^>]+>)?\s*\(/,
  },
  {
    file: "HomeView.svelte",
    variableName: "inProgress",
    pattern: /let\s+inProgress\s*=\s*\$state\.raw\s*(?:<[^>]+>)?\s*\(/,
  },
  {
    file: "HomeView.svelte",
    variableName: "upNext",
    pattern: /let\s+upNext\s*=\s*\$state\.raw\s*(?:<[^>]+>)?\s*\(/,
  },
  {
    file: "HomeView.svelte",
    variableName: "recentlyCompleted",
    pattern: /let\s+recentlyCompleted\s*=\s*\$state\.raw\s*(?:<[^>]+>)?\s*\(/,
  },
  {
    file: "HistoryView.svelte",
    variableName: "events",
    pattern: /let\s+events\s*=\s*\$state\.raw\s*(?:<[^>]+>)?\s*\(/,
  },
  {
    file: "HistoryView.svelte",
    variableName: "allItems",
    pattern: /let\s+allItems\s*=\s*\$state\.raw\s*(?:<[^>]+>)?\s*\(/,
  },
  {
    file: "ListsView.svelte",
    variableName: "lists",
    pattern: /let\s+lists\s*=\s*\$state\.raw\s*(?:<[^>]+>)?\s*\(/,
  },
];

console.log("[check:state-raw] Verifying $state.raw usage for primary media collections...");

for (const binding of EXPECTED_RAW_BINDINGS) {
  const filePath = path.join(srcDir, binding.file);
  assert(fs.existsSync(filePath), `File ${binding.file} must exist at ${filePath}`);
  const content = fs.readFileSync(filePath, "utf-8");

  const isRaw = binding.pattern.test(content);
  assert(
    isRaw,
    `[check:state-raw] In ${binding.file}, '${binding.variableName}' must be declared with $state.raw to prevent recursive proxy overhead.`,
  );
}

console.log(`[check:state-raw] All ${EXPECTED_RAW_BINDINGS.length} collection bindings verified successfully.`);
