#!/usr/bin/env node
/**
 * scripts/audit-animations.mjs
 *
 * Diagnostic (read-only) auditor of UI animations for the mediatracker-ui frontend.
 * Two levels:
 *   A) Static analysis of every Svelte component under src/:
 *      - 🔴 High priority: overlays (modals, popovers, selects, dropdowns, tooltips,
 *        accordions/collapsible sections) whose {#if} blocks render with neither a
 *        Svelte transition directive nor an animating CSS class.
 *      - 🟡 Medium priority: interactive controls (button / onclick elements / links)
 *        without any hover/click transition (Tailwind `transition-*`, `duration-*`,
 *        `animate-*`, inline `style="transition:..."` or a component <style> rule).
 *      - 🟢 Exceptions: virtual-scroll internals (media-grid / MediaCard), plain <input>s
 *        and purely technical wrappers are counted but never reported.
 *   B) With --runtime: boots the real app via checks/harness/testServerHarness.ts and
 *      Playwright, walks key routes (home, category, detail+tabs, settings, media editor),
 *      measures getComputedStyle(...).transitionDuration of every visible control and
 *      verifies that clicks which mutate the DOM also start at least one real CSS/Web
 *      animation (MutationObserver + transitionstart/animationstart + getAnimations polling).
 *
 * Output:
 *   - Console summary (grouped by priority).
 *   - mediatracker-ui/ANIMATION_AUDIT.md — human-readable report.
 *   - reports/animation-audit.json — machine-readable artifact.
 *
 * The script never modifies application code. Usage:
 *   node scripts/audit-animations.mjs            # static audit only
 *   node scripts/audit-animations.mjs --runtime  # static + live browser audit
 *   npm --prefix mediatracker-ui run audit:animations [-- --runtime]
 */

import fs from "node:fs";
import path from "node:path";
import { createRequire } from "node:module";
import { fileURLToPath, pathToFileURL } from "node:url";

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const ROOT_DIR = path.resolve(__dirname, "..");
const UI_DIR = path.join(ROOT_DIR, "mediatracker-ui");
const SRC_DIR = path.join(UI_DIR, "src");
const REPORTS_DIR = path.join(ROOT_DIR, "reports");
const MD_REPORT_PATH = path.join(UI_DIR, "ANIMATION_AUDIT.md");
const JSON_REPORT_PATH = path.join(REPORTS_DIR, "animation-audit.json");

const RUNTIME_FLAG = process.argv.includes("--runtime");

/* ------------------------------------------------------------------ */
/* Shared helpers                                                      */
/* ------------------------------------------------------------------ */

function walkDir(dir, filter) {
  const results = [];
  if (!fs.existsSync(dir)) return results;
  for (const entry of fs.readdirSync(dir, { withFileTypes: true })) {
    if (entry.name === "node_modules" || entry.name === "__tests__") continue;
    const full = path.join(dir, entry.name);
    if (entry.isDirectory()) results.push(...walkDir(full, filter));
    else if (filter(entry.name)) results.push(full);
  }
  return results;
}

function lineOf(content, index) {
  let line = 1;
  for (let i = 0; i < index && i < content.length; i++) {
    if (content[i] === "\n") line++;
  }
  return line;
}

function relFile(file) {
  return path.relative(UI_DIR, file).replace(/\\/g, "/");
}

/* ------------------------------------------------------------------ */
/* Part A — static analysis                                            */
/* ------------------------------------------------------------------ */

const OVERLAY_FILE_RE =
  /(Modal|Popover|Select|ContextMenu|Tooltip|Lightbox|Dropdown|Drawer|Sheet|Toast|Menu|Message|Prompt|Confirm)/i;

