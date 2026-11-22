import { createRequire } from "node:module";
import fs from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const require = createRequire(path.join(__dirname, "../mediatracker-ui/package.json"));
const { chromium } = require("playwright");

const BASE_URL = process.env.TS_FLUTTER_URL || "http://127.0.0.1:5099";
const OUT_DIR = process.env.TS_OUT_DIR || "/tmp/tsundoku-pixel-audit/flutter";

fs.mkdirSync(OUT_DIR, { recursive: true });

async function run() {
  console.log(`📸 Starting Flutter capture at 1920x1080 from ${BASE_URL}...`);

  // Fetch IDs from API
  const mediaRes = await fetch(`${BASE_URL}/api/media`);
  const mediaList = await mediaRes.json();
  const frieren = mediaList.find((m) => m.title.includes("Фрирен") || m.type === "tvshow");
  if (!frieren) {
    throw new Error("Could not find Frieren in media list");
  }
  const frierenId = frieren.id;
  console.log(`Using Frieren ID: ${frierenId}`);

  const browser = await chromium.launch({ headless: true });
  const context = await browser.newContext({
    viewport: { width: 1920, height: 1080 },
    deviceScaleFactor: 1.0,
  });
  const page = await context.newPage();

  async function capture(filename, url, waitMs = 1200) {
    console.log(`  -> Capturing ${filename} (${url})...`);
    await page.goto(url, { waitUntil: "networkidle" });
    await page.waitForTimeout(waitMs);
    const outPath = path.join(OUT_DIR, filename);
    await page.screenshot({ path: outPath, fullPage: false });
    console.log(`  ✓ Saved ${outPath}`);
  }

  // 1. 01_home.png (Главная с карточками и открытым поповером «Сколько есть времени?»)
  await capture("01_home.png", `${BASE_URL}/?view=home&popover=time`, 1500);

  // 2. 02_category_anime.png (Категория с FilterBar и сеткой)
  await capture("02_category_anime.png", `${BASE_URL}/?view=anime`, 1200);

  // 3. 03_detail_overview.png (Карточка медиа: Обзор, сайдбар, прогресс, персонажи, внешние источники)
  await capture("03_detail_overview.png", `${BASE_URL}/?view=detail&mediaId=${frierenId}`, 1500);

  // 4. 04_detail_episodes.png (Вкладка «Эпизоды»)
  await capture("04_detail_episodes.png", `${BASE_URL}/?view=detail&mediaId=${frierenId}&tab=episodes`, 1500);

  // 5. 05_edit_workspace.png (Пространственный редактор с ниточками)
  await capture("05_edit_workspace.png", `${BASE_URL}/?view=detail&mediaId=${frierenId}&edit=true`, 1800);

  // 6. 06_search_modal.png (Модалка внешнего поиска с результатами)
  await capture("06_search_modal.png", `${BASE_URL}/?view=home&search=true&query=Frieren`, 1500);

  // 7. 07_settings_sources.png (Настройки → Источники)
  await capture("07_settings_sources.png", `${BASE_URL}/?view=settings&tab=sources`, 1200);

  // 8. 08_settings_import.png (Настройки → Импорт)
  await capture("08_settings_import.png", `${BASE_URL}/?view=settings&tab=import`, 1200);

  // 9. 09_settings_appearance.png (Настройки → Внешний вид)
  await capture("09_settings_appearance.png", `${BASE_URL}/?view=settings&tab=appearance`, 1200);

  // 10. 10_settings_storage.png (Настройки → Хранилище / Поиск / Бэкап)
  await capture("10_settings_storage.png", `${BASE_URL}/?view=settings&tab=storage`, 1200);

  // 11. 11_stats.png (Статистика: Сводка + Taste Profile)
  await capture("11_stats.png", `${BASE_URL}/?view=stats`, 1500);

  // 12. 12_lists.png
  await capture("12_lists.png", `${BASE_URL}/?view=lists`, 1200);

  // 13. 13_history.png
  await capture("13_history.png", `${BASE_URL}/?view=history`, 1200);

  // 14. 14_calendar.png
  await capture("14_calendar.png", `${BASE_URL}/?view=calendar`, 1200);

  // 15. 15_goals.png
  await capture("15_goals.png", `${BASE_URL}/?view=goals`, 1200);

  await browser.close();
  console.log("🎉 All 15 Flutter screenshots captured successfully!");
}

run().catch((err) => {
  console.error("Flutter capture failed:", err);
  process.exit(1);
});
