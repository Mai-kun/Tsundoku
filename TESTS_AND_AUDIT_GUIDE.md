# 📖 Полное руководство по тестированию, аудиту и оптимизации Tsundoku

В проекте Tsundoku развернута многоуровневая автономная система контроля качества, производительности, безопасности и доступности. Все проверки работают в headless/CLI режиме и запускаются как через оркестратор `task` (Go Task), так и через `npm`.

---

## 📑 Оглавление
1. [Архитектурный обзор (Fast Path vs Deep Audit)](#1-архитектурный-обзор)
2. [Главные команды оркестрации (Taskfile и NPM)](#2-главные-команды-оркестрации)
3. [Каталог статических проверок и линтеров (checks/static)](#3-каталог-статических-проверок-и-линтеров)
4. [Каталог браузерного аудита и CDP-профилирования (checks/audit)](#4-каталог-браузерного-аудита-и-cdp-профилирования)
5. [Каталог функциональных E2E сценариев Playwright (checks/e2e)](#5-каталог-функциональных-e2e-сценариев-playwright)
6. [Тестирование и покрытие кода (C# xUnit + Vitest v8)](#6-тестирование-и-покрытие-кода)
7. [Глубокое профилирование бэкенда, БД и стресс-тесты (scripts/)](#7-глубокое-профилирование-бэкенда-бд-и-стресс-тесты)
8. [Визуальный регрессионный контроль (BackstopJS)](#8-визуальный-регрессионный-контроль)
9. [AI UI/UX ревью интерфейса (Google Gemini)](#9-ai-uiux-ревью-интерфейса)
10. [Руководство по настройке правил и бюджетов производительности](#10-руководство-по-настройке-правил-и-бюджетов)

---

## 1. Архитектурный обзор

Пайплайн разделен на два взаимодополняющих контура:

1. **Быстрый контур (Fast Path / `task fix` / `npm run fix`) — ~14 секунд**:
   - Автоматическое форматирование кода (Prettier, `dotnet format`).
   - Автофикс антипаттернов верстки (De-slop) и добавление забытых `.AsNoTracking()` в C#.
   - Параллельный запуск 12 статических анализаторов без поднятия браузера и сервера (TypeScript, ESLint 9, Stylelint с запретом layout thrashing, HTML-Validate, контроль `$state.raw`, симметрия словарей i18n, синхронность C# DTO и TS-типов, проверка сиротских тестов).
   - Быстрый C# `--selfcheck` (включая аудит планов запросов SQLite `EXPLAIN QUERY PLAN`).

2. **Глубокий контур (Deep Audit / `task audit` / `npm run audit`) — ~2 минуты**:
   - Изолированное поднятие тестового сервера на динамическом порту с временной SQLite базой данных.
   - Сборка фронтенда с контролем бюджетов чанков Vite (< 115 KB Gzip entry).
   - Запуск консолидированного Playwright-комбайна (CDP-метрики, тест утечек памяти с Force GC, геометрия DOM, доступность WCAG 2.1 AA, попиксельные снапшоты, Core Web Vitals).
   - Прогон C# тестов xUnit с покрытием Coverlet и фронтенд-тестов Vitest.
   - Микропрофилирование алгоритмов (`BenchmarkDotNet`) и макропрофилирование ASP.NET Core под нагрузкой (`dotnet-trace`).
   - Аудит фрагментации SQLite, сетевых ответов API и безопасности (CVE + Secret scan).
   - **Умное кэширование**: если C#-код не менялся, повторный аудит занимает всего ~1 минуту благодаря валидации SHA-256 хэшей исходников в `reports/.cache-manifest.json`.
   - Генерация отчетов `AUDIT_REPORT.md` и HTML-дашборда `reports/audit-report.html`.

---

## 2. Главные команды оркестрации

Запуск возможен как через утилиту `task` (Go Task), так и через `npm` из корня проекта:

| Команда через Task | Команда через NPM | Описание |
| :--- | :--- | :--- |
| `task fix` | `npm run fix` | Автоформатирование, автофикс и запуск всех статических чеков (~14 сек) |
| `task test` | `npm test` | Прогон всех 62 тестов (xUnit бэкенда + Vitest фронтенда) со сбором покрытия |
| `task audit` | `npm run audit` | Полный глубокий аудит качества и производительности со сборкой отчетов |
| — | `npm run audit -- --with-ai` | Полный аудит + автоматический запуск визуального AI UI/UX ревью через Gemini |
| `task visual` | `npm run visual` | Сверка 18 визуальных сценариев BackstopJS (Mobile, Tablet, Desktop) |
| `task visual:approve` | `npm run visual:approve` | Принятие текущих скриншотов как эталонов для BackstopJS |
| `task report` | `npm run report` | Принудительная перегенерация `AUDIT_REPORT.md` и `AUDIT_REPORT.html` |
| `task security` | `npm run security` | Быстрый аудит уязвимостей (NuGet, NPM production) и утечек приватных ключей |
| `task stress` | `npm run test:stress` | Стресс-тест виртуального скролла и базы на 50 000 элементов на 144 FPS |
| — | `npm run smells` | Инспектор микрооптимизаций C# и Svelte с формированием diff-подсказок |
| — | `npm run review:ai` | Автономный запуск захвата скриншотов и отправка на дизайн-ревью в Gemini |

---

## 3. Каталог статических проверок и линтеров (`checks/static`)

Все статические чеки можно запускать по отдельности:

| Команда | Файл проверки | Что проверяет |
| :--- | :--- | :--- |
| `npm run check:bundle` | `checks/static/bundleBudget.check.ts` | Контроль бюджетов Gzip (js/css) |
| `npm run check:contract-drift` | `checks/static/contractDrift.check.ts` | Синхронность 79 полей между C# `MediaResponseDtos.cs` и TS-моделями |
| `npm run check:deslop` | `checks/static/deslopAndUiMath.check.ts` | Поиск AI-штампов и математика верстки |
| `npm run format:fix` | — | Автоформатирование Prettier + автофикс De-slop |
| `npm run check:html` | `checks/static/htmlValidate.check.ts` | Валидность HTML-тегов, вложенность |
| `npm run check:i18n` | `checks/static/i18nHardcode.check.ts` | Поиск хардкода кириллицы |
| `npm run check:i18n-parity` | `checks/static/i18nParity.check.ts` | Симметрия ключей RU/EN (1144 ключа) |
| `npm run check:leading-chars` | `checks/static/leadingChars.check.ts` | Целостность кодировки (Windows-1251) |
| `npm run check:orphans` | `checks/static/orphanChecks.check.ts` | Регистрация 100% чеков на диске в пайплайне |
| `npm run check:state-raw` | `checks/static/stateRaw.check.ts` | Использование `$state.raw` в Svelte 5 |
| `npm run check:deadcode` | `knip.json` | Поиск мертвого кода |
| `npm run lint:es` | `eslint.config.js` | Линтинг TypeScript/Svelte (ESLint 9) |
| `npm run lint:css` | `.stylelintrc.json` | Stylelint (аппаратные анимации) |
| `npm run check` | — | `svelte-check` + `tsc` |

---

## 4. Каталог браузерного аудита и CDP-профилирования (`checks/audit`)

Эти проверки выполняются в реальном браузере Chromium:

| Команда | Файл проверки | Что замеряет |
| :--- | :--- | :--- |
| `npm run check:browser-suite` | `checks/audit/browserSuite.runner.ts` | Главный раннер (~50–60 сек) |
| `npm run check:cdp` | `checks/audit/cdpProfiler.check.ts` | `LayoutDuration`, `RecalcStyleDuration`, утечки памяти |
| `npm run check:geometry` | `checks/audit/layoutGeometry.check.ts` | Горизонтальный скролл, закон Фиттса |
| `npm run check:a11y` | `checks/audit/axeAccessibility.check.ts` | Аудит WCAG 2.1 AA |
| `npm run check:snapshots` | `checks/audit/visualSnapshots.check.ts` | Попиксельная сверка компонентов |
| `npm run check:snapshots:update`| — | Обновление эталонных снапшотов |
| `npm run check:web-vitals` | `checks/audit/webVitals.check.ts` | Google Core Web Vitals (LCP, CLS, INP) |

---

## 5. Каталог функциональных E2E сценариев Playwright (`checks/e2e`)

| Команда | Сценарий |
| :--- | :--- |
| `npm run check:achievements-buttons` | Логика достижений в играх |
| `npm run check:cards` | Рендеринг карточек всех типов |
| `npm run check:category-switch` | Переключение категорий библиотек |
| `npm run check:diag-scenarios` | Стресс-фильтрация и навигация |
| `npm run check:external-sources` | Провайдеры (AniList, Shikimori и др.) |
| `npm run check:game-payloads` | Кэширование данных игр |
| `npm run check:history-delete` | Удаление записей истории |
| `npm run check:jobs-queue` | Асинхронная очередь задач |
| `npm run check:lists` | Умные списки и создание |
| `npm run check:nav-detail` | Детальная страница тайтла |
| `npm run check:nav-overlap` | Адаптивность (мобильный таббар) |
| `npm run check:overview-ladder` | Двухколоночный макет Overview |
| `npm run check:popover` | Поповер статуса на карточке |
| `npm run check:ratings-settled` | Синхронизация внешних рейтингов |
| `npm run check:regression-fixes` | Проверка регрессий (редактирование) |
| `npm run check:related` | Франшиза и связанные тайтлы |
| `npm run check:release-dates` | Даты выхода и онгоинги |
| `npm run check:relink` | Смена источника метаданных |
| `npm run check:score-stack` | Стекинг бейджей на постере |
| `npm run check:search-modal` | Поиск по Ctrl+K |
| `npm run check:seasons` | Сезоны и аккордеоны |
| `npm run check:tokens` | Валидация CSS-токенов |
| `npm run check:virtual-grid` | Виртуализация сетки |
| `npm run check:visual-qa` | Сквозной визуальный проход |
| `npm run check:related-matching`| Связанные и матч-логика |

---

## 6. Тестирование и покрытие кода

### Бэкенд (.NET 10 / xUnit)
- `dotnet test MediaTracker.Tests/MediaTracker.Tests.csproj` (тесты покрывают правила домена, парсеры и интеграцию с БД).

### Фронтенд (Vitest v8)
- `npm --prefix mediatracker-ui run test:unit` (юнит-тесты моделей, утилит и редьюсеров).

---

## 7. Глубокое профилирование бэкенда, БД и стресс-тесты (`scripts/`)

| Команда | Скрипт | Что выполняет |
| :--- | :--- | :--- |
| `npm run selfcheck` | `RefactorSelfCheck.cs` | Самотест сервера и аудит SQLite |
| `npm run benchmarks` | `MediaTracker.Benchmarks` | Профилирование алгоритмов |
| `npm run profile:backend` | `profile-backend.mjs` | Макропрофилирование (dotnet-trace) |
| `npm run inspect:sqlite` | `inspect-sqlite-health.mjs` | Аудит фрагментации SQLite |
| `npm run measure:api` | `measure-api-payloads.mjs` | Замер латентности ответов JSON |
| `npm run test:stress` | `stress-test.mjs` | Стресс-тест 50к+ элементов |

---

## 8. Визуальный регрессионный контроль (BackstopJS)
- Сверка визуальных сценариев (Mobile/Tablet/Desktop).
- `npm run visual` (запуск), `npm run visual:approve` (принятие эталонов).

---

## 9. AI UI/UX ревью интерфейса (Google Gemini)
- `npm run review:ai` (скриншоты -> Gemini Vision).
- `npm run audit -- --with-ai` (интегрированный отчет).

---

## 10. Руководство по настройке правил
- **Бюджеты:** `bundleBudget.check.ts`, `cdpProfiler.check.ts`, `measure-api-payloads.mjs`.
- **Правила дизайна:** `SKILL.md`, `deslopAndUiMath.check.ts`.