/** Tailwind / custom utility classes that actually animate something. */
const ANIMATING_CLASS_RE =
  /(^|[\s"'])(transition[\w-]*|duration-\d+|ease-\w+|animate-\w+|delay-\d+|view-fade|motion-safe:transition[\w-]*|motion-reduce:transition[\w-]*|hover:transition[\w-]*|active:transition[\w-]*)/;

/** State-changing variants: their presence means hover/active actually alters this element. */
const STATE_VARIANT_RE = /(?:hover|active|focus-visible|focus-within|group-hover):/;

/** State names that usually drive collapsible sections (accordions). */
const COLLAPSE_STATE_RE = /(expand|collaps)/i;

/** Files whose controls live inside the virtual scroller — green-zone exceptions. */
const VIRTUAL_ZONE_RE = /(media-grid|MediaCard|virtualGrid|VirtualGrid)/;

const knownAnimatedClasses = new Set();

function extractStyleBlock(content) {
  const match = content.match(/<style[^>]*>([\s\S]*?)<\/style>/);
  return match ? { body: match[1], start: match.index } : null;
}

/**
 * Classes whose component <style> rules carry a transition/animation declaration.
 * Used both to whitelist buttons and to decide whether an {#if} branch animates.
 */
function collectStyledAnimatedClasses(styleBody) {
  const found = new Set();
  for (const chunk of styleBody.split("}")) {
    const braceIdx = chunk.indexOf("{");
    if (braceIdx === -1) continue;
    const selector = chunk.slice(0, braceIdx);
    const ruleBody = chunk.slice(braceIdx + 1);
    if (!/(^|[;{\s])(transition|animation)\s*:|@keyframes/.test(ruleBody)) continue;
    for (const m of selector.matchAll(/\.([\w-]+)/g)) found.add(m[1]);
    for (const m of ruleBody.matchAll(/@keyframes\s+([\w-]+)/g)) found.add(m[1]);
  }
  return found;
}

function isAnimatingClass(cls, fileAnimatedClasses) {
  if (ANIMATING_CLASS_RE.test(cls)) return true;
  if (knownAnimatedClasses.has(cls)) return true;
  return fileAnimatedClasses.has(cls);
}

/** Svelte block scanner: finds {#if ...} ... {/if} extents with block-depth matching. */
function findIfBlocks(markup) {
  const blocks = [];
  const openRe = /\{#if\s/g;
  let openMatch;
  while ((openMatch = openRe.exec(markup)) !== null) {
    const start = openMatch.index;
    // Walk forward counting {# (opens any block, +1) and {/ (closes one, -1).
    // {:else}/{:then}/{:catch} are neutral, so they never participate.
    let depth = 1; // the opening {#if itself
    const tokenRe = /\{[#/]/g;
    tokenRe.lastIndex = openMatch.index + 1;
    let end = -1;
    let token;
    while ((token = tokenRe.exec(markup)) !== null) {
      depth += token[0] === "{#" ? 1 : -1;
      if (depth === 0) {
        end = token.index; // position of the matching {/if}
        break;
      }
    }
    if (end === -1) continue;
    const condEnd = markup.indexOf("}", openMatch.index);
    const cond = markup.slice(openMatch.index + 4, condEnd).trim();
    const body = markup.slice(condEnd + 1, end);
    blocks.push({ start, condEnd, end, cond, body });
  }
  // Dedupe nested {#if} blocks (keep the outermost that we matched with an extent).
  return blocks.filter(
    (b, i, arr) => arr.findIndex((o) => b.start >= o.start && b.start < o.end) === i,
  );
}

/** Strip <script> blocks and HTML comments from scanning range bookkeeping. */
function buildSkipRanges(content) {
  const ranges = [];
  for (const m of content.matchAll(/<script[^>]*>[\s\S]*?<\/script>/g)) {
    ranges.push([m.index, m.index + m[0].length]);
  }
  for (const m of content.matchAll(/<!--[\s\S]*?-->/g)) {
    ranges.push([m.index, m.index + m[0].length]);
  }
  return ranges;
}

function inRanges(index, ranges) {
  return ranges.some(([s, e]) => index >= s && index < e);
}

function extractAttr(attrs, name) {
  // Supports plain "..." / '...' quotes, Svelte backtick templates (class={`...`})
  // and ={expression} values with balanced nested braces (class={`… ${cond ? "a" : "b"}`}).
  const m = new RegExp(`\\b${name}\\s*=\\s*`).exec(attrs);
  if (!m) return "";
  const start = m.index + m[0].length;
  const q = attrs[start];
  if (q === '"' || q === "'" || q === "`") {
    const end = attrs.indexOf(q, start + 1);
    return end === -1 ? "" : attrs.slice(start + 1, end);
  }
  if (q === "{") {
    let depth = 0;
    for (let j = start; j < attrs.length; j++) {
      if (attrs[j] === "{") depth++;
      else if (attrs[j] === "}") {
        depth--;
        if (depth === 0) return attrs.slice(start + 1, j);
      }
    }
  }
  return "";
}

function buttonLabel(markupAfterTag, attrs, tagName) {
  const aria =
    extractAttr(attrs, "aria-label") || extractAttr(attrs, "title") || extractAttr(attrs, "name");
  if (aria) return aria.replace(/\s+/g, " ").trim().slice(0, 60);
  if (tagName === "button") {
    const closeMatch = markupAfterTag.match(/<\/button\s*>/);
    if (closeMatch) {
      const text = markupAfterTag
        .slice(0, closeMatch.index)
        .replace(/<[^>]*>/g, " ")
        // Keep i18n expression bodies as readable labels: {i18n.t.importModal.changeFile} → changeFile
        .replace(/\{([^}]*)\}/g, " $1 ")
        .replace(/i18n\.t\.[\w.]+\.?/g, (m) => m.replace("i18n.t.", "").replace(/\.$/, ""))
        .replace(/\s+/g, " ")
        .trim();
      if (text) return text.slice(0, 60);
    }
  }
  return "(без текста)";
}

/**
 * Finds the real `>` that closes an opening tag. A naive `[^>]*` breaks on Svelte
 * attribute expressions like onclick={() => (x = 1)} where `>` lives inside braces/quotes.
 */
function findOpenTagEnd(content, tagStart) {  let braceDepth = 0;
  let quote = null;
  for (let i = tagStart + 1; i < content.length; i++) {
    const ch = content[i];
    if (quote) {
      if (ch === quote && content[i - 1] !== "\\") quote = null;
      continue;
    }
    if (ch === '"' || ch === "'" || ch === "`") {
      quote = ch;
      continue;
    }
    if (ch === "{") braceDepth++;
    else if (ch === "}") braceDepth = Math.max(0, braceDepth - 1);
    else if (ch === ">" && braceDepth === 0) return i;
  }
  return -1;
}

/** Removes balanced Svelte {…} expressions (nested braces aware) from markup text. */
function stripSvelteExpressions(text) {
  let out = "";
  let depth = 0;
  for (const ch of text) {
    if (ch === "{") depth++;
    else if (ch === "}") {
      depth = Math.max(0, depth - 1);
      continue;
    }
    if (depth === 0) out += ch;
  }
  return out;
}

function auditStatic() {
  const files = walkDir(SRC_DIR, (f) => f.endsWith(".svelte")).sort();
  const high = [];
  const medium = [];
  const excluded = { virtualZoneButtons: 0, inputs: 0, technical: 0 };
  const stats = {
    components: files.length,
    overlayComponents: 0,
    ifBlocks: 0,
    buttons: 0,
    animatedButtons: 0,
  };

  for (const file of files) {
    const content = fs.readFileSync(file, "utf8");
    const rel = relFile(file);
    const base = path.basename(file);
    const styleBlock = extractStyleBlock(content);
    const fileAnimatedClasses = styleBlock
      ? collectStyledAnimatedClasses(styleBlock.body)
      : new Set();
    for (const c of fileAnimatedClasses) knownAnimatedClasses.add(c);
    const skipRanges = buildSkipRanges(content);
    const styleRange = styleBlock ? [styleBlock.start, styleBlock.start + styleBlock.body.length + 20] : null;
    const ranges = styleRange ? [...skipRanges, styleRange] : skipRanges;

    const isOverlayFile = OVERLAY_FILE_RE.test(base) || rel.startsWith("src/shared/ui/");
    if (isOverlayFile) stats.overlayComponents++;
    const isVirtualZone = VIRTUAL_ZONE_RE.test(rel);

    /* --- 🔴 {#if} blocks of overlays / collapsible sections --- */
    const ifBlocks = findIfBlocks(content);
    stats.ifBlocks += ifBlocks.length;
    for (const block of ifBlocks) {
      if (inRanges(block.start, ranges)) continue;
      const isCollapsible = COLLAPSE_STATE_RE.test(block.cond);
      if (!isOverlayFile && !isCollapsible) continue;
      const body = block.body;
      if (body.length < 60 || !body.includes("<")) continue; // technical wrappers
      // Skip purely technical {#if} branches: svg resize handles, {@render} slots,
      // role="presentation" wrappers — anything without visible text or a mounted component.
      const bodyNoComments = body.replace(/<!--[\s\S]*?-->/g, "");
      const mountsComponent = /<[A-Z][\w]*[\s/>]/.test(bodyNoComments);
      const visibleText = stripSvelteExpressions(bodyNoComments.replace(/<[^>]*>/g, " "))
        .replace(/\s+/g, " ")
        .trim();
      if (visibleText === "" && !mountsComponent) continue;
      const hasDirective = /\b(transition|in|out|animate):/.test(body);
      const hasAnimatingClass =
        ANIMATING_CLASS_RE.test(body) ||
        [...fileAnimatedClasses].some((c) => body.includes(c)) ||
        /style\s*=\s*["'][^"']*transition/.test(body) ||
        /style:.*transition/.test(body);
      if (hasDirective || hasAnimatingClass) continue;
      high.push({
        file: rel,
        line: lineOf(content, block.start),
        kind: isOverlayFile ? "overlay" : "collapse",
        cond: block.cond.replace(/\s+/g, " ").slice(0, 90),
        snippet: body
          .replace(/\s+/g, " ")
          .replace(/<[^>]*>/g, "")
          .trim()
          .slice(0, 70),
      });
    }

    /* --- 🟡 interactive controls without transitions --- */
    const elementRe = /<(button|a|div|span|label|li|input)\b/g;
    let elMatch;
    while ((elMatch = elementRe.exec(content)) !== null) {
      const tagName = elMatch[1].toLowerCase();
      const tagEnd = findOpenTagEnd(content, elMatch.index);
      if (tagEnd === -1) continue;
      const attrs = content.slice(elMatch.index, tagEnd + 1);
      if (inRanges(elMatch.index, ranges)) continue;
      const isInteractive =
        tagName === "button" || tagName === "a" || /\bonclick=|\brole=["']button["']/.test(attrs);
      if (!isInteractive) continue;
      if (tagName === "input") {
        excluded.inputs++;
        continue;
      }
      stats.buttons++;
      const cls = extractAttr(attrs, "class");
      const styleAttr = extractAttr(attrs, "style");
      const classTokens = cls.split(/\s+/).filter(Boolean);
      const animated =
        classTokens.some((c) => isAnimatingClass(c, fileAnimatedClasses)) ||
        /transition\s*:/.test(styleAttr) ||
        /style:.*transition/.test(attrs);
      if (animated) {
        stats.animatedButtons++;
        continue;
      }
      if (isVirtualZone) {
        excluded.virtualZoneButtons++;
        continue; // 🟢 exception: virtual-scroll internals
      }
      // 🟢 exception: native popover panels are animated by the global [popover]
      // rule in app.css (@starting-style + allow-discrete), not by utility classes.
      if (/\bpopover\s*=/.test(attrs)) {
        excluded.popoverPanels = (excluded.popoverPanels || 0) + 1;
        continue;
      }
      // 🟢 exception: display:contents wrappers have no box — nothing can animate.
      if (classTokens.includes("contents")) {
        excluded.technical++;
        continue;
      }
      // 🟢 exception: a class list with no state variants (hover:/active:/
      // focus-visible:/group-hover:) never changes on hover — their hover effects
      // live on group-hover children (which are expected to carry their own transition).
      if (!STATE_VARIANT_RE.test(cls)) {
        excluded.noStateChange = (excluded.noStateChange || 0) + 1;
        continue;
      }
      // 🟢 exception: class comes from a local helper (tabClass(…) / viewClass(…)).
      // Not resolvable statically — these helpers are expected to include a
      // transition class themselves (verified during the animation audit).
      if (/^[\w$]+\([^()]*\)$/.test(cls.trim())) {
        excluded.dynamicHelpers = (excluded.dynamicHelpers || 0) + 1;
        continue;
      }
      const label = buttonLabel(content.slice(tagEnd + 1), attrs, tagName);
      if (label === "(без текста)" && !cls) {
        excluded.technical++;
        continue; // purely technical wrapper without class or label
      }
      medium.push({
        file: rel,
        line: lineOf(content, elMatch.index),
        tag: tagName,
        label,
        cls: cls.replace(/\{[^}]*\}/g, "").trim().slice(0, 80) || "(нет класса)",
      });
    }
  }

  return { high, medium, excluded, stats };
}

/* ------------------------------------------------------------------ */
/* Part B — runtime audit (Playwright)                                 */
/* ------------------------------------------------------------------ */

async function auditRuntime() {
  const requireFromUi = createRequire(path.join(UI_DIR, "package.json"));
  const { chromium } = requireFromUi("playwright-core");
  const harnessModule = await import(
    pathToFileURL(path.join(UI_DIR, "checks/harness/testServerHarness.ts")).href
  );

  const runtime = {
    screens: [],
    buttonsWithoutTransition: [],
    instantChanges: [],
    panelsWithoutAnimation: [],
    notes: [],
  };

  const harness = await harnessModule.ensureTestServer();
  const BASE = harness.baseUrl;
  const browser = await chromium.launch({
    channel: process.env.TS_BROWSER_CHANNEL || (process.platform === "win32" ? "msedge" : undefined),
    headless: true,
  });
  const page = await browser.newPage({ viewport: { width: 1440, height: 900 } });
  page.setDefaultTimeout(15000);

  // Instrumentation installed before any navigation: collects DOM mutations and
  // real animation starts (CSS transitions, CSS keyframes, Web Animations API).
  await page.addInitScript(() => {
    window.__animAuditState = null;
    window.__animAuditBegin = () => {
      const state = { mutations: 0, anims: [] };
      const obs = new MutationObserver((muts) => {
        state.mutations += muts.length;
      });
      obs.observe(document.documentElement, { childList: true, subtree: true, attributes: true });
      const onAnim = (e) => {
        state.anims.push(e.type + ":" + (e.animationName || e.propertyName || ""));
      };
      document.addEventListener("transitionstart", onAnim, true);
      document.addEventListener("animationstart", onAnim, true);
      const t0 = performance.now();
      const poll = () => {
        for (const a of document.getAnimations()) {
          if (!a.__animSeen) {
            a.__animSeen = true;
            state.anims.push("getAnimations:" + (a.animationName || a.transitionProperty || a.constructor.name));
          }
        }
        if (performance.now() - t0 < 1100) requestAnimationFrame(poll);
      };
      requestAnimationFrame(poll);
      window.__animAuditState = state;
      return true;
    };
    window.__animAuditEnd = () => {
      const s = window.__animAuditState;
      window.__animAuditState = null;
      return s ? { mutations: s.mutations, anims: s.anims.slice(0, 5) } : null;
    };
    window.__auditControls = () => {
      const visible = (el) => {
        const r = el.getBoundingClientRect();
        return r.width > 1 && r.height > 1 && el.getClientRects().length > 0;
      };
      const els = [...document.querySelectorAll('button, [role="button"], [role="tab"]')].filter(
        (el) => visible(el) && !el.disabled,
      );
      return els.slice(0, 400).map((el, i) => {
        el.setAttribute("data-anim-audit", String(i));
        const cs = getComputedStyle(el);
        const durations = (cs.transitionDuration || "0s")
          .split(",")
          .map((d) => parseFloat(d) || 0);
        const total = durations.reduce((a, b) => a + b, 0);
        return {
          i,
          tag: el.tagName.toLowerCase(),
          text: (el.textContent || "").replace(/\s+/g, " ").trim().slice(0, 50),
          cls: (el.getAttribute("class") || "").slice(0, 90),
          transitionDuration: cs.transitionDuration,
          transitionProperty: cs.transitionProperty,
          hasTransition: total > 0,
        };
      });
    };
  });

  async function auditControls(screenName) {
    const controls = await page.evaluate(() => window.__auditControls());
    runtime.screens.push({
      screen: screenName,
      url: page.url(),
      controls: controls.length,
      withoutTransition: controls.filter((c) => !c.hasTransition).length,
    });
    for (const c of controls) {
      if (!c.hasTransition) {
        runtime.buttonsWithoutTransition.push({ screen: screenName, ...c });
      }
      await page
        .evaluate((idx) => {
          const el = document.querySelector(`[data-anim-audit="${idx}"]`);
          if (el) el.removeAttribute("data-anim-audit");
        }, c.i)
        .catch(() => {});
    }
  }

  /** Click an element and check whether the DOM change came with a real animation. */
  async function clickAudit(screenName, kind, selector, label) {
    try {
      const el = page.locator(selector).first();
      if (!(await el.isVisible().catch(() => false))) return;
      await el.scrollIntoViewIfNeeded().catch(() => {});
      await page.evaluate(() => window.__animAuditBegin());
      await el.click({ timeout: 4000 });
      await page.waitForTimeout(900);
      const result = await page.evaluate(() => window.__animAuditEnd());
      if (!result) return;
      if (result.mutations > 0 && result.anims.length === 0) {
        runtime.instantChanges.push({
          screen: screenName,
          kind,
          selector,
          label: label || (await el.textContent().catch(() => "")).trim().slice(0, 50),
          mutations: result.mutations,
        });
      }
    } catch (err) {
      runtime.notes.push(`[${screenName}] click-audit failed for ${selector}: ${err.message.split("\n")[0]}`);
    }
  }

  /** Measure a live overlay surface (popover/dialog) for appear-animation styles. */
  async function panelAudit(screenName, kind, selector) {
    try {
      const info = await page.evaluate((sel) => {
        const el = document.querySelector(sel);
        if (!el) return null;
        const cs = getComputedStyle(el);
        const dur = (cs.transitionDuration || "0s").split(",").map(parseFloat).reduce((a, b) => a + b, 0);
        return {
          animName: cs.animationName,
          animDur: cs.animationDuration,
          transitionDur: cs.transitionDuration,
          animated: cs.animationName !== "none" || dur > 0,
        };
      }, selector);
      if (info && !info.animated) {
        runtime.panelsWithoutAnimation.push({ screen: screenName, kind, selector, ...info });
      }
    } catch {
      // Overlay already closed — not a problem for a diagnostic pass.
    }
  }

  try {
    /* --- Screen 1: Home --- */
    await page.goto(`${BASE}/?view=home`, { waitUntil: "domcontentloaded" });
    await page.waitForSelector('.media-card, [data-widget="sidebar"]', { timeout: 15000 });
    await page.waitForTimeout(800);
    await auditControls("Главная");

    await clickAudit("Главная", "popover", "button[popovertarget]", "Поповер статуса карточки");
    await panelAudit("Главная", "popover", "[popover]:popover-open");
    await page.keyboard.press("Escape").catch(() => {});
    await page.waitForTimeout(300);

    /* --- Screen 2: Category (game) --- */
    await page.goto(`${BASE}/?view=game`, { waitUntil: "domcontentloaded" });
    await page.waitForSelector('.media-card, [data-widget="sidebar"]', { timeout: 15000 });
    await page.waitForTimeout(600);
    await auditControls("Категория (game)");
    await clickAudit("Категория (game)", "popover", "button[popovertarget]", "Поповер статуса карточки");
    await panelAudit("Категория (game)", "popover", "[popover]:popover-open");
    await page.keyboard.press("Escape").catch(() => {});

    /* --- Screen 3: Detail page with tabs --- */
    await page.goto(`${BASE}/?view=detail&mediaId=${harness.seededIds.tvshowId}`, {
      waitUntil: "domcontentloaded",
    });
    await page.waitForSelector("main", { timeout: 15000 });
    await page.waitForTimeout(1000);
    await auditControls("Детальная (tvshow)");

    // Sub-tabs: role-based first, then localized text fallback.
    const tabCount = await page.locator('[role="tab"]').count();
    if (tabCount > 0) {
      for (let i = 1; i < Math.min(tabCount, 5); i++) {
        await clickAudit("Детальная (tvshow)", "tab", `[role="tab"] >> nth=${i}`, `Вкладка #${i}`);
      }
    } else {
      for (const name of ["Эпизоды", "Episodes", "Галерея", "Gallery"]) {
        await clickAudit(
          "Детальная (tvshow)",
          "tab",
          `button:text-is("${name}")`,
          `Вкладка «${name}»`,
        );
      }
    }

    // Collapsible sections on the detail page.
    const expandCount = await page.locator("button[aria-expanded]").count();
    for (let i = 0; i < Math.min(expandCount, 4); i++) {
      await clickAudit(
        "Детальная (tvshow)",
        "collapse",
        `button[aria-expanded] >> nth=${i}`,
        `Сворачиваемая секция #${i}`,
      );
    }

    /* --- Screen 4: Settings --- */
    await page.goto(`${BASE}/?view=settings`, { waitUntil: "domcontentloaded" });
    await page.waitForTimeout(800);
    await auditControls("Настройки");
    await panelAudit("Настройки", "dialog", "dialog[open]");
    const settingsTabCount = await page.locator('[role="tab"]').count();
    for (let i = 1; i < Math.min(settingsTabCount, 5); i++) {
      await clickAudit("Настройки", "tab", `[role="tab"] >> nth=${i}`, `Вкладка настроек #${i}`);
    }

    /* --- Screen 5: Media editor (best effort) --- */
    await page.goto(`${BASE}/?view=detail&mediaId=${harness.seededIds.movieId}`, {
      waitUntil: "domcontentloaded",
    });
    await page.waitForTimeout(800);
    const editBtn = page.getByRole("button", { name: /редакт|edit/i }).first();
    if (await editBtn.isVisible().catch(() => false)) {
      await editBtn.click();
      await page.waitForTimeout(900);
      await auditControls("Редактор медиа");
      await clickAudit("Редактор медиа", "collapse", "button[aria-expanded] >> nth=0", "Секция редактора");
    } else {
      runtime.notes.push("[Редактор медиа] Кнопка редактирования не найдена — экран пропущен.");
    }
  } catch (err) {
    runtime.notes.push(`Runtime audit error: ${err.message.split("\n")[0]}`);
  } finally {
    await browser.close().catch(() => {});
    await harness.stop().catch(() => {});
  }

  return runtime;
}

/* ------------------------------------------------------------------ */
/* Report generation                                                   */
/* ------------------------------------------------------------------ */

function renderReport(staticRes, runtimeRes, runtimeFresh) {
  const { high, medium, excluded, stats } = staticRes;
  const lines = [];
  const now = new Date().toISOString().replace("T", " ").slice(0, 16);

  lines.push(`# ANIMATION_AUDIT — аудит анимаций интерфейса Tsundoku`);
  lines.push("");
  lines.push(`> Сгенерировано \`scripts/audit-animations.mjs\` ${now}. Диагностический отчёт — только чтение.`);
  lines.push(
    runtimeFresh
      ? `Runtime-аудит: **выполнен в этом прогоне** (Playwright + testServerHarness).`
      : runtimeRes
        ? `Runtime-аудит: результаты предыдущего \`--runtime\` прогона (для обновления запустите \`--runtime\`).`
        : `Runtime-аудит: **не выполнялся** (запустите с \`--runtime\`).`,
  );
  lines.push("");

  lines.push("## Сводка");
  lines.push("");
  lines.push(`| Метрика | Значение |`);
  lines.push(`| --- | --- |`);
  lines.push(`| Компонентов просканировано | ${stats.components} |`);
  lines.push(`| Из них оверлеи/поповеры/модалки | ${stats.overlayComponents} |`);
  lines.push(`| \\{#if\\}-блоков проанализировано | ${stats.ifBlocks} |`);
  lines.push(`| Интерактивных контролов найдено | ${stats.buttons} |`);
  lines.push(`| … с transition-классами/стилями | ${stats.animatedButtons} |`);
  lines.push(`| 🟢 Исключено: внутри виртуального скролла | ${excluded.virtualZoneButtons} |`);
  lines.push(`| 🟢 Исключено: базовые \`<input>\` | ${excluded.inputs} |`);
  lines.push(`| 🟢 Исключено: технические обёртки | ${excluded.technical} |`);
  lines.push(`| 🔴 Оверлеи/аккордеоны без анимации | ${high.length} |`);
  lines.push(`| 🟡 Кнопки без hover/click transition | ${medium.length} |`);
  if (runtimeRes) {
    lines.push(
      `| Рантайм: контролов проверено | ${runtimeRes.screens.reduce((a, s) => a + s.controls, 0)} |`,
    );
    lines.push(`| Рантайм: кнопки без transition | ${runtimeRes.buttonsWithoutTransition.length} |`);
    lines.push(`| Рантайм: мгновенные смены без анимации | ${runtimeRes.instantChanges.length} |`);
    lines.push(`| Рантайм: панели без анимации появления | ${runtimeRes.panelsWithoutAnimation.length} |`);
  }
  lines.push("");

  lines.push("## 🔴 Панели и модалки/поповеры без анимации появления");
  lines.push("");
  if (high.length === 0) {
    lines.push("_Не найдено — все оверлейные {#if}-блоки имеют transition-директивы или анимирующие классы._");
  } else {
    lines.push("| Файл | Строка | Тип | Условие | Содержимое |");
    lines.push("| --- | --- | --- | --- | --- |");
    for (const f of high) {
      lines.push(`| \`${f.file}\` | ${f.line} | ${f.kind} | \`${f.cond}\` | ${f.snippet} |`);
    }
  }
  lines.push("");

  lines.push("## 🟡 Кнопки и переключатели без hover/click transition");
  lines.push("");
  if (medium.length === 0) {
    lines.push("_Не найдено._");
  } else {
    const byFile = new Map();
    for (const f of medium) {
      if (!byFile.has(f.file)) byFile.set(f.file, []);
      byFile.get(f.file).push(f);
    }
    for (const [file, items] of byFile) {
      lines.push(`### \`${file}\``);
      lines.push("");
      for (const it of items) {
        lines.push(`- стр. ${it.line} — \`<${it.tag}>\` «${it.label}» · классы: \`${it.cls}\``);
      }
      lines.push("");
    }
  }

  if (runtimeRes) {
    lines.push("## 🖥️ Runtime-аудит (живой браузер)");
    lines.push("");
    lines.push("### Экраны");
    lines.push("");
    lines.push("| Экран | Контролов | Без transition |");
    lines.push("| --- | --- | --- |");
    for (const s of runtimeRes.screens) {
      lines.push(`| ${s.screen} | ${s.controls} | ${s.withoutTransition} |`);
    }
    lines.push("");

    lines.push("### Кнопки без transition при hover/active (computed `transition-duration: 0s`)");
    lines.push("");
    if (runtimeRes.buttonsWithoutTransition.length === 0) {
      lines.push("_Все видимые контролы имеют ненулевую transition-duration._");
    } else {
      const byScreen = new Map();
      for (const b of runtimeRes.buttonsWithoutTransition) {
        if (!byScreen.has(b.screen)) byScreen.set(b.screen, []);
        byScreen.get(b.screen).push(b);
      }
      for (const [screen, items] of byScreen) {
        lines.push(`**${screen}** (${items.length}):`);
        lines.push("");
        for (const it of items.slice(0, 40)) {
          lines.push(`- \`<${it.tag}>\` «${it.text || "(пусто)"}» · \`${it.cls}\``);
        }
        if (items.length > 40) lines.push(`- … и ещё ${items.length - 40}`);
        lines.push("");
      }
    }

    lines.push("### Мгновенная смена без анимации (или сломанная CSS-анимация)");
    lines.push("");
    if (runtimeRes.instantChanges.length === 0) {
      lines.push("_Каждое клик-изменение DOM сопровождалось хотя бы одной CSS/Web анимацией._");
    } else {
      for (const c of runtimeRes.instantChanges) {
        lines.push(
          `- **${c.screen}** · ${c.kind} · «${c.label}» (\`${c.selector}\`) — DOM изменился (${c.mutations} мутаций), анимаций: 0`,
        );
      }
    }
    lines.push("");

    lines.push("### Панели/оверлеи без анимации появления (computed style открытой панели)");
    lines.push("");
    if (runtimeRes.panelsWithoutAnimation.length === 0) {
      lines.push("_Все открытые панели имели animation-name ≠ none или ненулевую transition-duration._");
    } else {
      for (const p of runtimeRes.panelsWithoutAnimation) {
        lines.push(
          `- **${p.screen}** · ${p.kind} · \`${p.selector}\` — animation: ${p.animName} ${p.animDur}, transition-duration: ${p.transitionDur}`,
        );
      }
    }
    lines.push("");

    if (runtimeRes.notes.length > 0) {
      lines.push("### Замечания рантайма");
      lines.push("");
      for (const n of runtimeRes.notes) lines.push(`- ${n}`);
      lines.push("");
    }
  }

  lines.push("---");
  lines.push("_Скрипт ничего не исправляет: см. находки выше. Пересобрать отчёт: `npm --prefix mediatracker-ui run audit:animations [-- --runtime]`._");
  return lines.join("\n");
}

/* ------------------------------------------------------------------ */
/* Main                                                                */
/* ------------------------------------------------------------------ */

(async () => {
  if (!fs.existsSync(REPORTS_DIR)) fs.mkdirSync(REPORTS_DIR, { recursive: true });

  console.log("[audit:animations] Часть A: статический анализ src/**/*.svelte …");
  const staticRes = auditStatic();

  let runtimeRes = null;
  if (RUNTIME_FLAG) {
    // Full run overwrites any previously stored runtime section.
    console.log("[audit:animations] Часть B: runtime-аудит через Playwright + testServerHarness …");
    try {
      runtimeRes = await auditRuntime();
    } catch (err) {
      console.warn(`[audit:animations] Runtime-аудит не удался: ${err.message.split("\n")[0]}`);
      console.warn("[audit:animations] Отчёт будет содержать только статические находки.");
    }
  } else if (fs.existsSync(JSON_REPORT_PATH)) {
    // Static-only run: keep the runtime section from the last --runtime pass,
    // so regenerating the MD never silently drops live-browser findings.
    try {
      const prev = JSON.parse(fs.readFileSync(JSON_REPORT_PATH, "utf8"));
      if (prev?.runtime) runtimeRes = prev.runtime;
    } catch {
      // Corrupted artifact — report without runtime section.
    }
  }

  const md = renderReport(staticRes, runtimeRes, RUNTIME_FLAG && runtimeRes !== null);
  fs.writeFileSync(MD_REPORT_PATH, md, "utf8");
  fs.writeFileSync(
    JSON_REPORT_PATH,
    JSON.stringify({ static: staticRes, runtime: runtimeRes, generatedAt: new Date().toISOString() }, null, 2),
    "utf8",
  );

  const { high, medium, stats } = staticRes;
  console.log("");
  console.log(
    `[audit:animations] Статика: компонентов ${stats.components}, оверлеев ${stats.overlayComponents}, {#if}-блоков ${stats.ifBlocks}, контролов ${stats.buttons}.`,
  );
  console.log(`🔴 Оверлеи/аккордеоны без анимации появления: ${high.length}`);
  for (const f of high.slice(0, 15)) {
    console.log(`   -> ${f.file}:${f.line} [${f.kind}] ${f.cond}`);
  }
  if (high.length > 15) console.log(`   … и ещё ${high.length - 15}`);
  console.log(`🟡 Кнопки/переключатели без hover/click transition: ${medium.length}`);
  for (const f of medium.slice(0, 15)) {
    console.log(`   -> ${f.file}:${f.line} <${f.tag}> «${f.label}»`);
  }
  if (medium.length > 15) console.log(`   … и ещё ${medium.length - 15}`);
  if (runtimeRes) {
    const totalControls = runtimeRes.screens.reduce((a, s) => a + s.controls, 0);
    console.log(
      `🖥️ Рантайм: экранов ${runtimeRes.screens.length}, контролов ${totalControls}, без transition ${runtimeRes.buttonsWithoutTransition.length}, мгновенных смен ${runtimeRes.instantChanges.length}, панелей без анимации ${runtimeRes.panelsWithoutAnimation.length}.`,
    );
  }
  console.log(`📄 Отчёт: ${MD_REPORT_PATH}`);
  console.log(`🧾 JSON:  ${JSON_REPORT_PATH}`);
})();
