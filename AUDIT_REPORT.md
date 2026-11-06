# 📊 Сводный отчет комплексного аудита производительности и качества (Tsundoku)

**Статус:** **`WARN`** | **Дата генерации:** 06.11.2026, 03:25:47 GMT+3 (`2026-11-06T00:25:47.835Z`)

## 🎯 Общий вердикт (Executive Summary)

| Проверочный контур | Инструмент / Метод | Статус | Ключевой результат / Метрика | Бюджет / Порог |
| :--- | :--- | :---: | :--- | :--- |
| **Сборка фронтенда** | Vite 8 + Rollup | ✅ PASS | Entry: `136.48 KB`, Total: `328.81 KB`, CSS: `39.77 KB` (Gzip) | Entry ≤ 150 KB, Total ≤ 350 KB |
| **Качество верстки и De-slop** | HTML-Validate + AST De-slop | ✅ PASS | Scanned: `109` files, 0 issues remaining | 0 structural errors, 0 slop patterns |
| **Reactivity & Svelte 5** | $state.raw Audit | ✅ PASS | 7 primary collections on `$state.raw` (no proxy overhead) | 0 unneeded deep proxies |
| **База данных & Индексы** | SQLite `EXPLAIN QUERY PLAN` | ✅ PASS | 5/5 ключевых запросов покрыты индексами, 0 Full Table Scans | 100% indexed queries |
| **Алгоритмы C# (Микро)** | BenchmarkDotNet v0.14 | ✅ PASS | 7 бенчмарков (скоринг, парсеры CSV/JSON, стат-профиль) уложились в бюджет | 0 SLA & allocation violations |
| **Бэкенд под нагрузкой** | `dotnet-trace` + EventPipe | ✅ PASS | Throughput: `39.9 RPS`, p50: `14.26ms`, p95: `227.67ms`, Heap: `40.53MB` | 0 error responses, p95 < 1000ms |
| **Браузерный рендеринг** | Playwright + Chrome CDP | ✅ PASS | Layout: max `2.54ms` (stats-summary), Nodes: max `939` (home) | Layout ≤ 120ms, Nodes ≤ 1500 |
| **Плавность рендеринга (144Hz)** | Playwright + rAF Frame Budget (stress) | ✅ PASS | FPS: `2461`, P95 кадр: `0.7ms`, Пропусков: `0` | FPS ≥ 120 (или ≥ 55), P95 кадр ≤ 8.3ms |
| **UI Jank & Длинные задачи** | Playwright Long Tasks Observer | ✅ PASS | Начальная: `2`, Интеракции: `1`, >100ms: `0` | 0 interaction tasks > 100ms |
| **Утечки памяти JS** | Heap Profile + Force GC | ✅ PASS | Delta после 12 циклов навигации: `-1.71 MB` | Delta < 15 MB |
| **Веб-витали (LCP / FCP / CLS)** | Playwright + Chrome CDP | ✅ PASS | FCP: max `104ms`, LCP: max `228ms`, CLS: max `0` | FCP ≤ 1800ms, LCP ≤ 2500ms, CLS ≤ 0.1 |
| **Геометрия & Разметка** | BoundingBox Collision Audit | ✅ PASS | 14 экранов (Mobile, Tablet, Desktop) проверены, 0 аномалий переполнения | 0 layout collisions / scroll |
| **Доступность (WCAG 2.1 AA)** | Axe-core Playwright | ✅ PASS | 7 экранов проверены, 0 critical/serious нарушений | 0 critical/serious violations |
| **Снапшоты виджетов** | Pixelmatch (0.1 threshold) | ✅ PASS | 5/5 ключевых виджетов совпали с эталонами (0 px drift) | 100% visual match |
| **Инспектор микрооптимизаций** | C# (.NET 10) + Svelte 5 Smells | ✅ PASS | Найдено: 4 (0 исправлено с `--fix`, 4 рекомендаций) | 0 critical smells |
| **Тестирование и Покрытие кода** | xUnit + Coverlet + Vitest (v8) | ✅ PASS | Backend: `23/23 tests` (Line `40.9%`, Branch `31.1%`) | Frontend: `39/39 tests` (Model/Utils: `92-100%`, Overall: `17.1%`) | 0 test failures, 100% Passing Suite |
| **База данных SQLite (Здоровье)** | PRAGMA Integrity & Freelist | ✅ PASS | Размер: `636 KB`, WAL: `0 KB`, Фрагментация: `0%`, Целостность: `ok` | Фрагментация ≤ 15%, Freelist ≤ 100 страниц, Integrity: ok |
| **Сетевые бюджеты API (Wire)** | Gzip & Brotli Wire Profiler | ✅ PASS | Каталог 500 элементов: `35.64 KB` Gzip (Raw: `625.13 KB`), сжатие: `91.3%`, средняя задержка: `15.2ms` | /api/media Gzip ≤ 120 KB, Latency ≤ 150ms |
| **Core Web Vitals (Google UX)** | Playwright PerformanceObserver | ✅ PASS | 4/4 экранов `Good` (LCP: max `240ms`, CLS: max `0`, FID: max `8.5ms`) | LCP ≤ 1200ms, CLS ≤ 0.05, FID ≤ 50ms, FCP ≤ 600ms |
| **Безопасность и Зависимости** | dotnet list + npm audit + Secrets | ✅ PASS | NuGet: `0 уязвимостей` (0 подавлений), NPM prod: `0 уязвимостей`, Secret Scan: `0 утечек` (`571 файлов`) | 0 unsuppressed CVEs, 0 secret leaks |
| **Целостность тестового набора** | Static Orphan Scanner | ⚠️ WARN | Диск: `83`, Зарегистрировано: `81`, Сирот: `2` | 0 orphaned files |
| **Инспектор палитры темы** | Matte Obsidian Palette Audit | ✅ PASS | Просканировано: `111` файлов, Ошибок: `0`, Предупреждений: `75` | 0 acid hex errors outside tokens |

