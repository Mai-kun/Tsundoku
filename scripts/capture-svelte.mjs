import { createRequire } from "node:module";
import fs from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const require = createRequire(path.join(__dirname, "../mediatracker-ui/package.json"));
const { chromium } = require("playwright");

const BASE_URL = process.env.TS_SVELTE_URL || "http://127.0.0.1:5173";
const API_URL = process.env.TS_API_URL || "http://127.0.0.1:5099";
const OUT_DIR = process.env.TS_OUT_DIR || "/tmp/tsundoku-pixel-audit/svelte";

fs.mkdirSync(OUT_DIR, { recursive: true });

async function run() {
  console.log(`📸 Starting Svelte capture at 1920x1080 from ${BASE_URL}...`);

  // Fetch IDs from API
  const mediaRes = await fetch(`${API_URL}/api/media`);
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

  // Helper to stabilize and capture
  async function capture(filename, action) {
    console.log(`  -> Capturing ${filename}...`);
    if (action) {
      await action();
    }
    await page.waitForTimeout(600);
    const outPath = path.join(OUT_DIR, filename);
    await page.screenshot({ path: outPath, fullPage: false });
    console.log(`  ✓ Saved ${outPath}`);
  }

  // 1. 01_home.png (Главная с карточками и открытым поповером «Сколько есть времени?»)
  await capture("01_home.png", async () => {
    await page.goto(`${BASE_URL}/?view=home`, { waitUntil: "networkidle" });
    await page.waitForTimeout(800);
    // Open time budget popover
    const popoverBtn = page.locator('button[title*="времени"], button[aria-label*="времени"], button:has-text("Сколько есть времени")').first();
    if (await popoverBtn.isVisible().catch(() => false)) {
      await popoverBtn.click();
      await page.waitForTimeout(500);
    }
  });

  // 2. 02_category_anime.png (Категория с FilterBar и сеткой)
  await capture("02_category_anime.png", async () => {
    await page.goto(`${BASE_URL}/?view=anime`, { waitUntil: "networkidle" });
    await page.waitForTimeout(800);
  });

  // 3. 03_detail_overview.png (Карточка медиа: Обзор, сайдбар, прогресс, персонажи, внешние источники)
  await capture("03_detail_overview.png", async () => {
    await page.goto(`${BASE_URL}/?view=detail&mediaId=${frierenId}`, { waitUntil: "networkidle" });
    await page.waitForTimeout(800);
  });

  // 4. 04_detail_episodes.png (Вкладка «Эпизоды»)
  await capture("04_detail_episodes.png", async () => {
    // Click on "Эпизоды" tab
    const episodesTab = page.locator('button:has-text("Эпизоды")').first();
    if (await episodesTab.isVisible().catch(() => false)) {
      await episodesTab.click();
      await page.waitForTimeout(600);
    }
  });

  // 5. 05_edit_workspace.png (Пространственный редактор с ниточками)
  await capture("05_edit_workspace.png", async () => {
    // On detail view, click Edit button in sidebar
    const editBtn = page.locator('button:has-text("Редактировать")').first();
    if (await editBtn.isVisible().catch(() => false)) {
      await editBtn.click();
      await page.waitForTimeout(1000);
    } else {
      // fallback: open create from sidebar
      const addBtn = page.locator('button:has-text("+ Добавить")').first();
      await addBtn.click();
      await page.waitForTimeout(1000);
    }
  });

  // 6. 06_search_modal.png (Модалка внешнего поиска с результатами)
  await capture("06_search_modal.png", async () => {
    // Press Escape to close edit workspace first
    await page.keyboard.press("Escape");
    await page.waitForTimeout(400);
    await page.goto(`${BASE_URL}/?view=home`, { waitUntil: "networkidle" });
    await page.waitForTimeout(500);
    // Open search modal via header button or Ctrl+K
    await page.keyboard.press("Control+k");
    await page.waitForTimeout(500);
    const searchInput = page.locator('input[placeholder*="Поиск"], input[type="search"]').first();
    if (await searchInput.isVisible().catch(() => false)) {
      await searchInput.fill("Frieren");
      await page.waitForTimeout(1200); // debounce and network request
    }
  });

  // Close search modal
  await page.keyboard.press("Escape");
  await page.waitForTimeout(400);

  // 7. 07_settings_sources.png (Настройки → Источники)
  await capture("07_settings_sources.png", async () => {
    await page.goto(`${BASE_URL}/?view=settings`, { waitUntil: "networkidle" });
    await page.waitForTimeout(600);
    const tab = page.locator('button:has-text("Источники")').first();
    if (await tab.isVisible().catch(() => false)) {
      await tab.click();
      await page.waitForTimeout(500);
    }
  });

  // 8. 08_settings_import.png (Настройки → Импорт)
  await capture("08_settings_import.png", async () => {
    const tab = page.locator('button:has-text("Импорт")').first();
    if (await tab.isVisible().catch(() => false)) {
      await tab.click();
      await page.waitForTimeout(500);
    }
  });

  // 9. 09_settings_appearance.png (Настройки → Внешний вид)
  await capture("09_settings_appearance.png", async () => {
    const tab = page.locator('button:has-text("Внешний вид")').first();
    if (await tab.isVisible().catch(() => false)) {
      await tab.click();
      await page.waitForTimeout(500);
    }
  });

  // 10. 10_settings_storage.png (Настройки → Хранилище / Поиск / Бэкап)
  await capture("10_settings_storage.png", async () => {
    const tab = page.locator('button:has-text("Хранилище")').first();
    if (await tab.isVisible().catch(() => false)) {
      await tab.click();
      await page.waitForTimeout(500);
    }
  });

  // 11. 11_stats.png (Статистика: Сводка + Taste Profile)
  await capture("11_stats.png", async () => {
    await page.goto(`${BASE_URL}/?view=stats`, { waitUntil: "networkidle" });
    await page.waitForTimeout(800);
  });

  // 12. 12_lists.png
  await capture("12_lists.png", async () => {
    await page.goto(`${BASE_URL}/?view=lists`, { waitUntil: "networkidle" });
    await page.waitForTimeout(800);
  });

  // 13. 13_history.png
  await capture("13_history.png", async () => {
    await page.goto(`${BASE_URL}/?view=history`, { waitUntil: "networkidle" });
    await page.waitForTimeout(800);
  });

  // 14. 14_calendar.png
  await capture("14_calendar.png", async () => {
    await page.goto(`${BASE_URL}/?view=calendar`, { waitUntil: "networkidle" });
    await page.waitForTimeout(800);
  });

  // 15. 15_goals.png
  await capture("15_goals.png", async () => {
    await page.goto(`${BASE_URL}/?view=goals`, { waitUntil: "networkidle" });
    await page.waitForTimeout(800);
  });

  await browser.close();
  console.log("🎉 All 15 Svelte screenshots captured successfully!");
}

run().catch((err) => {
  console.error("Capture failed:", err);
  process.exit(1);
});
