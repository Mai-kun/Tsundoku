import { chromium } from 'playwright';
import sharp from 'sharp';
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import dotenv from 'dotenv';
import { ensureTestServer } from '../mediatracker-ui/checks/harness/testServerHarness.ts';
import { ProxyAgent, fetch as undiciFetch } from 'undici';
import { execSync } from 'node:child_process';

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const ROOT_DIR = path.resolve(__dirname, '..');
const REPORTS_DIR = path.resolve(ROOT_DIR, 'reports');
const SCREENSHOTS_DIR = path.resolve(REPORTS_DIR, 'screenshots');
const SKILL_FILE = path.resolve(ROOT_DIR, 'SKILL.md');

// Загрузка .env
for (const envPath of [path.resolve(ROOT_DIR, '.env'), path.resolve(process.cwd(), '.env')]) {
  if (fs.existsSync(envPath)) {
    dotenv.config({ path: envPath });
    break;
  }
}

async function runReview() {
  const apiKey = process.env.GEMINI_API_KEY;
  if (!apiKey) {
    console.log('ℹ️ [AI-Review] GEMINI_API_KEY не обнаружен. Пропуск AI-ревью.');
    process.exit(0);
  }

  const proxyUrl = process.env.HTTPS_PROXY || process.env.https_proxy || process.env.HTTP_PROXY || process.env.http_proxy || process.env.ALL_PROXY || process.env.all_proxy;
  const dispatcher = proxyUrl ? new ProxyAgent({ uri: proxyUrl, headersTimeout: 120_000, bodyTimeout: 120_000 }) : undefined;

  if (dispatcher) {
    try {
      const ipCheck = await undiciFetch('https://api.ipify.org?format=json', { dispatcher });
      const { ip } = await ipCheck.json();
      console.log(`🌐 [AI-Review] Прокси активен! Входящий IP для Google: ${ip}`);
    } catch (err) {
      console.warn(`⚠️ [AI-Review] Внимание: не удалось проверить IP через прокси: ${err.message}`);
    }
  }

  if (!fs.existsSync(SCREENSHOTS_DIR)) fs.mkdirSync(SCREENSHOTS_DIR, { recursive: true });
  const harness = await ensureTestServer();
  const browser = await chromium.launch({ headless: true });

  const screens = [
    { name: '01-home-desktop.png', path: '/', width: 1440, height: 900 },
    { name: '02-category-game-desktop.png', path: '/?view=game', width: 1440, height: 900 },
    { name: '03-detail-desktop.png', path: harness.seededIds?.gameId ? `/?view=detail&mediaId=${harness.seededIds.gameId}` : '/?view=game', width: 1440, height: 900 },
    { name: '04-stats-summary-desktop.png', path: '/?view=stats', width: 1440, height: 900 },
    { name: '06-lists-desktop.png', path: '/?view=lists', width: 1440, height: 900 },
    { name: '07-history-desktop.png', path: '/?view=history', width: 1440, height: 900 },
    { name: '08-calendar-desktop.png', path: '/?view=calendar', width: 1440, height: 900 },
    { name: '12-home-mobile.png', path: '/', width: 390, height: 844 },
  ];

  for (const screen of screens) {
    const context = await browser.newContext({ viewport: { width: screen.width, height: screen.height } });
    const page = await context.newPage();
    await page.emulateMedia({ reducedMotion: 'reduce' });
    try {
      await page.goto(`${harness.baseUrl}${screen.path}`, { waitUntil: 'networkidle' });
      await page.waitForTimeout(1000);
      await page.screenshot({ path: path.join(SCREENSHOTS_DIR, screen.name) });
      console.log(`📸 [AI-Review] Скриншот: ${screen.name}`);
    } catch (e) {
      console.warn(`⚠️ [AI-Review] Не удалось снять скриншот ${screen.name}: ${e.message}`);
    } finally {
      await context.close();
    }
  }
  await browser.close();
  await harness.stop();

  const files = fs.readdirSync(SCREENSHOTS_DIR).filter(f => f.endsWith('.png')).sort();
  if (files.length === 0) {
    console.error('❌ [AI-Review] Нет скриншотов для анализа.');
    process.exit(1);
  }

  const skillRules = fs.existsSync(SKILL_FILE) ? fs.readFileSync(SKILL_FILE, 'utf8') : '';
  const promptText = `Ты — ведущий UI/UX дизайнер и арт-директор. Проведи строгое дизайн-ревью приложения Tsundoku по предоставленным скриншотам и правилам дизайн-системы из приложенного SKILL.md.
  Правила дизайна:
  ${skillRules}
  
  Проанализируй: 1) Визуальную иерархию и акценты; 2) Баланс отступов и плотность информации; 3) Читаемость и типографику в темной теме; 4) Мобильную адаптивность; 5) Дай 3-5 конкретных практических советов по улучшению внешнего вида (какой элемент изменить и как).`;

  const parts = [{ text: promptText }];

  console.log('🗜️ [AI-Review] Сжатие скриншотов для отправки в Gemini...');
  for (const file of files) {
    const filePath = path.join(SCREENSHOTS_DIR, file);
    const optimizedBuffer = await sharp(filePath)
      .resize({ width: 1280, withoutEnlargement: true })
      .jpeg({ quality: 75 })
      .toBuffer();

    parts.push({
      inlineData: {
        mimeType: 'image/jpeg',
        data: optimizedBuffer.toString('base64')
      }
    });
  }
  console.log(`📦 [AI-Review] Подготовлено ${files.length} оптимизированных изображений.`);

  // Выбор модели
  let activeModel = 'models/gemini-2.0-flash';
  try {
    const listRes = await undiciFetch(`https://generativelanguage.googleapis.com/v1beta/models?key=${apiKey}`, { dispatcher });
    const listData = await listRes.json();
    if (listData.models && Array.isArray(listData.models)) {
      const available = listData.models.filter(m => m.supportedGenerationMethods?.includes('generateContent'));
      const preferred = available.find(m => m.name.includes('gemini-2.0-flash'))
                     || available.find(m => m.name.includes('flash') && !m.name.includes('1.5'))
                     || available[0];
      if (preferred) activeModel = preferred.name;
    }
  } catch (e) {
    console.warn(`⚠️ [AI-Review] Пропуск списка моделей: ${e.message}`);
  }

  console.log(`🤖 [AI-Review] Отправка скриншотов в ${activeModel}...`);
  const modelPath = activeModel.startsWith('models/') ? activeModel : `models/${activeModel}`;
  const generateUrl = `https://generativelanguage.googleapis.com/v1beta/${modelPath}:generateContent?key=${apiKey}`;

  let reviewText = null;
  try {
    const response = await undiciFetch(generateUrl, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ contents: [{ role: 'user', parts }] }),
      dispatcher
    });

    const data = await response.json();
    if (!response.ok) {
      throw new Error(`Google API вернул ${response.status}: ${JSON.stringify(data.error || data)}`);
    }

    reviewText = data.candidates?.[0]?.content?.parts?.[0]?.text;
    if (reviewText) {
      console.log(`✅ [AI-Review] Рецензия успешно получена от ${modelPath}!`);
    }
  } catch (err) {
    console.warn(`⚠️ [AI-Review] Ошибка вызова Gemini: ${err.message}`);
  }

  if (reviewText) {
    fs.writeFileSync(path.resolve(REPORTS_DIR, 'ai-ui-review.json'), JSON.stringify({ review: reviewText, screenshots: files }, null, 2));
    try {
      execSync('node scripts/generate-audit-report.mjs', { stdio: 'inherit' });
    } catch (e) {
      console.error('❌ Ошибка generate-audit-report.mjs:', e.message);
    }
  }
}

runReview().catch(console.error);