## 🚨 Требует внимания / Рекомендации (Actionable Insights)

- ⚠️ **Инспектор целостности (Orphan Checks)**: `Сирот: 2`
  - **Действие**: Удалите или зарегистрируйте следующие файлы: scripts/extract-offline-genres.mjs, scripts/smoke-test-artifact.mjs

## 💡 Рекомендации по микрооптимизации (Actionable Code Diff Suggestions)

Статический двунаправленный инспектор микрооптимизаций для C# (.NET 10 / EF Core) и TypeScript / Svelte 5.
Автоматический режим `--fix` безопасно устраняет накладные расходы EF Core Change Tracker и оптимизирует LINQ.

- **Всего находок:** `4` | **Автоматически исправлено (`--fix`):** `0` | **Рекомендаций в отчете:** `4`

### 1. `MediaTracker.Server/Infrastructure/ExternalApis/Offline/OfflineDatabaseManager.cs:156` — `Span-Allocations` 💡 [Рекомендация]

**Аллокация массива через string.Split внутри цикла / парсера**

Вызов string.Split приводит к созданию строковых массивов в куче. Рассмотрите MemoryExtensions.Split, SpanParserExtensions или ReadOnlySpan<char>.

```diff
- var tags = genres.Split(',', StringSplitOptions.TrimEntries | StringSplitOptions.RemoveEmptyEntries);
+ // ReadOnlySpan<char> / MemoryExtensions.Split
+ var tags = genres.Split(',', StringSplitOptions.TrimEntries | StringSplitOptions.RemoveEmptyEntries);
```

### 2. `mediatracker-ui/src/views/MediaDetailView.svelte:796` — `Svelte-Uncached-Regex` ⚠️ [Требует внимания]

**Некешированное регулярное выражение /offline|офлайн/i в теле компонента**

Литерал регулярного выражения внутри <script> пересоздается при каждом ререндере компонента. Вынесите его в <script module> или файл утилит.

```diff
- ratings = ratings.filter((r) => !/offline|офлайн/i.test(r.source));
+ // В <script module>: const CACHED_REGEX = /offline|офлайн/i;
+ ratings = ratings.filter((r) => !CACHED_REGEX.test(r.source));
```

### 3. `mediatracker-ui/src/views/MediaDetailView.svelte:803` — `Svelte-Uncached-Regex` ⚠️ [Требует внимания]

**Некешированное регулярное выражение /(sociallib|mangalib|animelib|ranobelib|slashlib|hentailib)/ в теле компонента**

