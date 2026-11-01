import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

/**
 * Palette inspector: keeps the Obsidian-dark UI matte.
 *
 * Scans every .svelte and .css file under mediatracker-ui/src for
 *  1. raw "acid" hex colors — very bright, near-pure channel values that glare
 *     on the #0d0f14 canvas (e.g. #00e054, #ea580c, #02a9ff). Raw hexes are
 *     allowed only in the theme definition (src/app/tokens.css); everywhere
 *     else they must go through a token or a muted color-mix()/alpha blend;
 *  2. unshielded bright Tailwind fills (bg-orange-500 and friends) without an
 *     opacity modifier or an interaction prefix — reported as warnings since
 *     semantic status colors occasionally justify a solid fill.
 *
 * Muted accents live in src/app/tokens.css; new import-provider colors should
 * be low-saturation or alpha-blended so they read as matte surfaces.
 */

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const SRC_DIR = path.resolve(__dirname, '../../src');
/** Theme definition files own the raw palette; raw acid hexes are allowed there. */
const THEME_FILES = new Set([
  path.resolve(SRC_DIR, 'app/tokens.css'),
  path.resolve(SRC_DIR, 'app/app.css'),
]);
/** The import palette is this task's scope: acid hexes here fail the check. */
const ERROR_DIR = path.resolve(SRC_DIR, 'features/import-media');

interface Finding {
  file: string;
  line: number;
  found: string;
  reason: string;
  hint: string;
  /** Errors fail the check; warnings only print. */
  severity: 'error' | 'warning';
}

function walk(dir: string): string[] {
  if (!fs.existsSync(dir)) return [];
  const entries = fs.readdirSync(dir, { withFileTypes: true });
  const files: string[] = [];
  for (const entry of entries) {
    const full = path.join(dir, entry.name);
    if (entry.isDirectory()) {
      if (['node_modules', '__snapshots__', '__fixtures__'].includes(entry.name)) continue;
      files.push(...walk(full));
    } else if (entry.name.endsWith('.svelte') || entry.name.endsWith('.css')) {
      files.push(full);
    }
  }
  return files;
}

/** Bright channel spread: max >= 200 and (max - min) >= 150 reads as neon on graphite. */
function isAcidHex(hex: string): boolean {
  let r: number, g: number, b: number;
  if (hex.length === 3) {
    r = parseInt(hex[0] + hex[0], 16);
    g = parseInt(hex[1] + hex[1], 16);
    b = parseInt(hex[2] + hex[2], 16);
  } else {
    r = parseInt(hex.slice(0, 2), 16);
    g = parseInt(hex.slice(2, 4), 16);
    b = parseInt(hex.slice(4, 6), 16);
  }
  const max = Math.max(r, g, b);
  const min = Math.min(r, g, b);
  return max >= 200 && max - min >= 150;
}

const HEX_RE = /#([0-9a-fA-F]{6}|[0-9a-fA-F]{3})\b/g;

/** Fills only: text/border tints at low alpha are fine on dark backgrounds. */
const BRIGHT_FILL_RE =
  /(?:^|\s|'|")bg-(red|orange|amber|yellow|lime|green|emerald|pink|fuchsia|rose)-(?:400|500|600)\b(?!\/)/g;

function scanFile(relFile: string, content: string, isThemeFile: boolean, isErrorScope: boolean): Finding[] {
  const findings: Finding[] = [];
  const lines = content.split('\n');
  lines.forEach((line, idx) => {
    for (const match of line.matchAll(HEX_RE)) {
      const hex = match[1];
      if (!isThemeFile && isAcidHex(hex)) {
        findings.push({
          file: relFile,
          line: idx + 1,
          found: `#${hex}`,
          reason: 'acid hex outside the theme definition',
          hint: 'use a theme token (--color-accent / --color-import-*-accent) or a muted color-mix()',
          severity: isErrorScope ? 'error' : 'warning',
        });
      }
    }
    for (const match of line.matchAll(BRIGHT_FILL_RE)) {
      const cls = match[0].trim();
      findings.push({
        file: relFile,
        line: idx + 1,
        found: cls,
        reason: 'unshielded bright Tailwind fill',
        hint: 'use a token-driven fill or add transparency (e.g. bg-emerald-500/10) / a hover: prefix',
        severity: 'warning',
      });
    }
  });
  return findings;
}

const files = walk(SRC_DIR);
const findings: Finding[] = [];
for (const file of files) {
  const relFile = path.relative(process.cwd(), file);
  const content = fs.readFileSync(file, 'utf8');
  findings.push(
    ...scanFile(
      relFile,
      content,
      THEME_FILES.has(path.resolve(file)),
      file.startsWith(ERROR_DIR),
    ),
  );
}

const errors = findings.filter((f) => f.severity === 'error');
const warnings = findings.filter((f) => f.severity === 'warning');

for (const f of errors) {
  console.error(`❌ [checkMutedColors] ${f.file}:${f.line} — ${f.found} (${f.reason})`);
  console.error(`   → ${f.hint}`);
}
for (const f of warnings) {
  console.warn(`⚠️  [checkMutedColors] ${f.file}:${f.line} — ${f.found} (${f.reason})`);
  console.warn(`   → ${f.hint}`);
}

if (errors.length === 0) {
  console.log(
    `✅ [checkMutedColors] ${files.length} files scanned — palette is matte` +
      (warnings.length > 0 ? ` (${warnings.length} soft warning(s) above).` : '.'),
  );
} else {
  console.error(`❌ [checkMutedColors] ${errors.length} error(s), ${warnings.length} warning(s).`);
  process.exit(1);
}
