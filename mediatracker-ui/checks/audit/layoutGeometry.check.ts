import fs from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";
import { chromium, type BrowserContext, type Page } from "playwright";
import { ensureTestServer, type SeededIds } from "../harness/testServerHarness.ts";

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const reportsDir = path.resolve(__dirname, "../../../reports");

export interface LayoutAnomaly {
  type:
    | "horizontal-overflow-doc"
    | "horizontal-overflow-main"
    | "element-collision"
    | "target-size-too-small"
    | "target-collapsed"
    | "padding-too-small"
    | "line-length-too-wide"
    | "orphaned-glyph";
  screen: string;
  viewport: string;
  selector?: string;
  text?: string;
  details: string;
  box?: { x: number; y: number; width: number; height: number };
}

export interface ScreenGeometryResult {
  screen: string;
  viewport: string;
  viewportWidth: number;
  viewportHeight: number;
  url: string;
  anomalies: LayoutAnomaly[];
  passed: boolean;
}

export interface LayoutGeometryReport {
  timestamp: string;
  totalScreensChecked: number;
  totalAnomalies: number;
  passed: boolean;
  screens: ScreenGeometryResult[];
}

export async function runLayoutGeometry(options: {
  page: Page;
  baseUrl: string;
  seededIds: SeededIds;
}): Promise<LayoutGeometryReport> {
  const { page, baseUrl, seededIds } = options;

  const viewports = [
    { name: "desktop", width: 1440, height: 900 },
    { name: "mobile", width: 390, height: 844 },
  ];

  const screens = [
    { name: "home", path: "/?view=home" },
    { name: "game", path: "/?view=game" },
    { name: "stats", path: "/?view=stats" },
    { name: "lists", path: "/?view=lists" },
    { name: "history", path: "/?view=history" },
    { name: "calendar", path: "/?view=calendar" },
  ];

  const detailId = seededIds.gameId || seededIds.tvshowId || seededIds.allIds[0];
  if (detailId) {
    screens.push({ name: "detail", path: `/?view=detail&mediaId=${detailId}` });
  }

  const screenResults: ScreenGeometryResult[] = [];
  const allAnomalies: LayoutAnomaly[] = [];

  try {
    for (const vp of viewports) {
      await page.setViewportSize({ width: vp.width, height: vp.height });

      for (const sc of screens) {
        const targetUrl = `${baseUrl}${sc.path}`;
        await page.goto(targetUrl, { waitUntil: "domcontentloaded" });
        await page.waitForTimeout(600);

        const rawAnomalies = await page.evaluate(
        ({ screenName, vpName, vpWidth }) => {
          const list: Array<{
            type: string;
            selector?: string;
            text?: string;
            details: string;
            box?: { x: number; y: number; width: number; height: number };
          }> = [];

          function getCssSelector(el: Element): string {
            if (el.id) return `#${el.id}`;
            const parts: string[] = [];
            let curr: Element | null = el;
            while (curr && curr !== document.body && curr !== document.documentElement) {
              let part = curr.tagName.toLowerCase();
              if (curr.className && typeof curr.className === "string") {
                const firstCls = curr.className
                  .split(/\s+/)
                  .filter((c) => c && !c.includes(":") && !c.includes("/") && !c.includes("["))[0];
                if (firstCls) part += `.${firstCls}`;
              }
              parts.unshift(part);
              curr = curr.parentElement;
            }
            return parts.slice(-3).join(" > ");
          }

          // 1. Horizontal Overflow
          const docScroll = document.documentElement.scrollWidth;
          const docClient = document.documentElement.clientWidth;
          if (docScroll > docClient) {
            list.push({
              type: "horizontal-overflow-doc",
              details: `document.documentElement scrollWidth (${docScroll}px) > clientWidth (${docClient}px)`,
              box: { x: 0, y: 0, width: docScroll, height: window.innerHeight },
            });
          }

          const main = document.getElementById("main-scroll");
          if (main && main.scrollWidth > main.clientWidth + 1) {
            list.push({
              type: "horizontal-overflow-main",
              selector: "#main-scroll",
              details: `#main-scroll scrollWidth (${main.scrollWidth}px) > clientWidth (${main.clientWidth}px)`,
              box: { x: 0, y: 0, width: main.scrollWidth, height: main.clientHeight },
            });
          }

          // 2. Orphaned glyphs
          const walker = document.createTreeWalker(document.body, NodeFilter.SHOW_TEXT);
          let textNode: Node | null;
          const badLiterals = new Set(["undefined", "NaN", "[object Object]"]);
          while ((textNode = walker.nextNode())) {
            const val = textNode.nodeValue?.trim();
            if (val && badLiterals.has(val)) {
              const parent = textNode.parentElement;
              list.push({
                type: "orphaned-glyph",
                selector: parent ? getCssSelector(parent) : undefined,
                text: val,
                details: `Unexpected orphaned text value "${val}" found in DOM`,
              });
            }
          }

          // 3. Fitts Target Size & Collapsed controls
          const interactives = Array.from(
            document.querySelectorAll("button, a[href], input, select"),
          );
          for (const el of interactives) {
            if (el.closest('.hidden, [hidden], [aria-hidden="true"], [style*="display: none"]')) {
              continue;
            }
            const htmlEl = el as HTMLElement;
            if (htmlEl.offsetParent === null && window.getComputedStyle(el).position !== "fixed") {
              continue;
            }
            const style = window.getComputedStyle(el);
            if (
              style.display === "none" ||
              style.visibility === "hidden" ||
              style.opacity === "0"
            ) {
              continue;
            }
            const r = el.getBoundingClientRect();
            // Ignore elements entirely outside viewport
            if (r.bottom < 0 || r.top > window.innerHeight) continue;

            if (r.width === 0 && r.height === 0) {
              list.push({
                type: "target-collapsed",
                selector: getCssSelector(el),
                text: el.textContent?.trim().slice(0, 30),
                details: `Interactive element collapsed to 0x0`,
                box: { x: r.x, y: r.y, width: r.width, height: r.height },
              });
              continue;
            }

            if (r.width < 18 || r.height < 18) {
              list.push({
                type: "target-size-too-small",
                selector: getCssSelector(el),
                text: el.textContent?.trim().slice(0, 30),
                details: `Target size ${r.width.toFixed(1)}x${r.height.toFixed(1)}px is smaller than 20x20px`,
                box: { x: r.x, y: r.y, width: r.width, height: r.height },
              });
            }
          }

          // 4. Bounding Box Collision
          const containers = Array.from(
            document.querySelectorAll("div, nav, header, ul, ol, section"),
          );
          for (const parent of containers) {
            if (parent.closest(".media-poster, .aspect-\\[3\\/4\\]")) continue;
            const buttons = Array.from(parent.children).filter((c) =>
              ["BUTTON", "A", "INPUT", "SELECT"].includes(c.tagName),
            );
            if (buttons.length < 2) continue;

            for (let i = 0; i < buttons.length - 1; i++) {
              const b1 = buttons[i];
              const b2 = buttons[i + 1];
              const r1 = b1.getBoundingClientRect();
              const r2 = b2.getBoundingClientRect();
              if (r1.width === 0 || r2.width === 0) continue;

              const xOverlap = Math.max(0, Math.min(r1.right, r2.right) - Math.max(r1.left, r2.left));
              const yOverlap = Math.max(0, Math.min(r1.bottom, r2.bottom) - Math.max(r1.top, r2.top));

              if (xOverlap > 1 && yOverlap > 1) {
                list.push({
                  type: "element-collision",
                  selector: `${getCssSelector(b1)} & ${getCssSelector(b2)}`,
                  details: `Direct sibling controls overlap by ${xOverlap.toFixed(1)}x${yOverlap.toFixed(1)}px`,
                  box: { x: r1.x, y: r1.y, width: r1.width, height: r1.height },
                });
              }
            }
          }

          // 5. Padding vs Gap in Panels and Cards
          const cards = Array.from(document.querySelectorAll(".panel, article.media-card"));
          for (const card of cards) {
            const comp = window.getComputedStyle(card);
            const padTop = parseFloat(comp.paddingTop) || 0;
            const padLeft = parseFloat(comp.paddingLeft) || 0;
            if (padTop < 7 || padLeft < 7) {
              list.push({
                type: "padding-too-small",
                selector: getCssSelector(card),
                details: `Card/panel padding (${padTop}px / ${padLeft}px) is less than 8px`,
              });
            }
          }

          // 6. Max line length on desktop
          if (vpWidth >= 1200) {
            const paragraphs = Array.from(
              document.querySelectorAll(
                "#main-scroll p:not(.prose *), .media-detail p, section p",
              ),
            );
            for (const p of paragraphs) {
              if (p.closest('.hidden, [hidden]')) continue;
              const text = p.textContent?.trim() || "";
              if (text.length < 60) continue;
              const rect = p.getBoundingClientRect();
              if (rect.width > 950) {
                list.push({
                  type: "line-length-too-wide",
                  selector: getCssSelector(p),
                  text: text.slice(0, 40),
                  details: `Text paragraph width (${rect.width.toFixed(0)}px) exceeds recommended 900px line length`,
                  box: { x: rect.x, y: rect.y, width: rect.width, height: rect.height },
                });
              }
            }
          }

          return list;
        },
        { screenName: sc.name, vpName: vp.name, vpWidth: vp.width },
      );

      const mappedAnomalies: LayoutAnomaly[] = rawAnomalies.map((a) => ({
        type: a.type as LayoutAnomaly["type"],
        screen: sc.name,
        viewport: vp.name,
        selector: a.selector,
        text: a.text,
        details: a.details,
        box: a.box,
      }));

      allAnomalies.push(...mappedAnomalies);
      screenResults.push({
        screen: sc.name,
        viewport: vp.name,
        viewportWidth: vp.width,
        viewportHeight: vp.height,
        url: targetUrl,
        anomalies: mappedAnomalies,
        passed: mappedAnomalies.length === 0,
      });
    }
  }
} finally {
  await page.setViewportSize({ width: 1440, height: 900 }).catch(() => {});
}

  const report: LayoutGeometryReport = {
    timestamp: new Date().toISOString(),
    totalScreensChecked: screenResults.length,
    totalAnomalies: allAnomalies.length,
    passed: allAnomalies.length === 0,
    screens: screenResults,
  };

  fs.mkdirSync(reportsDir, { recursive: true });
  fs.writeFileSync(
    path.join(reportsDir, "layout-geometry.json"),
    JSON.stringify(report, null, 2),
    "utf-8",
  );

  return report;
}