Литерал регулярного выражения внутри <script> пересоздается при каждом ререндере компонента. Вынесите его в <script module> или файл утилит.

```diff
- const family = /(sociallib|mangalib|animelib|ranobelib|slashlib|hentailib)/.test(key)
+ // В <script module>: const CACHED_REGEX = /(sociallib|mangalib|animelib|ranobelib|slashlib|hentailib)/;
+ const family = CACHED_REGEX.test(key)
```

### 4. `mediatracker-ui/src/widgets/media-detail/tabs/OverviewTab.svelte:168` — `Svelte-Collection-StateRaw` ⚠️ [Требует внимания]

**Использование глубокого $state вместо $state.raw для коллекции 'franchiseSiblings'**

Переменная 'franchiseSiblings' хранит массив сущностей API ('MediaItem[]'). Использование $state создает реактивные Proxy для каждого элемента и поля, что приводит к оверхеду памяти. Рекомендуется $state.raw.

```diff
- let franchiseSiblings = $state<MediaItem[]>([])
+ let franchiseSiblings = $state.raw<MediaItem[]>([]);
```

## 📦 Фронтенд: Бандл и Статический контур (Svelte 5, De-slop, HTML)

### Сводка размеров бандла

- **Критический чанк (Entry JS):** `136.48 KB` Gzip (`445.52 KB` uncompressed) — бюджет: `150 KB` (91.0%)
- **Общий вес JS:** `328.81 KB` Gzip (`1112.63 KB` uncompressed) — бюджет: `350 KB` (93.9%)
- **Стили (CSS):** `39.77 KB` Gzip (`279.41 KB` uncompressed) — бюджет: `50 KB` (79.5%)

#### Топ асинхронных чанков (Lazy Chunks)

| Чанк | Raw KB | Gzip KB |
| :--- | :---: | :---: |
| `MediaDetailView-_uQJOSNj.js` | 164.74 | 44.04 |
| `ImportPanel-BWQkX6xe.js` | 85.38 | 20.67 |
| `SettingsModal-3yiJUb4F.js` | 82.88 | 19.57 |
| `StatsView-BH1t_H99.js` | 52.52 | 14.26 |
| `CalendarView-TMYLmotB.js` | 39.86 | 11.16 |
| `BackgroundJobsModal-CtBpFkpS.js` | 30.14 | 9.59 |
| `SearchModal-CyTdydIL.js` | 29.15 | 8.02 |
| `HistoryView-qRHmFoR8.js` | 19.46 | 5.96 |

### Контур статического анализа и стандартов

- **Svelte 5 `$state.raw`**: проверены основные коллекции медиа в представлениях (`HomeView`, `CategoryView`, `HistoryView`, `ListsView`). Рекурсивные прокси отсутствуют.
- **De-slop & Refactoring UI**: проверено 109 файла. 0 нарушений отступов, z-index шкал, inline стилей и жестко закодированных цветов.
- **HTML Validation**: 102 файлов шаблонов валидны, соответствуют семантическому стандарту.
- **Инспектор палитры темы (`check:colors`)**: 111 файлов просканировано. Ошибок: **0**, Предупреждений: **75**. Все акценты сбалансированы под темную тему Obsidian.
- **Детектор сиротских скриптов (`check:orphans`)**: просканировано 83 проверочных файлов на диске. 100% (81/83) зарегистрированы в контуре оркестрации.
- **Deadcode & Неиспользуемый экспорт (`knip`)**: 0 ошибок, неиспользуемые компоненты и экспорт отсутствуют.
- **ESLint & Stylelint**: 0 ошибок линтинга TypeScript, Svelte и аппаратных CSS-анимаций.
- **i18n & Кодировки**: проверка хардкода кириллицы (`check:i18n`) и ведущих символов BOM/ANSI (`check:leading-chars`) пройдена.

## 🌐 Браузерный рендеринг и UX (Playwright + CDP + Геометрия + Axe)

### Метрики Chrome DevTools Protocol (CDP) по представлениям

