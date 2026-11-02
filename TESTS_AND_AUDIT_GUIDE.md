# 📖 Полное руководство по тестированию, аудиту и оптимизации Tsundoku

В проекте Tsundoku развернута многоуровневая автономная система контроля качества, производительности, безопасности и доступности. Все проверки работают в headless/CLI режиме и запускаются как через оркестратор `task` (Go Task), так и через `npm`.

---

## 📑 Оглавление
1. [Архитектурный обзор (Fast Path vs Deep Audit)](#1-архитектурный-обзор)
2. [Главные команды оркестрации (Taskfile и NPM)](#2-главные-команды-оркестрации)
3. [Сводная таблица всех проверочных контуров и скриптов](#3-сводная-таблица-всех-проверочных-контуров-и-скриптов)
4. [Быстрый контур качества и автофикса (`task fix`)](#4-быстрый-контур-качества-и-автофикса)
5. [Статические проверки и линтеры](#5-статические-проверки-и-линтеры)
6. [Браузерный контур CDP, Web Vitals & Playwright](#6-браузерный-контур-cdp-web-vitals--playwright)
7. [Функциональные E2E сценарии Playwright (`checks/e2e`)](#7-функциональные-e2e-сценарии-playwright-checkse2e)
8. [Автономные компонентные проверки UI (`checks/`)](#8-автономные-компонентные-проверки-ui-checks)
9. [Бэкенд и База данных (.NET 10 + BenchmarkDotNet + SQLite)](#9-бэкенд-и-база-данных-net-10--benchmarkdotnet--sqlite)
10. [Многоуровневый аудит безопасности](#10-многоуровневый-аудит-безопасности)
11. [Визуальный регрессионный контроль (BackstopJS)](#11-визуальный-регрессионный-контроль-backstopjs)
12. [Стресс-тестирование на 25k/500k элементов](#12-стресс-тестирование-на-25k500k-элементов)
13. [AI UI/UX ревью интерфейса (Google Gemini Vision)](#13-ai-uiux-ревью-интерфейса-google-gemini-vision)
14. [Руководство по настройке правил и бюджетов](#14-руководство-по-настройке-правил-и-бюджетов)

---

## 1. Архитектурный обзор

Пайплайн разделен на два взаимодополняющих контура:

1. **Быстрый контур (Fast Path / `task fix` / `npm run fix`) — ~10-14 секунд**:
   - Автоматическое форматирование исходников (Prettier, `dotnet format`).
   - Автофикс антипаттернов верстки (De-slop) и микрооптимизаций C# (добавление забытых `.AsNoTracking()`).
   - Параллельный запуск 11 статических анализаторов без поднятия браузера и сервера:
     - TypeScript strict checks (`svelte-check` + `tsc`).
     - ESLint 9 (TypeScript & Svelte 5).
     - Stylelint с запретом layout thrashing и принудительными аппаратными свойствами (GPU transform/opacity).
     - HTML-Validate (семантический стандарт DOM).
     - Инспектор приглушённой палитры `check:colors` (защита матовой графитовой темы Obsidian от кислотных hex-цветов вне дизайн-токенов).
     - Контроль `$state.raw` в коллекциях Svelte 5 (исключение оверхеда Deep Proxy).
     - Проверка пространств имен Performance Marks (`tsundoku:*`).
     - Поиск мертвого кода и неиспользуемых экспортов (`knip`).
     - Детектор хардкода кириллицы в компонентах (`check:i18n`).
     - Проверка целостности кодировки файлов и BOM (`check:leading-chars`).
     - Инспектор сиротских файлов проверок (`check:orphans`).
   - Быстрый C# `--selfcheck` (проверка DI, миграций и планов SQLite `EXPLAIN QUERY PLAN`).

2. **Глубокий контур (Deep Audit / `task audit` / `npm run audit`) — ~1.5–2 минуты**:
   - Автоматический запуск быстрого контура `task fix`.
   - Изолированное поднятие тестового сервера на случайном порту с временной БД.
   - Сборка фронтенда с контролем бюджетов чанков Vite (`< 115 KB` Gzip entry).
   - Запуск консолидированного браузерного комбайна `checks/audit/browserSuite.runner.ts`:
     - CDP-метрики (Layout, Recalc Style, DOM Nodes, JS Heap).
     - Тест утечек памяти JS Heap (12 циклов навигации с Force GC).
     - Геометрия DOM, коллизии и Fitts' law tap targets.
     - Доступность Axe WCAG 2.1 AA.
     - Попиксельные снапшоты Pixelmatch ключевых виджетов.
     - Google Core Web Vitals (LCP, CLS, FID, FCP).
   - Аудит UI Jank и Long Tasks (>50ms) при интеракциях + 144Hz framerate (`checks/e2e/jankAudit.check.ts`).
   - Прогон C# тестов xUnit с покрытием Coverlet и фронтенд-тестов Vitest (v8).
   - Сетевой замер wire payloads и сжатия API Gzip/Brotli на 500 элементах.
   - Аудит фрагментации SQLite, freelist страниц и WAL checkpoint.
   - Микропрофилирование алгоритмов (`BenchmarkDotNet`) и макропрофилирование ASP.NET Core под нагрузкой (`dotnet-trace`).
   - Мультиуровневый аудит безопасности (NuGet CVEs, NPM production audit, Secret scan).
   - **Умное кэширование**: если C#-код не менялся, повторный аудит занимает ~40 секунд благодаря валидации SHA-256 хэшей в `reports/.cache-manifest.json`.
   - Генерация единого Markdown-отчета `AUDIT_REPORT.md` и HTML-дашборда `AUDIT_REPORT.html`.

---

## 2. Главные команды оркестрации

Запуск возможен как через утилиту `task` (Go Task), так и через `npm` из корня проекта:

| Команда Task | Команда NPM | Описание |
| :--- | :--- | :--- |
| `task fix` | `npm run fix` | Автоформатирование, автофикс и запуск всех 11 статических чеков (~10-14 сек) |
| `task test` | `npm test` | Прогон всех тестов бэкенда (xUnit) и фронтенда (Vitest) со сбором покрытия |
| `task audit` | `npm run audit` | Полный глубокий сквозной аудит системы с генерацией итоговых отчетов |
| — | `npm run audit -- --with-ai` | Полный аудит + автоматический запуск визуального AI UI/UX ревью через Gemini |
| `task browser-suite` | `npm run check:browser-suite` | Запуск комбайна браузерного аудита (CDP, геометрия, a11y, snapshots, Web Vitals) |
| `task check:jank` | `npm run check:jank` | Детекция Long Tasks (>50ms) и аудит плавности 144Hz при интеракциях |
| `task check:orphans`| `npm run check:orphans` | Проверка отсутствия сиротских тестовых файлов на диске |
| `task visual` | `npm run visual` | Сверка визуальных сценариев BackstopJS (Mobile, Tablet, Desktop) |
| `task visual:approve` | `npm run visual:approve` | Принятие текущих скриншотов как эталонов для BackstopJS |
| `task report` | `npm run report` | Перегенерация `AUDIT_REPORT.md` и `AUDIT_REPORT.html` по имеющимся артефактам |
| `task security` | `npm run security` | Аудит уязвимостей (NuGet, NPM prod) и сканирование утечек приватных ключей |
| `task stress` | `npm run test:stress` | Стресс-тест виртуального скролла и базы на 25 000 элементов на 144 FPS |
| `task smells` | `npm run smells` | Инспектор микрооптимизаций C# и Svelte с формированием diff-подсказок |
| — | `npm run review:ai` | Автономный запуск захвата скриншотов и отправка на дизайн-ревью в Gemini |

---

## 3. Сводная таблица всех проверочных контуров и скриптов

### 3.1. Скрипты оркестрации и инфраструктуры (`scripts/`)

| Скрипт / Утилита | Расположение | Команда запуска | Поддерживаемые флаги и аргументы | Генерируемый артефакт в `reports/` |
| :--- | :--- | :--- | :--- | :--- |
| **Audit Runner** | `scripts/audit-runner.mjs` | `node scripts/audit-runner.mjs [cmd]` | `fix`, `test`, `audit`, `security`, `visual`, `visual:approve`, `report`<br>`--with-ai` (включает вызов Gemini Vision при аудите) | Консолидирует запуск и валидирует артефакты; обновляет `reports/.cache-manifest.json` |
| **Report Generator** | `scripts/generate-audit-report.mjs` | `node scripts/generate-audit-report.mjs` | Без аргументов. Считывает все `reports/*.json` | `AUDIT_REPORT.md`, `AUDIT_REPORT.html` |
| **Code Smells Inspector** | `scripts/inspect-code-smells.mjs` | `node scripts/inspect-code-smells.mjs` | `--fix` (автоматически применяет исправления микрооптимизаций в коде C# и Svelte) | `reports/code-smells.json` |
| **SQLite Health** | `scripts/inspect-sqlite-health.mjs` | `node scripts/inspect-sqlite-health.mjs` | `[dbPath]` (опциональный путь к файлу БД, по умолчанию `tracker.dev.db`) | `reports/sqlite-health.json` |
| **API Payloads Profiler** | `scripts/measure-api-payloads.mjs` | `node --experimental-strip-types scripts/measure-api-payloads.mjs` | Переменная окружения `TS_BASE` (URL работающего сервера; если не задан — поднимает изолированный) | `reports/api-payloads.json` |
| **Backend Coverage Parser**| `scripts/parse-backend-coverage.mjs` | `node scripts/parse-backend-coverage.mjs` | Без аргументов. Фильтрует зависимости и парсит Cobertura XML | `reports/backend-coverage.json` |
| **Frontend Coverage Parser**| `scripts/parse-frontend-coverage.mjs` | `node scripts/parse-frontend-coverage.mjs` | Без аргументов. Парсит Vitest v8 coverage | `reports/frontend-coverage.json` |
| **Backend Macroprofiler** | `scripts/profile-backend.mjs` | `node scripts/profile-backend.mjs` | `--gcdump` (собирает снимок кучи `.gcdump` наряду со SpeedScope трейсом) | `reports/backend-profile-summary.json`, `reports/trace/*.nettrace` |
| **BenchmarkDotNet Runner** | `scripts/run-benchmarks.mjs` | `node scripts/run-benchmarks.mjs` | `--skip-run` (пропускает выполнение и парсит существующие логи бенчмарков) | `reports/benchmarks-summary.json`, `reports/sqlite-query-plans.json` |
| **Multi-layer Security** | `scripts/security-audit.mjs` | `node scripts/security-audit.mjs` | Без аргументов. Сканирует NuGet, NPM prod, регулярки секретов | `reports/security-audit.json` |
| **144Hz Stress Tester** | `scripts/stress-test.mjs` | `node scripts/stress-test.mjs` | `--count=<N>` (количество элементов, по умолчанию 25000)<br>`--headless` (запуск без GUI)<br>`--port=<N>` (порт тестового сервера) | `reports/stress/result-*.json` |
| **AI UI/UX Review** | `scripts/ai-ui-review.mjs` | `node scripts/ai-ui-review.mjs` | Переменные окружения: `GEMINI_API_KEY`, `HTTP_PROXY`, `HTTPS_PROXY` | `reports/ai-ui-review.json` |

---

### 3.2. Статический контур и линтеры (`mediatracker-ui/`)

| Проверка | Расположение | Команда запуска | Поддерживаемые флаги и аргументы | Генерируемый артефакт в `reports/` |
| :--- | :--- | :--- | :--- | :--- |
| **Инспектор палитры** | `checks/static/checkMutedColors.check.ts` | `npm run check:colors` | Без аргументов. Сканирует `src/**/*.{svelte,css}` на кислотные hex и яркие bg-заливки | `reports/muted-colors.json` |
| **Детектор сирот** | `checks/static/orphanChecks.check.ts` | `npm run check:orphans` | `--strict` (завершает процесс с кодом 1 при обнаружении сирот) | `reports/orphan-checks.json` |
| **De-slop & UI Math** | `checks/deslopAndUiMath.check.ts` | `npm run check:deslop` | `--fix` (автоматически исправляет произвольные отступы и inline-стили) | `reports/deslop-summary.json` |
| **HTML Validate** | `checks/htmlValidate.check.ts` | `npm run check:html` | `--fix` (автоматически исправляет форматирование тегов) | `reports/html-validate.json` |
| **Svelte 5 $state.raw** | `checks/stateRaw.check.ts` | `npm run check:state-raw` | Без аргументов. Проверяет коллекции на отсутствие Deep Proxy | Вывод в консоль |
| **Bundle Budget** | `checks/bundleBudget.check.ts` | `npm run check:bundle` | `BUDGET_ENTRY_JS_GZIP_KB`, `BUDGET_TOTAL_JS_GZIP_KB`, `BUDGET_CSS_GZIP_KB` | `reports/bundle-summary.json`, `reports/bundle-stats.html` |
| **Хардкод i18n** | `checks/i18nHardcode.check.cjs` | `npm run check:i18n` | Без аргументов. Сканирует кириллические литералы вне словарей | Вывод в консоль |
| **Кодировки и BOM** | `checks/leadingChars.check.cjs` | `npm run check:leading-chars`| Без аргументов. Ищет BOM и поврежденные ANSI-символы | Вывод в консоль |
| **Perf Marks Namespaces**| `checks/perfMarks.check.ts` | `npm run check:perf-marks` | Без аргументов. Проверяет префикс `tsundoku:*` | Вывод в консоль |
| **Deadcode (Knip)** | `knip.json` | `npm run check:deadcode` | Флаги утилиты Knip | Вывод в консоль |
| **ESLint 9** | `eslint.config.js` | `npm run lint:es` | Стандартные флаги ESLint (`--fix`) | Вывод в консоль |
| **Stylelint** | `.stylelintrc.json` | `npm run lint:css` | Стандартные флаги Stylelint (`--fix`) | Вывод в консоль |
| **Prettier & De-slop** | `.prettierrc` | `npm run format:fix` | Без аргументов. Форматирует весь код и правит de-slop | Форматирование на месте |
| **Svelte Check & TS** | `tsconfig.app.json` | `npm run check` | Без аргументов (`svelte-check` + `tsc`) | Вывод в консоль |

---

### 3.3. Браузерный аудит и CDP-профилирование (`checks/audit/`)

| Проверка | Расположение | Команда запуска | Поддерживаемые флаги и аргументы | Генерируемый артефакт в `reports/` |
| :--- | :--- | :--- | :--- | :--- |
| **Главный браузерный комбайн** | `checks/audit/browserSuite.runner.ts` | `npm run check:browser-suite` | Запускает фазы 1-6 последовательно в одном изолированном браузере | `reports/browser-suite-summary.json` |
| **CDP Profiler** | `checks/audit/cdpProfiler.check.ts` | `npm run check:cdp` | Замеряет Layout, Recalc, DOM Nodes, JS Heap и утечки памяти (12 циклов) | `reports/cdp-performance.json` |
| **Layout Geometry** | `checks/audit/layoutGeometry.check.ts` | `npm run check:geometry` | Проверяет горизонтальный скролл, коллизии и Fitts' law на 3 брейкпоинтах | `reports/layout-geometry.json` |
| **Axe Accessibility**| `checks/audit/axeAccessibility.check.ts` | `npm run check:a11y` | Сканирует WCAG 2.1 AA нарушения (critical и serious) | `reports/axe-accessibility.json` |
| **Visual Snapshots** | `checks/audit/visualSnapshots.check.ts` | `npm run check:snapshots` | `--update` (обновляет эталонные PNG-снапшоты в `checks/harness/__snapshots__/`)<br>`UPDATE_SNAPSHOTS=true` | `reports/visual-snapshots.json`, `reports/visual-diffs/*.png` |
| **Core Web Vitals** | `checks/audit/webVitals.check.ts` | `npm run check:web-vitals` | Замеряет LCP, CLS, FID, FCP в реальных сценариях взаимодействия | `reports/web-vitals.json` |
| **BackstopJS Runner**| `checks/audit/runBackstop.ts` | `npm run visual:test`<br>`npm run visual:approve` | `test` (прогон регресса)<br>`reference` / `approve` (сохранение эталонов) | `reports/backstop-summary.json`, `reports/backstop_data/html_report/` |

---

### 3.4. E2E сценарии и Jank-аудит (`checks/e2e/`)

Все сценарии поддерживают переменные окружения:
- `TS_BASE` или `TARGET_URL`: базовый URL приложения (по умолчанию `http://localhost:5000` или поднимаемый изолированный тестовый сервер).
- `TS_BROWSER_CHANNEL`: указание браузера (например, `chromium`, `msedge`).

| Команда | Файл проверки | Проверяемый сценарий | Артефакт |
| :--- | :--- | :--- | :--- |
| `npm run check:jank` | `checks/e2e/jankAudit.check.ts` | Детекция Long Tasks (>50ms) при интеракциях и 144Hz rAF micro-jank | `reports/jank-audit.json` |
| `npm run check:achievements-buttons` | `checks/e2e/achievementsButtons.check.ts` | Интерактивные кнопки достижений в карточках игр | Консоль |
| `npm run check:cards` | `checks/e2e/cards.check.ts` | Рендеринг всех типов карточек медиа, степперы прогресса, ховер-префетч | Консоль |
| `npm run check:category-switch` | `checks/e2e/categorySwitch.check.ts` | Мгновенное переключение категорий (Anime, Manga, Games, Movies, TV) | Консоль |
| `npm run check:diag-scenarios` | `checks/e2e/diagScenarios.check.ts` | Стресс-фильтрация, комбинированные фильтры и навигация | Консоль |
| `npm run check:external-sources` | `checks/e2e/externalSources.check.ts` | Работа внешних провайдеров метаданных (AniList, Shikimori, RAWG, TMDB) | Консоль |
| `npm run check:game-payloads` | `checks/e2e/gamePayloads.check.ts` | Кэширование детальных пейлоадов игр и DLC | Консоль |
| `npm run check:history-delete` | `checks/e2e/historyDelete.check.ts` | Удаление записей хронологии и пересчет счетчиков | Консоль |
| `npm run check:jobs-queue` | `checks/e2e/jobsQueue.check.ts` | Очередь фоновых задач синхронизации и импорта | Консоль |
| `npm run check:lists` | `checks/e2e/lists.check.ts` | Создание, редактирование и фильтрация умных списков | Консоль |
| `npm run check:nav-detail` | `checks/e2e/navDetail.check.ts` | Переход в деталку тайтла, рендеринг аккордеонов и сезонов | Консоль |
| `npm run check:nav-overlap` | `checks/e2e/navOverlap.check.ts` | Проверка перекрытия элементов мобильным таббаром | Консоль |
| `npm run check:overview-ladder` | `checks/e2e/overviewLadder.check.ts` | Двухколоночный макет Overview и расчет высоты колонок | Консоль |
| `npm run check:popover` | `checks/e2e/popover.check.ts` | Позиционирование и закрытие поповера статуса | Консоль |
| `npm run check:ratings-settled` | `checks/e2e/ratingsSettled.check.ts` | Расчет и отображение агрегированного рейтинга | Консоль |
| `npm run check:regression-fixes` | `checks/e2e/regressionFixes.check.ts` | Проверка регрессионных правок в редактировании тайтла | Консоль |
| `npm run check:related` | `checks/e2e/related.check.ts` | Франшизы, сиквелы/приквелы и связанные медиа | Консоль |
| `npm run check:release-dates` | `checks/e2e/releaseDates.check.ts` | Отображение дат выхода и онгоингов | Консоль |
| `npm run check:relink` | `checks/e2e/relink.check.ts` | Смена источника метаданных (перепривязка ID) | Консоль |
| `npm run check:score-stack` | `checks/e2e/scoreStack.check.ts` | Стекинг бейджей рейтинга на постерах | Консоль |
| `npm run check:search-modal` | `checks/e2e/searchModal.check.ts` | Модальное окно глобального поиска (`Ctrl+K`) | Консоль |
| `npm run check:seasons` | `checks/e2e/seasons.check.ts` | Раскрытие аккордеонов сезонов и серий сериалов | Консоль |
| `npm run check:tokens` | `checks/e2e/tokens.check.ts` | Валидация вычисленных значений CSS-токенов темы | Консоль |
| `npm run check:tools-and-search` | `checks/e2e/toolsAndSearch.check.ts` | Инструменты пакетной обработки и расширенный поиск | Консоль |
| `npm run check:virtual-grid` | `checks/e2e/virtualGrid.check.ts` | Динамический виртуальный скроллинг сетки (TanStack Virtual) | Консоль |
| `npm run check:visual-qa` | `checks/e2e/visualQa.check.ts` | Сквозной визуальный проход по всем страницам. Флаг: `[scenarioName]` | Консоль |

---

### 3.5. Автономные компонентные проверки (`checks/`)

| Команда | Файл проверки | Назначение |
| :--- | :--- | :--- |
| `npm run check:chronicle` | `checks/chronicleTimeline.check.ts` | Логика группировки и сортировки хронологии просмотров |
| `npm run check:client-errors` | `checks/clientErrors.check.ts` | Перехват необработанных ошибок в клиенте и отображение тостов |
| `npm run check:cover` | `checks/coverUrl.check.ts` | Валидация URL обложек, фоллбэков и проксирования изображений |
| `npm run check:detailed-score` | `checks/detailedScore.check.ts` | Форматирование и округление детального скоринга |
| `npm run check:external-mapping` | `checks/externalMapping.check.ts` | Маппинг внешних сущностей AniList/TMDB в модель Tsundoku |
| `npm run check:prefetch` | `checks/prefetchCache.check.ts` | Кэш предзагрузки метаданных при наведении курсора |
| `npm run check:related-matching`| `checks/relatedMatching.check.ts` | Алгоритм сопоставления связанных тайтлов |
| `npm run check:series-step` | `checks/seriesStep.check.ts` | Логика инкремента эпизодов и завершения сезона |
| `npm run check:stale` | `checks/staleTriage.check.ts` | Сортировка и фильтрация заброшенных тайтлов |
| `npm run check:time-budget` | `checks/timeBudget.check.ts` | Расчет затраченного времени на медиа (часы/минуты) |
| `npm run check:virtual-grid-rows` | `checks/virtualGridRows.check.ts` | Математика расчета колонок и рядов виртуального грида |

---

## 4. Быстрый контур качества и автофикса

Запуск:
```bash
task fix
# или
npm run fix
```

Включает:
1. `check:orphans` — гарантия, что ни один проверочный файл не забыт.
2. `inspect-code-smells.mjs --fix` — автофикс микрооптимизаций C# (например, добавление `.AsNoTracking()`).
3. `format:fix` — форматирование Prettier + автофикс De-slop верстки.
4. `dotnet format` — форматирование C#-кода.
5. Параллельный запуск 11 проверок:
   - `check` (TypeScript strict)
   - `lint:es` (ESLint 9)
   - `lint:css` (Stylelint GPU)
   - `check:html` (HTML-Validate)
   - `check:colors` (инспектор приглушённой палитры)
   - `check:deslop` (AST De-slop)
   - `check:state-raw` (Svelte 5 reactivity)
   - `check:perf-marks` (Performance Marks)
   - `check:deadcode` (Knip)
   - `check:i18n` (поиск хардкода кириллицы)
   - `check:leading-chars` (целостность BOM/ANSI)
6. `dotnet run ... -- --selfcheck` — быстрая внутренняя самодиагностика сервера.

---

## 5. Статические проверки и линтеры

### Инспектор приглушённой палитры (`check:colors`)
- **Файл:** `mediatracker-ui/checks/static/checkMutedColors.check.ts`
- **Команда:** `npm run check:colors` (или `task fix`)
- **Назначение:** Следит за соблюдением строгой матовой эстетики Obsidian Dark Canvas (`#0d0f14`). Запрещает использование «кислотных» (неоновых) hex-значений вне `src/app/tokens.css` и неподавленных ярких Tailwind-заливок без прозрачности или модификаторов (`hover:`, `/10` и т.д.).
- **Артефакт:** `reports/muted-colors.json`.

### Детектор сиротских скриптов (`check:orphans`)
- **Файл:** `mediatracker-ui/checks/static/orphanChecks.check.ts`
- **Команда:** `npm run check:orphans` (поддерживает флаг `--strict`)
- **Назначение:** Сканирует все проверочные скрипты на диске (`*.check.ts`, `*.check.cjs`, `*.runner.ts`, `scripts/*.mjs`) и сверяет их регистрацию в `Taskfile.yml`, `package.json` и контурах исполнения. Должно быть строго **0 сирот**.
- **Артефакт:** `reports/orphan-checks.json`.

---

## 6. Браузерный контур CDP, Web Vitals & Playwright

### Консолидированный комбайн (`check:browser-suite`)
- **Файл:** `mediatracker-ui/checks/audit/browserSuite.runner.ts`
- **Команда:** `npm run check:browser-suite` (или `task browser-suite`)
- **Фазы исполнения:**
  1. **Lazy Chunks:** проверка загрузки бандла и асинхронных чанков.
  2. **CDP Profiler:** замер Layout, Recalc Style, DOM Nodes, JS Heap и 12 циклов навигации с Force GC.
  3. **Layout Geometry:** коллизии, горизонтальный скролл, законы Фиттса.
  4. **Axe Accessibility:** аудит доступности WCAG 2.1 AA.
  5. **Visual Snapshots:** попиксельная сверка компонентов через Pixelmatch.
  6. **Core Web Vitals:** сбор LCP, CLS, FID, FCP через PerformanceObserver.
- **Артефакты:** `reports/browser-suite-summary.json`, `reports/cdp-performance.json`, `reports/layout-geometry.json`, `reports/axe-accessibility.json`, `reports/visual-snapshots.json`, `reports/web-vitals.json`.

### UI Jank & 144Hz Frame Budget (`check:jank`)
- **Файл:** `mediatracker-ui/checks/e2e/jankAudit.check.ts`
- **Команда:** `npm run check:jank` (или `task check:jank`)
- **Назначение:** Отслеживает Long Tasks (>50ms) при пользовательских взаимодействиях, а также выполняет rAF-сэмплирование для контроля бюджета кадра 144Hz (6.94 ms на кадр).
- **Артефакт:** `reports/jank-audit.json`.

---

## 7. Функциональные E2E сценарии Playwright (`checks/e2e`)

В каталоге `mediatracker-ui/checks/e2e/` сосредоточены 26 функциональных сценариев, проверяющих все ключевые пользовательские флоу (поиск `Ctrl+K`, редактирование тайтлов, фильтрация, виртуальная сетка, умные списки, интеграция с провайдерами). Все они запускаются изолированно или по отдельности через `npm run check:<name>`.

---

## 8. Автономные компонентные проверки UI (`checks/`)

В каталоге `mediatracker-ui/checks/` находятся 11 быстрых изолированных проверок бизнес-логики фронтенда (расчет времени, виртуализация строк, кэширование обложек, сопоставление франшиз). Они запускаются автономно и тестируют алгоритмическую корректность компонентов интерфейса.

---

## 9. Бэкенд и База данных (.NET 10 + BenchmarkDotNet + SQLite)

### Модульное и интеграционное тестирование
- **Команда:** `task test` / `npm test`
- **Бэкенд:** `MediaTracker.Tests/MediaTracker.Tests.csproj` (xUnit + Coverlet Cobertura).
- **Фронтенд:** `mediatracker-ui` (Vitest v8).
- **Артефакты:** `reports/backend-coverage.json`, `reports/frontend-coverage.json`.

### Микропрофилирование BenchmarkDotNet
- **Команда:** `task benchmarks` / `node scripts/run-benchmarks.mjs`
- **Флаг:** `--skip-run` (только парсинг существующих артефактов).
- **Артефакты:** `reports/benchmarks-summary.json`, `reports/sqlite-query-plans.json`.

### Макропрофилирование под нагрузкой
- **Команда:** `task profile-backend` / `node scripts/profile-backend.mjs`
- **Флаг:** `--gcdump` (сбор снимка памяти).
- **Артефакты:** `reports/backend-profile-summary.json`, `reports/trace/*.nettrace`.

### Здоровье и целостность SQLite
- **Команда:** `task sqlite-health` / `node scripts/inspect-sqlite-health.mjs`
- **Артефакт:** `reports/sqlite-health.json`.

### Замер сетевых пейлоадов API (Wire Efficiency)
- **Команда:** `task api-payloads` / `node --experimental-strip-types scripts/measure-api-payloads.mjs`
- **Артефакт:** `reports/api-payloads.json`.

---

## 10. Многоуровневый аудит безопасности

Запуск:
```bash
task security
# или
node scripts/security-audit.mjs
```

Проверяет:
1. **NuGet:** `dotnet list package --vulnerable` (.NET 10 зависимости).
2. **NPM:** `npm audit --omit=dev` (только production runtime-зависимости).
3. **Secret Scan:** регулярный поиск утекших API-ключей, токенов, приватных ключей и паролей в кодовой базе.
- **Артефакт:** `reports/security-audit.json`.

---

## 11. Визуальный регрессионный контроль (BackstopJS)

Запуск проверки:
```bash
task visual
# или
npm run visual
```

Утверждение новых эталонов:
```bash
task visual:approve
# или
npm run visual:approve
```

- **Конфигурация:** `mediatracker-ui/backstop.config.cjs`.
- **Эталоны:** `mediatracker-ui/checks/harness/backstop_data/bitmaps_reference/`.
- **Артефакты:** `reports/backstop-summary.json`, интерактивный HTML-отчет в `reports/backstop_data/html_report/index.html`.

---

## 12. Стресс-тестирование на 25k/500k элементов

Скрипт стресс-тестирования библиотеки и виртуального скролла на высоких частотах развертки (144 FPS):
```bash
# Базовый стресс-тест на 25k элементов
task stress
# или
node scripts/stress-test.mjs --count=25000

# Экстремальный стресс-тест на 500k элементов
node scripts/stress-test.mjs --count=500000 --headless
```

- **Флаги:**
  - `--count=<N>`: число элементов в библиотеке.
  - `--headless`: безголовый режим Chromium.
  - `--port=<N>`: порт тестового сервера.
- **Артефакт:** `reports/stress/result-<timestamp>.json`.

---

## 13. AI UI/UX ревью интерфейса (Google Gemini Vision)

Запуск:
```bash
npm run review:ai
# или в составе полного аудита:
npm run audit -- --with-ai
```

Делает полностраничные скриншоты всех экранов приложения и отправляет их в мультимодальную модель Google Gemini для экспертной оценки дизайна, типографики, акцентов и удобства использования.
- **Артефакт:** `reports/ai-ui-review.json`.

---

## 14. Руководство по настройке правил и бюджетов

| Область контроля | Файл конфигурации / проверки | Контролируемый бюджет |
| :--- | :--- | :--- |
| **JS/CSS бандл** | `mediatracker-ui/checks/bundleBudget.check.ts` | Entry JS ≤ 115 KB Gzip, Total JS ≤ 400 KB Gzip, CSS ≤ 35 KB Gzip |
| **CDP рендеринг** | `mediatracker-ui/checks/audit/cdpProfiler.check.ts` | Layout ≤ 120ms, Recalc ≤ 80ms, Nodes ≤ 1500, Heap Leak Delta < 15MB |
| **Core Web Vitals** | `mediatracker-ui/checks/audit/webVitals.check.ts` | LCP ≤ 1200ms, CLS ≤ 0.05, FID ≤ 50ms, FCP ≤ 600ms |
| **UI Jank (144Hz)** | `mediatracker-ui/checks/e2e/jankAudit.check.ts` | Long Tasks interaction = 0, P95 frame time ≤ 8.3ms, FPS ≥ 120 |
| **Палитра темы** | `mediatracker-ui/checks/static/checkMutedColors.check.ts` | 0 кислотных цветов вне `tokens.css`, приглушённые альфа-заливки |
| **Сетевые ответы**| `scripts/measure-api-payloads.mjs` | `/api/media` (500 items) Gzip ≤ 120 KB, средняя задержка ≤ 150ms |
| **SQLite БД** | `scripts/inspect-sqlite-health.mjs` | Фрагментация ≤ 15%, Freelist ≤ 100 страниц, Integrity: `ok` |
