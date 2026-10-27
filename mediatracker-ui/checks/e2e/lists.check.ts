// Regression guard for the lists redesign. Three things must hold:
//   1. A list card previews VERTICAL posters: an empty list renders the styled color block,
//      one title renders a crisp centered 2:3 poster over a blurred backdrop, 2-4 titles
//      render an overlapping fan -- never a squished horizontal strip.
//   2. The lists screen spans the full content width (the old max-width cap squeezed the
//      inner MediaGrid into tiny columns) and cards inside an open list are the same size
//      as the home grid's cards at the same viewport.
//   3. The RU title count declines correctly: "1 тайтл" / "3 тайтла", never "1 тайтлов".
// Run: `npm run check:lists` (needs the app on :5000, like the other browser checks).
import { chromium } from "playwright-core";

const BASE = process.env.TS_BASE || "http://localhost:5000";
const PREFIX = "ZZ Check ";

const fail = [];
const expect = (name, ok, extra) => {
  if (!ok) fail.push({ name, extra });
  return ok;
};

(async () => {
  const launchOptions = {
    channel: process.env.TS_BROWSER_CHANNEL || (process.platform === 'win32' ? 'msedge' : undefined),
    headless: true
  };
  const browser = await chromium.launch(launchOptions);
  const page = await browser.newPage({ viewport: { width: 1920, height: 1080 } });
  const created = [];
  try {
    const errors = [];
    page.on("pageerror", (e) => errors.push(e.message));

    // --- fixtures: one list per preview branch (0 / 1 / 3 titles), sweeping stale ones first.
    const api = {
      get: (p) => page.request.get(BASE + p).then((r) => r.json()),
      post: (p, data) => page.request.post(BASE + p, { data }),
      del: (p) => page.request.delete(BASE + p),
    };

    const media = await api.get("/api/media");
    const ids = media
      .filter((m) => m.coverUrl)
      .slice(0, 3)
      .map((m) => m.id);
    expect("library has 3 covered titles", ids.length === 3, {
      total: media.length,
    });

    const stale = (await api.get("/api/lists")).filter((l) =>
      l.name.startsWith(PREFIX),
    );
    for (const list of stale) await api.del(`/api/lists/${list.id}`);

    const mkList = async (name) => {
      const res = await api.post("/api/lists/", {
        name,
        description: null,
        icon: "star",
        color: "#3b82f6",
      });
      const body = await res.json();
      created.push(body.id);
      return body.id;
    };
    const emptyId = await mkList(PREFIX + "Empty");
    const singleId = await mkList(PREFIX + "Single");
    const fanId = await mkList(PREFIX + "Fan");
    expect("fixture lists created", !!(emptyId && singleId && fanId), {
      emptyId,
      singleId,
      fanId,
    });
    await api.post(`/api/lists/${singleId}/items`, { mediaId: ids[0] });
    for (const mediaId of ids) {
      await api.post(`/api/lists/${fanId}/items`, { mediaId });
    }

    // --- lists screen -------------------------------------------------------------
    await page.goto(BASE + "/?view=lists", { waitUntil: "domcontentloaded" });
    const cardOf = (name) => page.locator("article").filter({ hasText: name });
    await cardOf(PREFIX + "Empty").waitFor({ state: "visible", timeout: 15000 });

    // Geometry of one list card's preview block: container box, every img inside it,
    // whether the styled empty block / icon are present, and the footer text.
    const probe = (name) =>
      cardOf(name).evaluate((article) => {
        const preview = article.querySelector('div[class*="h-44"]');
        if (!preview) return null;
        const pr = preview.getBoundingClientRect();
        const imgs = [...preview.querySelectorAll("img")].map((img) => {
          const r = img.getBoundingClientRect();
          const cs = getComputedStyle(img);
          return {
            blurred: img.className.includes("blur-"),
            aspect: img.className.includes("aspect-"),
            x: r.x,
            w: r.width,
            h: r.height,
            pos: cs.position,
            opacity: cs.opacity,
            filter: cs.filter,
          };
        });
        return {
          pw: pr.width,
          ph: pr.height,
          left: pr.x,
          right: pr.right,
          imgs,
          gradient: !!preview.querySelector('[style*="linear-gradient"]'),
          icon: !!preview.querySelector("span.grid"),
          footer: article.innerText,
        };
      });

    const previews = {
      empty: await probe(PREFIX + "Empty"),
      single: await probe(PREFIX + "Single"),
      fan: await probe(PREFIX + "Fan"),
    };

    // 1a. Empty list -> styled color block with the icon, no images, h-44 area.
    const e = previews.empty;
    expect("empty: preview block renders", !!e, previews.empty);
    if (e) {
      expect("empty: preview is h-44 (176px)", Math.abs(e.ph - 176) <= 1, { ph: e.ph });
      expect("empty: no images", e.imgs.length === 0, { n: e.imgs.length });
      expect("empty: list-color gradient block", e.gradient, e);
      expect("empty: icon centered in the block", e.icon, e);
      expect("empty: footer says 0 тайтлов", /0 тайтлов/.test(e.footer), { footer: e.footer });
    }

    // 1b. One title -> blurred backdrop copy + crisp centered vertical poster.
    const s = previews.single;
    expect("single: preview block renders", !!s, previews.single);
    if (s) {
      expect("single: preview is h-44 (176px)", Math.abs(s.ph - 176) <= 1, { ph: s.ph });
      expect("single: two images (backdrop + poster)", s.imgs.length === 2, { imgs: s.imgs });
      const bg = s.imgs.find((i) => i.blurred);
      const poster = s.imgs.find((i) => i.aspect);
      expect("single: backdrop image exists", !!bg, s.imgs);
      if (bg) {
        expect("single: backdrop is absolute", bg.pos === "absolute", bg);
        expect("single: backdrop blurred by 20px", bg.filter.includes("blur(20px)"), bg);
        expect("single: backdrop is 25% opacity", bg.opacity === "0.25", bg);
        expect("single: backdrop scaled to 125%", Math.abs(bg.w / s.pw - 1.25) <= 0.03, {
          bgw: bg.w,
          pw: s.pw,
        });
      }
      expect("single: crisp poster exists", !!poster, s.imgs);
      if (poster) {
        expect("single: poster keeps 2:3 ratio", Math.abs(poster.w / poster.h - 2 / 3) <= 0.03, {
          w: poster.w,
          h: poster.h,
        });
        expect("single: poster is h-36 (144px)", Math.abs(poster.h - 144) <= 1, { h: poster.h });
        expect("single: poster dominates the preview height", poster.h > s.ph * 0.7, {
          h: poster.h,
          ph: s.ph,
        });
        expect(
          "single: footer declines to «1 тайтл»",
          /1 тайтл/.test(s.footer) && !/1 тайтл(ов|а)/.test(s.footer),
          { footer: s.footer },
        );
      }
    }

    // 1c. 2-4 titles -> overlapping fan of vertical posters.
    const f = previews.fan;
    expect("fan: preview block renders", !!f, previews.fan);
    if (f) {
      expect("fan: preview is h-44 (176px)", Math.abs(f.ph - 176) <= 1, { ph: f.ph });
      expect("fan: three images", f.imgs.length === 3, { imgs: f.imgs.length });
      for (const [i, img] of f.imgs.entries()) {
        expect(`fan: poster ${i} keeps 2:3 ratio`, Math.abs(img.w / img.h - 2 / 3) <= 0.03, img);
        expect(`fan: poster ${i} is vertical (h 128..145)`, img.h >= 127 && img.h <= 145, img);
        expect(
          `fan: poster ${i} stays inside the preview`,
          img.x >= f.left - 1 && img.x + img.w <= f.right + 1,
          { x: img.x, w: img.w, left: f.left, right: f.right },
        );
      }
      const sorted = [...f.imgs].sort((a, b) => a.x - b.x);
      for (let i = 1; i < sorted.length; i++) {
        const gap = sorted[i].x - (sorted[i - 1].x + sorted[i - 1].w);
        expect(`fan: poster ${i} overlaps its neighbour (-space-x-5)`, gap < -5, { gap });
      }
      expect(
        "fan: footer declines to «3 тайтла»",
        /3 тайтла/.test(f.footer) && !/3 тайтлов/.test(f.footer),
        { footer: f.footer },
      );
    }

    // 2a. The lists grid spans the full content width (the old max-width cap sat way below this).
    const gridLoc = page.locator('main div[class*="grid-cols-4"]').first();
    const gridBox = await gridLoc.boundingBox();
    expect("lists grid spans the full width", !!gridBox && gridBox.width > 1400, gridBox);
    const tracks = await gridLoc.evaluate(
      (el) => getComputedStyle(el).gridTemplateColumns.split(" ").length,
    );
    expect("lists grid uses 4 columns at xl", tracks === 4, { tracks });

    // 2b. Open the single-title list: header plural + standard MediaGrid sizing.
    await cardOf(PREFIX + "Single").locator("button").first().click();
    await page
      .locator("main h2", { hasText: PREFIX + "Single" })
      .waitFor({ state: "visible", timeout: 15000 });

    const headerCount = await page
      .locator("main p", { hasText: /тайтл/ })
      .first()
      .innerText();
    expect(
      "list header declines to «1 тайтл»",
      /1 тайтл/.test(headerCount) && !/1 тайтл(ов|а)/.test(headerCount),
      { headerCount },
    );

    const detailGrid = page.locator('main div[class*="2xl:grid-cols-7"]').first();
    await detailGrid.waitFor({ state: "visible", timeout: 15000 });
    const detailTracks = await detailGrid.evaluate(
      (el) => getComputedStyle(el).gridTemplateColumns.split(" ").length,
    );
    expect("in-list MediaGrid keeps 7 columns at 2xl", detailTracks === 7, { detailTracks });
    const detailCard = await page.locator("main article").first().boundingBox();

    // 2c. Cards inside a list are the same size as on the home screen (same viewport).
    await page.goto(BASE + "/?view=home", { waitUntil: "domcontentloaded" });
    const homeCardLoc = page.locator("main article").first();
    await homeCardLoc.waitFor({ state: "visible", timeout: 15000 });
    const homeCard = await homeCardLoc.boundingBox();
    expect(
      "in-list card matches the home card size",
      !!detailCard && !!homeCard && Math.abs(detailCard.width - homeCard.width) <= 2,
      { detail: detailCard, home: homeCard },
    );

    // 3. CreateListModal: verify scrollable center, fixed header/footer, and clean emojis.
    await page.goto(BASE + "/?view=lists", { waitUntil: "domcontentloaded" });
    const createBtn = page.locator("button", { hasText: "+ Создать список" }).first();
    await createBtn.click();
    await page.locator("h2#custom-list-modal-title").waitFor({ state: "visible", timeout: 15000 });

    const manualBtn = page.locator("button", { hasText: "Обычный список" });
    const smartBtn = page.locator("button", { hasText: "Умный список" });
    const manualText = (await manualBtn.innerText()).trim();
    const smartText = (await smartBtn.innerText()).trim();

    expect("manual switch emoji is clean", !manualText.includes("📁 📁") && manualText.includes("📁"), { manualText });
    expect("smart switch emoji is clean", !smartText.includes("⚡ ⚡") && smartText.includes("⚡"), { smartText });

    await smartBtn.click();
    await page.waitForTimeout(300);

    const modalHeader = page.locator("header").filter({ hasText: "Создать список" });
    const modalFooter = page.locator("footer").filter({ hasText: "Создать" });
    expect("modal header is visible", await modalHeader.isVisible());
    expect("modal footer is visible", await modalFooter.isVisible());

    const footerMatches = modalFooter.locator("text=/Сейчас подходит/");
    expect("footer live matches indicator is visible", await footerMatches.isVisible());

    const scrollContainer = page.locator("form div.overflow-y-auto");
    const isScrollable = await scrollContainer.evaluate((el) => el.scrollHeight > el.clientHeight);
    expect("smart list builder is vertically scrollable", isScrollable);

    const limitInput = page.getByRole("spinbutton", { name: "Лимит" });
    await limitInput.scrollIntoViewIfNeeded();
    expect("limit input at bottom is reachable and visible", await limitInput.isVisible());
    expect("modal header stays visible after scrolling to bottom", await modalHeader.isVisible());
    expect("modal footer stays visible after scrolling to bottom", await modalFooter.isVisible());

    const closeBtn = modalHeader.locator("button[aria-label=\"Закрыть\"]");
    await closeBtn.click();
    await page.locator("h2#custom-list-modal-title").waitFor({ state: "hidden", timeout: 5000 });

    expect("no page errors", errors.length === 0, errors);

    console.log(
      JSON.stringify(
        { previews, gridBox, tracks, detailTracks, detailCard, homeCard, errors, failures: fail },
        null,
        2,
      ),
    );
    if (fail.length) {
      console.error("FAILED: " + fail.length);
      process.exit(1);
    }
    console.log("OK: list previews, full-width grid, in-list card size and RU plurals all behave");
  } finally {
    for (const id of created) {
      await page.request.delete(`${BASE}/api/lists/${id}`).catch(() => {});
    }
    await browser.close();
  }
})();