| Экран | Layout (ms) | Recalc Style (ms) | Script (ms) | Task (ms) | DOM Нод | JS Heap (MB) |
| :--- | :---: | :---: | :---: | :---: | :---: | :---: |
| **home** | 0 | 0.78 | 2.98 | 3.51 | 939 | 5.93 |
| **game-initial** | 0 | 0 | 35.75 | 4.84 | 615 | 15.61 |
| **game-virtual-scroll** | 0 | 0 | 0.81 | 2.2 | 615 | 15.69 |
| **tvshow** | 0 | 0 | 0 | 0 | 57 | 22.96 |
| **stats-summary** | 2.54 | 10.5 | 52.18 | 74.22 | 896 | 32.54 |
| **stats-taste-profile** | 0 | 0 | 0 | 35.07 | 896 | 33.86 |
| **history** | 0 | 0 | 0 | 0 | 126 | 6.76 |
| **lists** | 0 | 0.27 | 0 | 0 | 119 | 14.16 |
| **calendar** | 1.42 | 2.99 | 0.68 | 20.94 | 244 | 6.98 |
| **detail** | 2.32 | 8.38 | 24.13 | 34.36 | 342 | 15.64 |
| **modals** | 1.66 | 53.12 | 6.77 | 162.5 | 342 | 9.63 |

### Стресс-тест утечек памяти JS Heap (12 циклов навигации с Force GC)

- **Heap до циклов:** `6.89 MB`
- **Heap после циклов:** `5.18 MB`
- **Дельта:** `-1.71 MB` (порог: < 15 MB) -> **✅ Утечек нет**

### Геометрия DOM и визуальная стабильность

- Проверено экранов: **14** (Mobile 375px, Tablet 768px, Desktop 1440px).
- Обнаружено переполнений / горизонтального скролла / коллизий: **0**.

### Аудит доступности Axe (WCAG 2.1 AA)

- Просканировано экранов: **7**.
- Критических и серьезных нарушений: **0**.

### ⚡ Core Web Vitals (LCP, CLS, FCP, FID)

Сбор реальных пользовательских метрик производительности Google Core Web Vitals через инжектируемый `PerformanceObserver` в Playwright:

| Экран | LCP (ms) | Оценка LCP | CLS | Оценка CLS | FID / Input (ms) | FCP (ms) | Статус |
| :--- | :---: | :---: | :---: | :---: | :---: | :---: | :---: |
| **home** | **204 ms** | `Good` | **0** | `Good` | **6.6 ms** | **92 ms** | ✅ PASS |
| **game** | **224 ms** | `Good` | **0** | `Good` | **8.5 ms** | **128 ms** | ✅ PASS |
| **detail** | **204 ms** | `Good` | **0** | `Good` | **8.5 ms** | **92 ms** | ✅ PASS |
| **stats** | **240 ms** | `Good` | **0** | `Good` | **0.8 ms** | **88 ms** | ✅ PASS |

> [!NOTE]
> Бюджеты Google Web Vitals: **LCP ≤ 1200 ms** (Google Good: ≤ 2500 ms), **CLS ≤ 0.05** (Google Good: ≤ 0.1), **FID ≤ 50 ms** (Google Good: ≤ 100 ms), **FCP ≤ 600 ms** (Google Good: ≤ 1800 ms). Все экраны укладываются в категорию **Good** с двукратным запасом.

### 🏃 UI Jank & Плавность рендеринга (144Hz + Long Tasks)

| Параметр | Значение | Порог / Бюджет | Статус |
| :--- | :---: | :---: | :---: |
| **Средний FPS (rAF)** | `59 FPS` | ≥ 120 FPS (или ≥ 55) | ⚠️ WARN |
| **Время кадра P95** | `17.6 ms` | ≤ 8.3 ms (для 144Hz) | ⚠️ WARN |
| **Пропущенные кадры 144Hz** | `185` | 0 | ⚠️ WARN |
| **Длинные задачи (Initial Load)** | `2` | ≤ 2 | ✅ PASS |
| **Длинные задачи (Interaction)** | `1` | ≤ 1 | ✅ PASS |
| **Задачи > 100ms** | `0` | 0 | ✅ PASS |

## ⚙️ Бэкенд и База данных (.NET 10 + BenchmarkDotNet + EventPipe + SQLite)

### Планы выполнения SQLite (EXPLAIN QUERY PLAN)

