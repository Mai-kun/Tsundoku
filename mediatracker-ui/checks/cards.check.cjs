// Regression guard for the card refactor: every media type renders its own
// chrome, the progress steppers increment optimistically (and only where they
// belong), hover-prefetch still warms the detail cache, and the detail view
// renders the type-specific sections.
// Run: `npm run check:cards` (needs the app on :5000, like the other browser checks).
const { chromium } = require("playwright-core");

const BASE = process.env.TS_BASE || "http://localhost:5000";

const fail = [];
const expect = (name, ok, extra) => {
  if (!ok) fail.push({ name, extra });
  return ok;
};

(async () => {
  const browser = await chromium.launch({ channel: "msedge" });
  const page = await browser.newPage({ viewport: { width: 1440, height: 900 } });
  const errors = [];
  page.on("pageerror", (e) => errors.push(e.message));

  const go = async (url) => {
    await page.goto(BASE + url, { waitUntil: "domcontentloaded" });
    await page.waitForTimeout(1500);
  };

  // Pick one item of each type straight from the API вЂ” no seeded ids hardcoded.
  const library = await page.request
    .get(`${BASE}/api/media`)
    .then((r) => r.json());
  const pick = (type) => library.find((m) => m.type === type);
  const game = pick("game");
  const book = pick("book");
  const manga = pick("manga");
  const movie = pick("movie");
  const tv = pick("tvshow");
  expect("library has every media type", !!(game && manga && movie && tv), {
    types: library.map((m) => m.type),
  });

  // 1. Home renders every card, each with a status badge.
  await go("/?view=home");
  const cards = await page.evaluate(() => {
    const all = [...document.querySelectorAll("article")];
    return {
      total: all.length,
      withBadge: all.filter((a) => a.querySelector("button[popovertarget]"))
        .length,
      withTitle: all.filter((a) => a.querySelector("h2")).length,
    };
  });
  expect("cards render with a title", cards.total > 0 && cards.withTitle === cards.total, cards);
  expect("every card has a status badge", cards.withBadge === cards.total, cards);

  // 2. Hover-prefetch warms the detail cache for the hovered card.
  await go("/?view=tvshow");
  const prefetch = await page.evaluate(async () => {
    const count = () =>
      performance
        .getEntriesByType("resource")
        .filter((r) => r.name.includes("/api/media/")).length;
    const before = count();
    document
      .querySelector("article")
      ?.dispatchEvent(new PointerEvent("pointerenter", { bubbles: true }));
    await new Promise((r) => setTimeout(r, 900));
    return { before, after: count() };
  });
  expect(
    "hover prefetch fires a detail request",
    prefetch.after > prefetch.before,
    prefetch,
  );
  // 3. Steppers: flip a few items to in-progress, then check each card type.
  const touched = [game, book, manga, tv, movie].filter(Boolean);
  for (const m of touched) {
    await page.request.put(`${BASE}/api/media/${m.id}/status`, {
      data: { status: 1 },
    });
  }

  const stepperFor = async (view) => {
    await go(`/?view=${view}`);
    return page.evaluate(async () => {
      const article = document.querySelector("article");
      if (!article) return { card: false };
      const plus = [...article.querySelectorAll("button")].find((b) =>
        /Increase|\u0443\u0432\u0435\u043b\u0438\u0447/i.test(
          b.getAttribute("aria-label") || "",
        ),
      );
      if (!plus) {
        return {
          card: true,
          stepper: false,
          text: article.innerText.replace(/\n/g, " | "),
        };
      }
      const box = plus.closest("div");
      const read = () => box?.querySelector("span")?.textContent?.trim();
      const before = read();
      plus.click();
      await new Promise((r) => setTimeout(r, 150));
      return { card: true, stepper: true, before, after: read() };
    });
  };

  for (const type of ["game", "book", "manga"]) {
    if (!pick(type)) continue;
    const r = await stepperFor(type);
    expect(`${type} card has a stepper`, r.stepper === true, r);
    expect(
      `${type} stepper increments optimistically`,
      r.stepper === true && r.before !== r.after,
      r,
    );
  }

  // Shows count episodes; movies carry only a runtime.
  const tvStepper = await stepperFor("tvshow");
  expect("tvshow card has an episode stepper", tvStepper.stepper === true, tvStepper);
  const movieStepper = await stepperFor("movie");
  expect("movie card has no stepper", movieStepper.stepper === false, movieStepper);
  expect(
    "movie card shows a runtime",
    /\d+\s*(min|\u043c)/i.test(movieStepper.text || ""),
    movieStepper,
  );
  // 4. Detail sections per media type.
  const detailFor = async (media) => {
    await go(`/?view=detail&mediaId=${media.id}`);
    return page.evaluate(() => {
      const t = document.body.innerText;
      return {
        sidebarHistory: /\u0418\u0441\u0442\u043e\u0440\u0438\u044f|Your history/i.test(t),
        sidebarActions: /\u0414\u0435\u0439\u0441\u0442\u0432\u0438\u044f|Actions/i.test(t),
        detailSpecs: /\u0425\u0430\u0440\u0430\u043a\u0442\u0435\u0440\u0438\u0441\u0442\u0438\u043a\u0438|Details/i.test(t),
        hasTabs: document.querySelectorAll("nav button").length > 0,
        speedometer: !!document.querySelector("svg circle"),
        achievements: /\u0414\u043e\u0441\u0442\u0438\u0436\u0435\u043d\u0438\u044f|Achievements/i.test(t),
        volumes: /\u0422\u043e\u043c\u0430|Volumes/i.test(t),
        seasonBanner: /Season|\u0421\u0435\u0437\u043e\u043d/i.test(t),
        episodes: /\u0421\u0435\u0440\u0438\u0438|Episodes/i.test(t),
      };
    });
  };

  const base = await detailFor(movie);
  expect(
    "detail sidebar renders (history, actions, specs)",
    base.sidebarHistory && base.sidebarActions && base.detailSpecs,
    base,
  );
  expect("detail tabs render", base.hasTabs, base);

  const gameDetail = await detailFor(game);
  expect("game detail has the speedometer", gameDetail.speedometer, gameDetail);
  expect("game detail has achievements", gameDetail.achievements, gameDetail);

  const mangaDetail = await detailFor(manga);
  expect("manga detail has volumes", mangaDetail.volumes, mangaDetail);

  const tvDetail = await detailFor(tv);
  expect(
    "tv detail has seasons/episodes",
    tvDetail.seasonBanner || tvDetail.episodes,
    tvDetail,
  );

  // Restore the statuses we flipped.
  for (const m of touched) {
    await page.request.put(`${BASE}/api/media/${m.id}/status`, {
      data: { status: m.status ?? 0 },
    });
  }


  // 5. Search preview shows the full metadata, minus related/recommendations.
  await go("/");
  await page.click('button[title*="Ctrl"], header button');
  await page.waitForTimeout(600);
  await page.fill("dialog[open] input[type='search']", "cowboy bebop");
  await page.waitForTimeout(7000);
  const opened = await page.evaluate(() => {
    const dialog = document.querySelector("dialog[open]");
    const row = dialog?.querySelector("[role='button']");
    if (!row) return { clicked: false };
    row.click();
    return { clicked: true };
  });
  expect("a search result opens the preview", opened.clicked, opened);
  await page.waitForTimeout(7000);

  const preview = await page.evaluate(() => {
    // The preview opens as a second dialog on top of the search one.
    const dialogs = [...document.querySelectorAll("dialog[open]")];
    const dialog = dialogs[dialogs.length - 1];
    if (!dialog || dialogs.length < 2) return { open: false };
    const t = dialog.innerText;
    return {
      open: true,
      specs: /\u0425\u0430\u0440\u0430\u043a\u0442\u0435\u0440\u0438\u0441\u0442\u0438\u043a\u0438|Details/i.test(t),
      synopsis: /\u0421\u0438\u043d\u043e\u043f\u0441\u0438\u0441|Synopsis/i.test(t),
      ratings: /anilist|shikimori|myanimelist|tmdb|rawg/i.test(dialog.innerHTML),
      genres: /\u0416\u0430\u043d\u0440\u044b|Genre/i.test(t),
      noRelated: !/\u0421\u0432\u044f\u0437\u0430\u043d\u043d\u044b\u0435|Related/i.test(t),
      noRecs: !/\u0420\u0435\u043a\u043e\u043c\u0435\u043d\u0434\u0430\u0446\u0438\u0438|Recommendation/i.test(t),
    };
  });
  expect("search preview opens", preview.open, preview);
  expect("preview lists the characteristics", preview.specs, preview);
  expect("preview lists the synopsis", preview.synopsis, preview);
  expect("preview lists external ratings", preview.ratings, preview);
  expect("preview lists genres", preview.genres, preview);
  expect("preview hides related titles", preview.noRelated, preview);
  expect("preview hides recommendations", preview.noRecs, preview);

  expect("no page errors", errors.length === 0, errors);

  console.log(
    JSON.stringify(
      { cards, prefetch, tvStepper, movieStepper, preview, errors, failures: fail },
      null,
      2,
    ),
  );
  await browser.close();
  if (fail.length) {
    console.error("FAILED: " + fail.length);
    process.exit(1);
  }
  console.log("OK: cards, steppers, prefetch and detail sections all behave");
})();