// Standalone execution
if (process.argv[1] && fileURLToPath(import.meta.url) === path.resolve(process.argv[1])) {
  (async () => {
    console.log("[layoutGeometry] Starting standalone DOM geometry inspection...");
    const harness = await ensureTestServer();
    const browser = await chromium.launch({
      channel:
        process.env.TS_BROWSER_CHANNEL || (process.platform === "win32" ? "msedge" : undefined),
      headless: true,
    });
    const context: BrowserContext = await browser.newContext();
    const page = await context.newPage();

    try {
      const report = await runLayoutGeometry({
        page,
        baseUrl: harness.baseUrl,
        seededIds: harness.seededIds,
      });

      console.log("\n--- Layout Geometry Summary ---");
      for (const s of report.screens) {
        console.log(
          `  ${(s.screen + " (" + s.viewport + ")").padEnd(25)} | Anomalies: ${s.anomalies.length} | Status: ${s.passed ? "OK" : "FAIL"}`,
        );
        for (const a of s.anomalies) {
          console.log(`    - [${a.type}] ${a.details} ${a.selector ? "(" + a.selector + ")" : ""}`);
        }
      }

      if (!report.passed) {
        console.error(`\n[layoutGeometry] FAILED: ${report.totalAnomalies} geometry anomalies found!`);
        process.exitCode = 1;
      } else {
        console.log("\n[layoutGeometry] PASSED: 0 layout geometry anomalies found!");
      }
    } finally {
      await browser.close();
      await harness.stop();
    }
  })();
}