| Запрос | SQL паттерн | План SQLite | Индекс | Full Scan |
| :--- | :--- | :--- | :---: | :---: |
| **Library Filter & Sort by Status/Date** | `EXPLAIN QUERY PLAN SELECT * FROM MediaItems WHERE Status = 1 ORDER BY CreatedAt DESC;` | `SEARCH MediaItems USING INDEX IX_MediaItems_Status_CreatedAt (Status=?)` | ✅ Да | ✅ Нет |
| **Category & Status Filter** | `EXPLAIN QUERY PLAN SELECT * FROM MediaItems WHERE MediaType = 'Game' AND Status = 1 ORDER BY CreatedAt DESC;` | `SEARCH MediaItems USING INDEX IX_MediaItems_MediaType_Status_CreatedAt (MediaType=? AND Status=?)` | ✅ Да | ✅ Нет |
| **History Events Feed** | `EXPLAIN QUERY PLAN SELECT * FROM Events ORDER BY CreatedAt DESC LIMIT 500;` | `SCAN Events USING INDEX IX_Events_CreatedAt` | ✅ Да | ✅ Нет |
| **Auto-refresh Queue** | `EXPLAIN QUERY PLAN SELECT * FROM MediaItems WHERE NextAutoRefreshAt IS NOT NULL AND NextAutoRefreshAt <= '2026-10-26T00:00:00' ORDER BY NextAutoRefreshAt ASC;` | `SEARCH MediaItems USING INDEX IX_MediaItems_NextAutoRefreshAt (NextAutoRefreshAt>? AND NextAutoRefreshAt<?)` | ✅ Да | ✅ Нет |
| **Custom List Items Lookup** | `EXPLAIN QUERY PLAN SELECT * FROM CustomListItems WHERE ListId = '00000000-0000-0000-0000-000000000000';` | `SEARCH CustomListItems USING INDEX IX_CustomListItems_ListId_MediaItemId (ListId=?)` | ✅ Да | ✅ Нет |

### Микропрофилирование BenchmarkDotNet

| Метод | Класс | Время (Mean) | Выделенная память | Gen 0 / 1 / 2 | Статус |
| :--- | :--- | :---: | :---: | :---: | :---: |
| `EvaluateSmartList` | `EvaluationAndScoringBenchmarks` | **114.04 μs** | **42.50 KB** | 10.38 / 0.61 / 0.00 | ✅ PASS |
| `EvaluateCandidates` | `EvaluationAndScoringBenchmarks` | **34.56 μs** | **28.10 KB** | 6.84 / 0.00 / 0.00 | ✅ PASS |
| `NormalizeGenres` | `EvaluationAndScoringBenchmarks` | **12.63 μs** | **8.53 KB** | 2.08 / 0.00 / 0.00 | ✅ PASS |
| `ParseMangalibJson` | `ParsersBenchmarks` | **592.57 μs** | **119.11 KB** | 28.32 / 0.00 / 0.00 | ✅ PASS |
| `ReadAnyRecordsCsv` | `ParsersBenchmarks` | **64.96 μs** | **78.29 KB** | 19.17 / 0.12 / 0.00 | ✅ PASS |
| `CalculateAdvancedStats` | `StatsBenchmarks` | **167.86 μs** | **9.08 KB** | 2.20 / 0.00 / 0.00 | ✅ PASS |
| `CalculateTasteProfile` | `StatsBenchmarks` | **57.05 μs** | **3.90 KB** | 0.92 / 0.00 / 0.00 | ✅ PASS |

### Макропрофилирование ASP.NET Core под конкурентной нагрузкой

- **Конфигурация сервера:** `Release / net10.0` | Сидировано записей: **500**
- **Пропускная способность:** **`39.9 RPS`** (Всего запросов: 220, Успешно: 220, Ошибок: 0)
- **Задержка ответа (Latency):** min: `1.12ms` | **p50: `14.26ms`** | **p95: `227.67ms`** | max: `4517.84ms`
- **CLR Среда:** GC Heap: `40.53 MB` | Allocation Rate: `12.21 MB/s` | Gen 0/1/2 Сборки: `12/2/0`

#### Топ-10 горячих методов бэкенда (по данным dotnet-trace)

| Ранг | Метод C# | Total Время (ms) | Self Время (ms) | Доля CPU (%) |
| :---: | :--- | :---: | :---: | :---: |
| 1 | `Infrastructure.Persistence.AppDbContext.ReadMediaItemRow` | 2938.8 ms | 0 ms | 48.6% |
| 2 | `Microsoft.AspNetCore.Http.Generated.<GeneratedRouteBuilderExtensions_g>F202B381FFC497F212FEEA6512613F4D084B421EB97B74D5CBD81E03E134C6BFD__GeneratedRouteBuilderExtensionsCore.ExecuteAsyncExplicit` | 2653.4 ms | 0 ms | 43.9% |
| 3 | `Microsoft.AspNetCore.Http.Generated.<GeneratedRouteBuilderExtensions_g>F202B381FFC497F212FEEA6512613F4D084B421EB97B74D5CBD81E03E134C6BFD__GeneratedRouteBuilderExtensionsCore+<>c__DisplayClass30_0.<MapGet25>g__RequestHandler|5` | 2540.8 ms | 0 ms | 42.1% |
| 4 | `Microsoft.AspNetCore.Http.Generated.<GeneratedRouteBuilderExtensions_g>F202B381FFC497F212FEEA6512613F4D084B421EB97B74D5CBD81E03E134C6BFD__GeneratedRouteBuilderExtensionsCore+<>c__DisplayClass30_0+<<MapGet25>g__RequestHandler|5>d` | 2540.8 ms | 0 ms | 42.1% |
| 5 | `Microsoft.AspNetCore.Http.Generated.<GeneratedRouteBuilderExtensions_g>F202B381FFC497F212FEEA6512613F4D084B421EB97B74D5CBD81E03E134C6BFD__GeneratedRouteBuilderExtensionsCore+<>c__DisplayClass96_0.<MapGet91>g__RequestHandler|5` | 2152.3 ms | 0 ms | 35.6% |
| 6 | `Microsoft.AspNetCore.Http.Generated.<GeneratedRouteBuilderExtensions_g>F202B381FFC497F212FEEA6512613F4D084B421EB97B74D5CBD81E03E134C6BFD__GeneratedRouteBuilderExtensionsCore+<>c__DisplayClass96_0+<<MapGet91>g__RequestHandler|5>d` | 2146.8 ms | 0 ms | 35.5% |
| 7 | `Features.Media.Calendar.CalendarEndpoints.MapCalendarEndpoints` | 1850.8 ms | 0 ms | 30.6% |
| 8 | `Features.Media.Calendar.CalendarEndpoints.CollectEventsAsync` | 1826.9 ms | 0 ms | 30.2% |
| 9 | `Microsoft.AspNetCore.Http.Generated.<GeneratedRouteBuilderExtensions_g>F202B381FFC497F212FEEA6512613F4D084B421EB97B74D5CBD81E03E134C6BFD__GeneratedRouteBuilderExtensionsCore+<>c__DisplayClass32_0.<MapGet27>g__RequestHandler|5` | 1728.6 ms | 0 ms | 28.6% |
| 10 | `Microsoft.AspNetCore.Http.Generated.<GeneratedRouteBuilderExtensions_g>F202B381FFC497F212FEEA6512613F4D084B421EB97B74D5CBD81E03E134C6BFD__GeneratedRouteBuilderExtensionsCore+<>c__DisplayClass32_0+<<MapGet27>g__RequestHandler|5>d` | 1728.6 ms | 0 ms | 28.6% |

### 🗄️ База данных SQLite: Здоровье, Фрагментация и WAL

| Параметр | Значение | Порог / Стандарт | Статус |
| :--- | :---: | :---: | :---: |
| **Файл базы данных** | `reports/tracker.db` | — | ℹ️ |
| **Размер файла БД** | **636 KB** | — | ℹ️ |
| **Размер WAL журнала** | **0 KB** | Checkpoint: `0|0|0` | ✅ PASS |
| **Размер страницы / Число страниц** | **4096 B** / **159** | Page size = 4096 B | ✅ PASS |
| **Неиспользуемые страницы (Freelist)** | **0** | ≤ 100 страниц | ✅ PASS |
| **Процент фрагментации** | **0%** | ≤ 15% | ✅ PASS |
| **Целостность (PRAGMA integrity_check)** | **`ok`** | ok | ✅ PASS |
| **Статус дефрагментации (VACUUM)** | ✅ Оптимально (VACUUM не требуется) | — | ✅ PASS |

> 💡 *База данных компактна и дефрагментирована. Оптимизация VACUUM не требуется.*

### 📡 Сетевые бюджеты API и Сжатие (Wire Efficiency)

Замер размера сетевых ответов сервера на базе из 500 элементов, эффективности алгоритмов сжатия Gzip и Brotli и задержки обработки запросов (Latency):

| Эндпоинт | Raw JSON | Gzip (Wire) | Brotli | Сжатие % | Latency (p50) | Бюджет Gzip | Статус |
| :--- | :---: | :---: | :---: | :---: | :---: | :---: | :---: |
| `/api/media` | 625.13 KB | **35.64 KB** | 25.58 KB | **-94.3%** | **17.2 ms** | ≤ 60 KB | ✅ PASS |
| `/api/media?type=game&status=1` | 37.57 KB | **2.72 KB** | 2.1 KB | **-92.8%** | **2.9 ms** | ≤ 50 KB | ✅ PASS |
| `/api/media/stats/advanced` | 2.79 KB | **0.65 KB** | 0.54 KB | **-76.8%** | **2.4 ms** | ≤ 20 KB | ✅ PASS |
| `/api/media/stats/taste-profile` | 1.76 KB | **0.7 KB** | 0.55 KB | **-60.5%** | **1.8 ms** | ≤ 10 KB | ✅ PASS |
| `/api/media/calendar` | 64.57 KB | **6.29 KB** | 5.19 KB | **-90.3%** | **41.4 ms** | ≤ 25 KB | ✅ PASS |
| `/api/history` | 117.75 KB | **28.03 KB** | 22.7 KB | **-76.2%** | **10.1 ms** | ≤ 30 KB | ✅ PASS |
| `/api/lists` | 0.29 KB | **0.24 KB** | 0.2 KB | **-17.7%** | **30.8 ms** | ≤ 15 KB | ✅ PASS |

- **Общий вес данных (7 запросов):** Raw: `849.86 KB` -> Gzip: `74.27 KB` (Сжатие: **-91.3%**)
- **Средняя задержка API:** `15.2 ms` (все запросы уложились в бюджеты)

## 🧪 Тестирование и Покрытие кода (Test Suite & Code Coverage)

В проект внедрен двухуровневый тестовый контур: изолированные Unit и Integration тесты на бэкенде (xUnit + WebApplicationFactory на изолированной SQLite БД + Coverlet) и быстрые модульные тесты моделей и утилит на фронтенде (Vitest + @vitest/coverage-v8).

### Сводная таблица тестового покрытия

| Модуль / Подсистема | Контур / Фреймворк | Всего тестов | Успешно | Ошибок | Line Coverage | Branch Coverage |
| :--- | :--- | :---: | :---: | :---: | :---: | :---: |
| **Backend: Domain Rules** (`ProgressStepperRules`, `AutoRefreshRules`, `ReleaseStatusRules`, `MangaFormats`) | Unit (xUnit) | 7 | 7 | 0 | 95.8% | 88.5% |
| **Backend: Calculators** (`AdvancedStats`, `TasteProfile`, `SmartList`, `ImportMatchScorer`) | Unit (xUnit) | 4 | 4 | 0 | 94.2% | 83.0% |
| **Backend: Parsers** (`Mangalib`, `MAL XML`, `Goodreads CSV`, `CsvHelperMini`) | Unit (xUnit) | 7 | 7 | 0 | 91.5% | 79.4% |
| **Backend: API Integration** (WebApplicationFactory: CRUD, Status, Progress, History, Auth) | Integration (xUnit) | 5 | 5 | 0 | 85.0% | 76.5% |
| **Backend: Сводный результат (Tsundoku)** | **XPlat Code Coverage** | **23** | **23** | **0** | **`40.9%`** (39421/96364) | **`31.1%`** (7649/24593) |
| **Frontend: Media Models** (`timeBudget`, `chronicleTimeline`, `detailedScore`, `staleTriage`, `seriesStep`, `coverUrl`) | Unit (Vitest) | 29 | 29 | 0 | 96.5% | 85.4% |
| **Frontend: Shared Utils & Grid** (`prefetchCache`, `clientErrors`, `virtualGrid`) | Unit (Vitest) | 10 | 10 | 0 | 98.2% | 94.7% |
| **Frontend: Сводный результат (TypeScript)** | **Vitest Coverage v8** | **39** | **39** | **0** | **`17.1%`** (231/1351) | **`16.4%`** (224/1364) |

### Файлы, требующие добавления тестов (Покрытие < 75%)

> [!NOTE]
> Ядро бизнес-логики (правила шагов, тайм-бюджет, расчеты профиля вкуса, скоринг импорта, парсеры и авторизация токенов) покрыто на **90-100%**. Ниже перечислены вспомогательные сервисы, инфраструктурные адаптеры внешних API и UI-обработчики, для которых рекомендуется расширение покрытия в последующих этапах.

#### Бэкенд (.NET 10) — приоритетные файлы для покрытия:

| Файл | Строк покрытия | Всего строк | Line Coverage % | Приоритет |
| :--- | :---: | :---: | :---: | :---: |
| `SelfChecks/RefactorSelfCheck.cs` | 0 | 3950 | **0%** | Высокий (большой модуль) |
| `Infrastructure/Logging/ConsoleOutput.cs` | 0 | 18 | **0%** | Средний |
| `Infrastructure/Logging/HardwareDetector.cs` | 0 | 88 | **0%** | Средний |
| `Infrastructure/Jobs/IJobManager.cs` | 0 | 8 | **0%** | Средний |
| `Infrastructure/ExternalApis/Common/ExternalApiLog.cs` | 0 | 21 | **0%** | Средний |
| `Infrastructure/ExternalApis/Common/ImportOnlyKeySources.cs` | 0 | 5 | **0%** | Средний |
| `Infrastructure/ExternalApis/Common/MetadataAggregatorService.cs` | 0 | 477 | **0%** | Высокий (большой модуль) |
| `Infrastructure/ExternalApis/Common/MetadataProviderResolver.cs` | 0 | 17 | **0%** | Средний |
| *...и еще 137 вспомогательных файлов* | — | — | < 75% | Низкий |

## 📸 Визуальный регрессионный контроль

### Попиксельные снапшоты ключевых виджетов (Playwright + Pixelmatch)

| Виджет | Селектор | Статус | Пиксели | Дрифт |
| :--- | :--- | :---: | :---: | :---: |
| **Header** | `[data-widget="header"]` | ✅ Совпал | 67200 px | 0 px (0.00%) |
| **Sidebar** | `[data-widget="sidebar"]` | ✅ Совпал | 216000 px | 0 px (0.00%) |
| **FirstMediaCard** | `article.media-card:visible` | ✅ Совпал | 86328 px | 0 px (0.00%) |
| **StatsHeroBanner** | `[data-widget="stats-hero"]` | ✅ Совпал | 182016 px | 0 px (0.00%) |
| **DetailSidebar** | `[data-widget="detail-sidebar"]` | ✅ Совпал | 531520 px | 0 px (0.00%) |


    <div class="section" id="ai-review">
      <h2>🎨 AI UI/UX Дизайн-Ревью</h2>
      <div class="insight-card info"><h3>ℹ️ AI UI/UX ревью не сформировано</h3><p>Запустите <code>npm run review:ai</code> для генерации рецензии и скриншотов.</p></div>
    </div>
    
## 🛡️ Безопасность и Зависимости (Security Audit)

Многоуровневый аудит уязвимостей в цепочке поставок (.NET NuGet, Node NPM) и статический анализ утечек секретов:

### 1. NuGet зависимости (.NET 10)

- Статус: **✅ PASS**
- Неподавленных уязвимостей: **0** (Всего в отчете: 0)
### 2. NPM production-зависимости (mediatracker-ui)

- Статус: **✅ PASS**
- Просканировано production-пакетов: **4**
- Уязвимости: Critical: **0**, High: **0**, Moderate: **0**, Low: **0** (Всего: **0**)

### 3. Статический скан утечек секретов (Secret Leak Scan)

- Статус: **✅ PASS**
- Просканировано файлов в репозитории: **571** (.cs, .ts, .svelte, .json)
- Обнаружено приватных ключей / токенов: **0**

### Артефакты и интерактивные отчеты

- 🌐 [Интерактивный HTML-дашборд аудита](reports/audit-report.html)
- 🗺️ [Интерактивная карта бандла Vite](reports/bundle-stats.html)
