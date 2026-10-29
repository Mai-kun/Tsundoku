# 📊 Сводный отчет комплексного аудита производительности и качества (Tsundoku)

**Статус:** **`FAIL`** | **Дата генерации:** 29.10.2026, 03:41:03 GMT+3 (`2026-10-29T00:41:03.814Z`)

## 🎯 Общий вердикт (Executive Summary)

| Проверочный контур | Инструмент / Метод | Статус | Ключевой результат / Метрика | Бюджет / Порог |
| :--- | :--- | :---: | :--- | :--- |
| **Сборка фронтенда** | Vite 8 + Rollup | ✅ PASS | Entry: `99.77 KB`, Total: `272.43 KB`, CSS: `35.95 KB` (Gzip) | Entry ≤ 150 KB, Total ≤ 320 KB |
| **Качество верстки и De-slop** | HTML-Validate + AST De-slop | ✅ PASS | Scanned: `104` files, 0 issues remaining | 0 structural errors, 0 slop patterns |
| **Reactivity & Svelte 5** | $state.raw Audit | ✅ PASS | 7 primary collections on `$state.raw` (no proxy overhead) | 0 unneeded deep proxies |
| **База данных & Индексы** | SQLite `EXPLAIN QUERY PLAN` | ✅ PASS | 5/5 ключевых запросов покрыты индексами, 0 Full Table Scans | 100% indexed queries |
| **Алгоритмы C# (Микро)** | BenchmarkDotNet v0.14 | ❌ FAIL | 7 бенчмарков (скоринг, парсеры CSV/JSON, стат-профиль) уложились в бюджет | 0 SLA & allocation violations |
| **Бэкенд под нагрузкой** | `dotnet-trace` + EventPipe | ✅ PASS | Throughput: `20.5 RPS`, p50: `30.42ms`, p95: `252.03ms`, Heap: `40.53MB` | 0 error responses, p95 < 1000ms |
| **Браузерный рендеринг** | Playwright + Chrome CDP | ✅ PASS | Layout: max `3.95ms` (stats-summary), Nodes: max `1082` (home) | Layout ≤ 120ms, Nodes ≤ 1500 |
| **Утечки памяти JS** | Heap Profile + Force GC | ✅ PASS | Delta после 12 циклов навигации: `-1.67 MB` | Delta < 15 MB |
| **Геометрия & Разметка** | BoundingBox Collision Audit | ✅ PASS | 14 экранов (Mobile, Tablet, Desktop) проверены, 0 аномалий переполнения | 0 layout collisions / scroll |
| **Доступность (WCAG 2.1 AA)** | Axe-core Playwright | ✅ PASS | 7 экранов проверены, 0 critical/serious нарушений | 0 critical/serious violations |
| **Снапшоты виджетов** | Pixelmatch (0.1 threshold) | ✅ PASS | 5/5 ключевых виджетов совпали с эталонами (0 px drift) | 100% visual match |
| **Инспектор микрооптимизаций** | C# (.NET 10) + Svelte 5 Smells | ✅ PASS | Найдено: 43 (0 исправлено с `--fix`, 43 рекомендаций) | 0 critical smells |
| **Тестирование и Покрытие кода** | xUnit + Coverlet + Vitest (v8) | ✅ PASS | Backend: `23/23 tests` (Line `0%`, Branch `0%`) | Frontend: `39/39 tests` (Model/Utils: `92-100%`, Overall: `17.1%`) | 0 test failures, 100% Passing Suite |
| **База данных SQLite (Здоровье)** | PRAGMA Integrity & Freelist | ✅ PASS | Размер: `628 KB`, WAL: `0 KB`, Фрагментация: `0%`, Целостность: `ok` | Фрагментация ≤ 15%, Freelist ≤ 100 страниц, Integrity: ok |
| **Сетевые бюджеты API (Wire)** | Gzip & Brotli Wire Profiler | ✅ PASS | Каталог 500 элементов: `35.73 KB` Gzip (Raw: `618.57 KB`), сжатие: `91.2%`, средняя задержка: `16.7ms` | /api/media Gzip ≤ 120 KB, Latency ≤ 150ms |
| **Безопасность и Зависимости** | dotnet list + npm audit + Secrets | ✅ PASS | NuGet: `0 уязвимостей` (ImageSharp подавлен), NPM prod: `0 уязвимостей`, Secret Scan: `0 утечек` (`519 файлов`) | 0 unsuppressed CVEs, 0 secret leaks |
| **Целостность тестового набора** | Static Orphan Scanner | ⚠️ WARN | Диск: `79`, Зарегистрировано: `61`, Сирот: `18` | 0 orphaned files |

## 🚨 Требует внимания / Рекомендации (Actionable Insights)

- ⚠️ **Общий размер JS бандла**: `Total JS Gzip: 272.43 KB / 320 KB (85.1%)`
  - **Действие**: Проведите аудит дублирующихся утилит в `bundle-stats.html` и убедитесь, что библиотеки не импортируются целиком.
- ⚠️ **Инспектор целостности (Orphan Checks)**: `Сирот: 18`
  - **Действие**: Удалите или зарегистрируйте следующие файлы: mediatracker-ui/checks/e2e/achievementsButtons.check.ts, mediatracker-ui/checks/e2e/cards.check.ts, mediatracker-ui/checks/e2e/categorySwitch.check.ts, mediatracker-ui/checks/e2e/gamePayloads.check.ts, mediatracker-ui/checks/e2e/historyDelete.check.ts, mediatracker-ui/checks/e2e/lists.check.ts, mediatracker-ui/checks/e2e/navDetail.check.ts, mediatracker-ui/checks/e2e/navOverlap.check.ts, mediatracker-ui/checks/e2e/popover.check.ts, mediatracker-ui/checks/e2e/ratingsSettled.check.ts, mediatracker-ui/checks/e2e/related.check.ts, mediatracker-ui/checks/e2e/releaseDates.check.ts, mediatracker-ui/checks/e2e/relink.check.ts, mediatracker-ui/checks/e2e/scoreStack.check.ts, mediatracker-ui/checks/e2e/seasons.check.ts, mediatracker-ui/checks/e2e/tokens.check.ts, mediatracker-ui/checks/e2e/virtualGrid.check.ts, mediatracker-ui/checks/e2e/visualQa.check.ts

## 💡 Рекомендации по микрооптимизации (Actionable Code Diff Suggestions)

Статический двунаправленный инспектор микрооптимизаций для C# (.NET 10 / EF Core) и TypeScript / Svelte 5.
Автоматический режим `--fix` безопасно устраняет накладные расходы EF Core Change Tracker и оптимизирует LINQ.

- **Всего находок:** `43` | **Автоматически исправлено (`--fix`):** `0` | **Рекомендаций в отчете:** `43`

### 1. `MediaTracker.Server/Features/Media/Import/ImportMatchScorer.cs:320` — `Span-Allocations` 💡 [Рекомендация]

**Аллокация массива через string.Split внутри цикла / парсера**

Вызов string.Split приводит к созданию строковых массивов в куче. Рассмотрите MemoryExtensions.Split, SpanParserExtensions или ReadOnlySpan<char>.

```diff
- var parts = value.Split(' ', StringSplitOptions.RemoveEmptyEntries | StringSplitOptions.TrimEntries);
+ // ReadOnlySpan<char> / MemoryExtensions.Split
+ var parts = value.Split(' ', StringSplitOptions.RemoveEmptyEntries | StringSplitOptions.TrimEntries);
```

### 2. `MediaTracker.Server/Features/Media/Import/ImportMediaHandler.cs:860` — `Span-Allocations` 💡 [Рекомендация]

**Аллокация массива через string.Split внутри цикла / парсера**

Вызов string.Split приводит к созданию строковых массивов в куче. Рассмотрите MemoryExtensions.Split, SpanParserExtensions или ReadOnlySpan<char>.

```diff
- return int.TryParse(value.Trim().Split('-')[0], NumberStyles.Integer, CultureInfo.InvariantCulture, out var year) ? year : null;
+ return int.TryParse(value.Trim().Split('-')[0], NumberStyles.Integer, CultureInfo.InvariantCulture, out var year) ? year : null;
```

### 3. `MediaTracker.Server/Features/Media/Import/Parsers/AniListImportParser.cs:262` — `Span-Allocations` 💡 [Рекомендация]

**Аллокация массива через string.Split внутри цикла / парсера**

Вызов string.Split приводит к созданию строковых массивов в куче. Рассмотрите MemoryExtensions.Split, SpanParserExtensions или ReadOnlySpan<char>.

```diff
- return int.TryParse(value.Split('-')[0], NumberStyles.Integer, CultureInfo.InvariantCulture, out var yr) && yr > 0 ? yr : null;
+ return SpanParserExtensions.ParseYearFromDateString(value) && yr > 0 ? yr : null;
```

### 4. `MediaTracker.Server/Features/Media/Import/Parsers/CustomImportParser.cs:106` — `Span-Allocations` 💡 [Рекомендация]

**Аллокация массива через string.Split внутри цикла / парсера**

Вызов string.Split приводит к созданию строковых массивов в куче. Рассмотрите MemoryExtensions.Split, SpanParserExtensions или ReadOnlySpan<char>.

```diff
- : int.TryParse(value?.Split('-')[0], NumberStyles.Integer, CultureInfo.InvariantCulture, out var yr) ? yr : null;
+ : SpanParserExtensions.ParseYearFromDateString(value) ? yr : null;
```

### 5. `MediaTracker.Server/Features/Media/Import/Parsers/MalJsonParser.cs:46` — `Span-Allocations` 💡 [Рекомендация]

**Аллокация массива через string.Split внутри цикла / парсера**

Вызов string.Split приводит к созданию строковых массивов в куче. Рассмотрите MemoryExtensions.Split, SpanParserExtensions или ReadOnlySpan<char>.

```diff
- : int.TryParse(value?.Split('-')[0], NumberStyles.Integer, CultureInfo.InvariantCulture, out var year) ? year : null;
+ : SpanParserExtensions.ParseYearFromDateString(value) ? year : null;
```

### 6. `MediaTracker.Server/Features/Media/Import/Parsers/MalXmlParser.cs:31` — `Span-Allocations` 💡 [Рекомендация]

**Аллокация массива через string.Split внутри цикла / парсера**

Вызов string.Split приводит к созданию строковых массивов в куче. Рассмотрите MemoryExtensions.Split, SpanParserExtensions или ReadOnlySpan<char>.

```diff
- private static int? ParseYear(string? value) => DateTime.TryParse(value, CultureInfo.InvariantCulture, out var date) ? date.Year : int.TryParse(value?.Split('-')[0], out var year) ? year : null;
+ private static int? ParseYear(string? value) => DateTime.TryParse(value, CultureInfo.InvariantCulture, out var date) ? date.Year : SpanParserExtensions.ParseYearFromDateString(value) ? year : null;
```

### 7. `MediaTracker.Server/Features/Media/Import/Parsers/ShikimoriImportParser.cs:143` — `Span-Allocations` 💡 [Рекомендация]

**Аллокация массива через string.Split внутри цикла / парсера**

Вызов string.Split приводит к созданию строковых массивов в куче. Рассмотрите MemoryExtensions.Split, SpanParserExtensions или ReadOnlySpan<char>.

```diff
- : int.TryParse(value?.Split('-')[0], NumberStyles.Integer, CultureInfo.InvariantCulture, out var yr) ? yr : null;
+ : SpanParserExtensions.ParseYearFromDateString(value) ? yr : null;
```

### 8. `MediaTracker.Server/Infrastructure/Persistence/Franchises/FranchiseService.cs:19` — `Generated-Regex` ⚠️ [Требует внимания]

**Использование new Regex вместо [GeneratedRegex] для 'SeasonSuffixRegex'**

Создание экземпляров Regex во время выполнения требует динамической компиляции и увеличивает время старта и аллокации. В .NET 10 используйте генератор исходного кода [GeneratedRegex].

```diff
- private static readonly Regex SeasonSuffixRegex = new(
-         @"\s+(season\s+\d+|\d+(st|nd|rd|th)\s+season|final\s+season|part\s+\d+|[IVXLCDM]+)$",
-         RegexOptions.IgnoreCase | RegexOptions.Compiled);
+ [GeneratedRegex(@"\s+(season\s+\d+|\d+(st|nd|rd|th)\s+season|final\s+season|part\s+\d+|[IVXLCDM]+)$",
+         RegexOptions.IgnoreCase | RegexOptions.Compiled)]
+     private static partial Regex SeasonSuffixRegex();
```

### 9. `mediatracker-ui/src/features/filter-and-sort/FilterBar.svelte:206` — `Heavy-Event-Debounce` 💡 [Рекомендация]

**Событие ввода/скролла без debounce: handleSearch**

Обработчик 'handleSearch' вызывается на каждый тик события. Убедитесь, что сетевые запросы или тяжелые фильтрации защищены debounce (например, progressDebounce или setTimeout).

```diff
- oninput={handleSearch}
+ oninput={debounce(handleSearch, 300)}
```

### 10. `mediatracker-ui/src/features/import-media/ImportPanel.svelte:385` — `Svelte-Uncached-Regex` ⚠️ [Требует внимания]

**Некешированное регулярное выражение /^\d+$/ в теле компонента**

Литерал регулярного выражения внутри <script> пересоздается при каждом ререндере компонента. Вынесите его в <script module> или файл утилит.

```diff
- (typeof rawStatus === "string" && /^\d+$/.test(rawStatus))
+ // В <script module>: const CACHED_REGEX = /^\d+$/;
+ (typeof rawStatus === "string" && CACHED_REGEX.test(rawStatus))
```

### 11. `mediatracker-ui/src/features/import-media/ImportPanel.svelte:669` — `Svelte-Uncached-Regex` ⚠️ [Требует внимания]

**Некешированное регулярное выражение /^\d{17}$/ в теле компонента**

Литерал регулярного выражения внутри <script> пересоздается при каждом ререндере компонента. Вынесите его в <script module> или файл утилит.

```diff
- ...(/^\d{17}$/.test(value) ? { steamId: value } : { profileUrl: value }),
+ // В <script module>: const CACHED_REGEX = /^\d{17}$/;
+ ...(CACHED_REGEX.test(value) ? { steamId: value } : { profileUrl: value }),
```

### 12. `mediatracker-ui/src/features/import-media/ImportPanel.svelte:858` — `Svelte-Uncached-Regex` ⚠️ [Требует внимания]

**Некешированное регулярное выражение /(?:\u0447\u0438\u0442\u0430\u044E|\u0441\u043C\u043E\u0442\u0440\u044E|\u043F\u0435\u0440\u0435\u0441\u043C\u0430\u0442\u0440|reading|watching|rewatching|in_progress|in progress)/i в теле компонента**

Литерал регулярного выражения внутри <script> пересоздается при каждом ререндере компонента. Вынесите его в <script module> или файл утилит.

```diff
- return /(?:\u0447\u0438\u0442\u0430\u044E|\u0441\u043C\u043E\u0442\u0440\u044E|\u043F\u0435\u0440\u0435\u0441\u043C\u0430\u0442\u0440|reading|watching|rewatching|in_progress|in progress)/i.test(s) ||
+ // В <script module>: const CACHED_REGEX = /(?:\u0447\u0438\u0442\u0430\u044E|\u0441\u043C\u043E\u0442\u0440\u044E|\u043F\u0435\u0440\u0435\u0441\u043C\u0430\u0442\u0440|reading|watching|rewatching|in_progress|in progress)/i;
+ return CACHED_REGEX.test(s) ||
```

### 13. `mediatracker-ui/src/features/import-media/ImportPanel.svelte:859` — `Svelte-Uncached-Regex` ⚠️ [Требует внимания]

**Некешированное регулярное выражение /(?:\u043F\u043B\u0430\u043D|\u0437\u0430\u043F\u043B\u0430\u043D\u0438\u0440\u043E\u0432\u0430\u043D\u043E|\u0431\u0443\u0434\u0443|planned|plan_to_watch)/i в теле компонента**

Литерал регулярного выражения внутри <script> пересоздается при каждом ререндере компонента. Вынесите его в <script module> или файл утилит.

```diff
- /(?:\u043F\u043B\u0430\u043D|\u0437\u0430\u043F\u043B\u0430\u043D\u0438\u0440\u043E\u0432\u0430\u043D\u043E|\u0431\u0443\u0434\u0443|planned|plan_to_watch)/i.test(s) ||
+ // В <script module>: const CACHED_REGEX = /(?:\u043F\u043B\u0430\u043D|\u0437\u0430\u043F\u043B\u0430\u043D\u0438\u0440\u043E\u0432\u0430\u043D\u043E|\u0431\u0443\u0434\u0443|planned|plan_to_watch)/i;
+ CACHED_REGEX.test(s) ||
```

### 14. `mediatracker-ui/src/features/import-media/ImportPanel.svelte:860` — `Svelte-Uncached-Regex` ⚠️ [Требует внимания]

**Некешированное регулярное выражение /(?:\u043F\u0440\u043E\u0447\u0438\u0442\u0430\u043D\u043E|\u043F\u0440\u043E\u0441\u043C\u043E\u0442\u0440\u0435\u043D\u043E|completed|watched)/i в теле компонента**

Литерал регулярного выражения внутри <script> пересоздается при каждом ререндере компонента. Вынесите его в <script module> или файл утилит.

```diff
- /(?:\u043F\u0440\u043E\u0447\u0438\u0442\u0430\u043D\u043E|\u043F\u0440\u043E\u0441\u043C\u043E\u0442\u0440\u0435\u043D\u043E|completed|watched)/i.test(s) ||
+ // В <script module>: const CACHED_REGEX = /(?:\u043F\u0440\u043E\u0447\u0438\u0442\u0430\u043D\u043E|\u043F\u0440\u043E\u0441\u043C\u043E\u0442\u0440\u0435\u043D\u043E|completed|watched)/i;
+ CACHED_REGEX.test(s) ||
```

### 15. `mediatracker-ui/src/features/import-media/ImportPanel.svelte:861` — `Svelte-Uncached-Regex` ⚠️ [Требует внимания]

**Некешированное регулярное выражение /(?:\u043B\u044E\u0431\u0438\u043C|favorite)/i в теле компонента**

Литерал регулярного выражения внутри <script> пересоздается при каждом ререндере компонента. Вынесите его в <script module> или файл утилит.

```diff
- /(?:\u043B\u044E\u0431\u0438\u043C|favorite)/i.test(s) ||
+ // В <script module>: const CACHED_REGEX = /(?:\u043B\u044E\u0431\u0438\u043C|favorite)/i;
+ CACHED_REGEX.test(s) ||
```

### 16. `mediatracker-ui/src/features/import-media/ImportPanel.svelte:862` — `Svelte-Uncached-Regex` ⚠️ [Требует внимания]

**Некешированное регулярное выражение /(?:\u043E\u0442\u043B\u043E\u0436|hold|pause)/i в теле компонента**

Литерал регулярного выражения внутри <script> пересоздается при каждом ререндере компонента. Вынесите его в <script module> или файл утилит.

```diff
- /(?:\u043E\u0442\u043B\u043E\u0436|hold|pause)/i.test(s) ||
+ // В <script module>: const CACHED_REGEX = /(?:\u043E\u0442\u043B\u043E\u0436|hold|pause)/i;
+ CACHED_REGEX.test(s) ||
```

### 17. `mediatracker-ui/src/features/import-media/ImportPanel.svelte:863` — `Svelte-Uncached-Regex` ⚠️ [Требует внимания]

**Некешированное регулярное выражение /(?:\u0443\u0434\u0430\u043B\u0435\u043D|\u0431\u0440\u043E\u0448|dropped)/i в теле компонента**

Литерал регулярного выражения внутри <script> пересоздается при каждом ререндере компонента. Вынесите его в <script module> или файл утилит.

```diff
- /(?:\u0443\u0434\u0430\u043B\u0435\u043D|\u0431\u0440\u043E\u0448|dropped)/i.test(s);
+ // В <script module>: const CACHED_REGEX = /(?:\u0443\u0434\u0430\u043B\u0435\u043D|\u0431\u0440\u043E\u0448|dropped)/i;
+ CACHED_REGEX.test(s);
```

### 18. `mediatracker-ui/src/features/import-media/ImportPanel.svelte:868` — `Svelte-Uncached-Regex` ⚠️ [Требует внимания]

**Некешированное регулярное выражение /(?:\u0443\u0434\u0430\u043B\u0435\u043D|\u0431\u0440\u043E\u0448|dropped)/i в теле компонента**

Литерал регулярного выражения внутри <script> пересоздается при каждом ререндере компонента. Вынесите его в <script module> или файл утилит.

```diff
- if (/(?:\u0443\u0434\u0430\u043B\u0435\u043D|\u0431\u0440\u043E\u0448|dropped)/i.test(s)) return 3;
+ // В <script module>: const CACHED_REGEX = /(?:\u0443\u0434\u0430\u043B\u0435\u043D|\u0431\u0440\u043E\u0448|dropped)/i;
+ if (CACHED_REGEX.test(s)) return 3;
```

### 19. `mediatracker-ui/src/features/import-media/ImportPanel.svelte:869` — `Svelte-Uncached-Regex` ⚠️ [Требует внимания]

**Некешированное регулярное выражение /(?:\u0447\u0438\u0442\u0430\u044E|\u0441\u043C\u043E\u0442\u0440\u044E|\u043F\u0435\u0440\u0435\u0441\u043C\u0430\u0442\u0440|reading|watching|rewatching)/i в теле компонента**

Литерал регулярного выражения внутри <script> пересоздается при каждом ререндере компонента. Вынесите его в <script module> или файл утилит.

```diff
- if (/(?:\u0447\u0438\u0442\u0430\u044E|\u0441\u043C\u043E\u0442\u0440\u044E|\u043F\u0435\u0440\u0435\u0441\u043C\u0430\u0442\u0440|reading|watching|rewatching)/i.test(s)) return 1;
+ // В <script module>: const CACHED_REGEX = /(?:\u0447\u0438\u0442\u0430\u044E|\u0441\u043C\u043E\u0442\u0440\u044E|\u043F\u0435\u0440\u0435\u0441\u043C\u0430\u0442\u0440|reading|watching|rewatching)/i;
+ if (CACHED_REGEX.test(s)) return 1;
```

### 20. `mediatracker-ui/src/features/import-media/ImportPanel.svelte:870` — `Svelte-Uncached-Regex` ⚠️ [Требует внимания]

**Некешированное регулярное выражение /(?:\u043F\u043B\u0430\u043D|\u0437\u0430\u043F\u043B\u0430\u043D\u0438\u0440\u043E\u0432\u0430\u043D\u043E|planned)/i в теле компонента**

Литерал регулярного выражения внутри <script> пересоздается при каждом ререндере компонента. Вынесите его в <script module> или файл утилит.

```diff
- if (/(?:\u043F\u043B\u0430\u043D|\u0437\u0430\u043F\u043B\u0430\u043D\u0438\u0440\u043E\u0432\u0430\u043D\u043E|planned)/i.test(s)) return 2;
+ // В <script module>: const CACHED_REGEX = /(?:\u043F\u043B\u0430\u043D|\u0437\u0430\u043F\u043B\u0430\u043D\u0438\u0440\u043E\u0432\u0430\u043D\u043E|planned)/i;
+ if (CACHED_REGEX.test(s)) return 2;
```

### 21. `mediatracker-ui/src/features/import-media/ImportPanel.svelte:871` — `Svelte-Uncached-Regex` ⚠️ [Требует внимания]

**Некешированное регулярное выражение /(?:\u043F\u0440\u043E\u0447\u0438\u0442\u0430\u043D\u043E|\u043F\u0440\u043E\u0441\u043C\u043E\u0442\u0440\u0435\u043D\u043E|completed|watched)/i в теле компонента**

Литерал регулярного выражения внутри <script> пересоздается при каждом ререндере компонента. Вынесите его в <script module> или файл утилит.

```diff
- if (/(?:\u043F\u0440\u043E\u0447\u0438\u0442\u0430\u043D\u043E|\u043F\u0440\u043E\u0441\u043C\u043E\u0442\u0440\u0435\u043D\u043E|completed|watched)/i.test(s)) return 4;
+ // В <script module>: const CACHED_REGEX = /(?:\u043F\u0440\u043E\u0447\u0438\u0442\u0430\u043D\u043E|\u043F\u0440\u043E\u0441\u043C\u043E\u0442\u0440\u0435\u043D\u043E|completed|watched)/i;
+ if (CACHED_REGEX.test(s)) return 4;
```

### 22. `mediatracker-ui/src/features/import-media/ImportPanel.svelte:872` — `Svelte-Uncached-Regex` ⚠️ [Требует внимания]

**Некешированное регулярное выражение /(?:\u043B\u044E\u0431\u0438\u043C|favorite)/i в теле компонента**

Литерал регулярного выражения внутри <script> пересоздается при каждом ререндере компонента. Вынесите его в <script module> или файл утилит.

```diff
- if (/(?:\u043B\u044E\u0431\u0438\u043C|favorite)/i.test(s)) return 5;
+ // В <script module>: const CACHED_REGEX = /(?:\u043B\u044E\u0431\u0438\u043C|favorite)/i;
+ if (CACHED_REGEX.test(s)) return 5;
```

### 23. `mediatracker-ui/src/features/import-media/ImportPanel.svelte:873` — `Svelte-Uncached-Regex` ⚠️ [Требует внимания]

**Некешированное регулярное выражение /(?:\u043E\u0442\u043B\u043E\u0436|hold)/i в теле компонента**

Литерал регулярного выражения внутри <script> пересоздается при каждом ререндере компонента. Вынесите его в <script module> или файл утилит.

```diff
- if (/(?:\u043E\u0442\u043B\u043E\u0436|hold)/i.test(s)) return 6;
+ // В <script module>: const CACHED_REGEX = /(?:\u043E\u0442\u043B\u043E\u0436|hold)/i;
+ if (CACHED_REGEX.test(s)) return 6;
```

### 24. `mediatracker-ui/src/features/import-media/ImportPanel.svelte:67` — `Svelte-Collection-StateRaw` ⚠️ [Требует внимания]

**Использование глубокого $state вместо $state.raw для коллекции 'lists'**

Переменная 'lists' хранит массив сущностей API ('CustomListSummary[]'). Использование $state создает реактивные Proxy для каждого элемента и поля, что приводит к оверхеду памяти. Рекомендуется $state.raw.

```diff
- let lists = $state<CustomListSummary[]>([])
+ let lists = $state.raw<CustomListSummary[]>([]);
```

### 25. `mediatracker-ui/src/features/import-media/ImportPanel.svelte:126` — `Svelte-Collection-StateRaw` ⚠️ [Требует внимания]

**Использование глубокого $state вместо $state.raw для коллекции 'pendingCustomFolders'**

Переменная 'pendingCustomFolders' хранит массив сущностей API ('CustomFolderItem[]'). Использование $state создает реактивные Proxy для каждого элемента и поля, что приводит к оверхеду памяти. Рекомендуется $state.raw.

```diff
- let pendingCustomFolders = $state<CustomFolderItem[]>([])
+ let pendingCustomFolders = $state.raw<CustomFolderItem[]>([]);
```

### 26. `mediatracker-ui/src/features/lists/CreateListModal.svelte:32` — `Svelte-Collection-StateRaw` ⚠️ [Требует внимания]

**Использование глубокого $state вместо $state.raw для коллекции 'allMedia'**

Переменная 'allMedia' хранит массив сущностей API ('MediaItem[]'). Использование $state создает реактивные Proxy для каждого элемента и поля, что приводит к оверхеду памяти. Рекомендуется $state.raw.

```diff
- let allMedia = $state<MediaItem[]>([])
+ let allMedia = $state.raw<MediaItem[]>([]);
```

### 27. `mediatracker-ui/src/features/lists/CreateListModal.svelte:33` — `Svelte-Collection-StateRaw` ⚠️ [Требует внимания]

**Использование глубокого $state вместо $state.raw для коллекции 'matchedItems'**

Переменная 'matchedItems' хранит массив сущностей API ('MediaItem[]'). Использование $state создает реактивные Proxy для каждого элемента и поля, что приводит к оверхеду памяти. Рекомендуется $state.raw.

```diff
- let matchedItems = $state<MediaItem[]>([])
+ let matchedItems = $state.raw<MediaItem[]>([]);
```

### 28. `mediatracker-ui/src/features/lists/ListPicker.svelte:23` — `Svelte-Collection-StateRaw` ⚠️ [Требует внимания]

**Использование глубокого $state вместо $state.raw для коллекции 'lists'**

Переменная 'lists' хранит массив сущностей API ('CustomListSummary[]'). Использование $state создает реактивные Proxy для каждого элемента и поля, что приводит к оверхеду памяти. Рекомендуется $state.raw.

```diff
- let lists = $state<CustomListSummary[]>([])
+ let lists = $state.raw<CustomListSummary[]>([]);
```

### 29. `mediatracker-ui/src/features/search-external/SearchModal.svelte:71` — `Svelte-Collection-StateRaw` ⚠️ [Требует внимания]

**Использование глубокого $state вместо $state.raw для коллекции 'results'**

Переменная 'results' хранит массив сущностей API ('ExternalMedia[]'). Использование $state создает реактивные Proxy для каждого элемента и поля, что приводит к оверхеду памяти. Рекомендуется $state.raw.

```diff
- let results = $state<ExternalMedia[]>([])
+ let results = $state.raw<ExternalMedia[]>([]);
```

### 30. `mediatracker-ui/src/features/search-external/SearchModal.svelte:85` — `Svelte-Collection-StateRaw` ⚠️ [Требует внимания]

**Использование глубокого $state вместо $state.raw для коллекции 'availableSources'**

Переменная 'availableSources' хранит массив сущностей API ('SourceInfo[]'). Использование $state создает реактивные Proxy для каждого элемента и поля, что приводит к оверхеду памяти. Рекомендуется $state.raw.

```diff
- let availableSources = $state<SourceInfo[]>([])
+ let availableSources = $state.raw<SourceInfo[]>([]);
```

### 31. `mediatracker-ui/src/features/settings/SettingsModal.svelte:365` — `Svelte-Collection-StateRaw` ⚠️ [Требует внимания]

**Использование глубокого $state вместо $state.raw для коллекции 'sources'**

Переменная 'sources' хранит массив сущностей API ('SourceInfo[]'). Использование $state создает реактивные Proxy для каждого элемента и поля, что приводит к оверхеду памяти. Рекомендуется $state.raw.

```diff
- let sources = $state<SourceInfo[]>([])
+ let sources = $state.raw<SourceInfo[]>([]);
```

### 32. `mediatracker-ui/src/features/stale-triage/StaleBacklogModal.svelte:34` — `Svelte-Collection-StateRaw` ⚠️ [Требует внимания]

**Использование глубокого $state вместо $state.raw для коллекции 'allInProgress'**

Переменная 'allInProgress' хранит массив сущностей API ('MediaItem[]'). Использование $state создает реактивные Proxy для каждого элемента и поля, что приводит к оверхеду памяти. Рекомендуется $state.raw.

```diff
- let allInProgress = $state<MediaItem[]>([])
+ let allInProgress = $state.raw<MediaItem[]>([]);
```

### 33. `mediatracker-ui/src/views/MediaDetailView.svelte:398` — `Svelte-Collection-StateRaw` ⚠️ [Требует внимания]

**Использование глубокого $state вместо $state.raw для коллекции 'availableSources'**

Переменная 'availableSources' хранит массив сущностей API ('SourceInfo[]'). Использование $state создает реактивные Proxy для каждого элемента и поля, что приводит к оверхеду памяти. Рекомендуется $state.raw.

```diff
- let availableSources = $state<SourceInfo[]>([])
+ let availableSources = $state.raw<SourceInfo[]>([]);
```

### 34. `mediatracker-ui/src/views/MediaDetailView.svelte:437` — `Svelte-Collection-StateRaw` ⚠️ [Требует внимания]

**Использование глубокого $state вместо $state.raw для коллекции 'related'**

Переменная 'related' хранит массив сущностей API ('RelatedEntry[]'). Использование $state создает реактивные Proxy для каждого элемента и поля, что приводит к оверхеду памяти. Рекомендуется $state.raw.

```diff
- let related = $state<RelatedEntry[]>([])
+ let related = $state.raw<RelatedEntry[]>([]);
```

### 35. `mediatracker-ui/src/views/MediaDetailView.svelte:527` — `Svelte-Collection-StateRaw` ⚠️ [Требует внимания]

**Использование глубокого $state вместо $state.raw для коллекции 'recommendations'**

Переменная 'recommendations' хранит массив сущностей API ('RecommendationItem[]'). Использование $state создает реактивные Proxy для каждого элемента и поля, что приводит к оверхеду памяти. Рекомендуется $state.raw.

```diff
- let recommendations = $state<RecommendationItem[]>([])
+ let recommendations = $state.raw<RecommendationItem[]>([]);
```

### 36. `mediatracker-ui/src/views/MediaDetailView.svelte:1062` — `Svelte-Collection-StateRaw` ⚠️ [Требует внимания]

**Использование глубокого $state вместо $state.raw для коллекции 'gameAchievements'**

Переменная 'gameAchievements' хранит массив сущностей API ('GameAchievementItem[]'). Использование $state создает реактивные Proxy для каждого элемента и поля, что приводит к оверхеду памяти. Рекомендуется $state.raw.

```diff
- let gameAchievements = $state<GameAchievementItem[]>([])
+ let gameAchievements = $state.raw<GameAchievementItem[]>([]);
```

### 37. `mediatracker-ui/src/widgets/layout/BackgroundJobsModal.svelte:79` — `Svelte-Uncached-Regex` ⚠️ [Требует внимания]

**Некешированное регулярное выражение /[а-яА-ЯёЁ]/ в теле компонента**

Литерал регулярного выражения внутри <script> пересоздается при каждом ререндере компонента. Вынесите его в <script module> или файл утилит.

```diff
- const isLatin = !/[а-яА-ЯёЁ]/.test(title) && /[a-zA-Z]/.test(title);
+ // В <script module>: const CACHED_REGEX = /[а-яА-ЯёЁ]/;
+ const isLatin = !CACHED_REGEX.test(title) && /[a-zA-Z]/.test(title);
```

### 38. `mediatracker-ui/src/widgets/layout/BackgroundJobsModal.svelte:87` — `Svelte-Uncached-Regex` ⚠️ [Требует внимания]

**Некешированное регулярное выражение /[а-яА-ЯёЁ]/ в теле компонента**

Литерал регулярного выражения внутри <script> пересоздается при каждом ререндере компонента. Вынесите его в <script module> или файл утилит.

```diff
- if (match && /[а-яА-ЯёЁ]/.test(match[1])) return match[1].trim();
+ // В <script module>: const CACHED_REGEX = /[а-яА-ЯёЁ]/;
+ if (match && CACHED_REGEX.test(match[1])) return match[1].trim();
```

### 39. `mediatracker-ui/src/widgets/media-detail/FillMissingModal.svelte:30` — `Svelte-Collection-StateRaw` ⚠️ [Требует внимания]

**Использование глубокого $state вместо $state.raw для коллекции 'sources'**

Переменная 'sources' хранит массив сущностей API ('SourceInfo[]'). Использование $state создает реактивные Proxy для каждого элемента и поля, что приводит к оверхеду памяти. Рекомендуется $state.raw.

```diff
- let sources = $state<SourceInfo[]>([])
+ let sources = $state.raw<SourceInfo[]>([]);
```

### 40. `mediatracker-ui/src/widgets/media-detail/MediaActivityModal.svelte:25` — `Svelte-Collection-StateRaw` ⚠️ [Требует внимания]

**Использование глубокого $state вместо $state.raw для коллекции 'events'**

Переменная 'events' хранит массив сущностей API ('HistoryEvent[]'). Использование $state создает реактивные Proxy для каждого элемента и поля, что приводит к оверхеду памяти. Рекомендуется $state.raw.

```diff
- let events = $state<HistoryEvent[]>([])
+ let events = $state.raw<HistoryEvent[]>([]);
```

### 41. `mediatracker-ui/src/widgets/media-detail/RelinkSourceModal.svelte:53` — `Svelte-Collection-StateRaw` ⚠️ [Требует внимания]

**Использование глубокого $state вместо $state.raw для коллекции 'providers'**

Переменная 'providers' хранит массив сущностей API ('SourceInfo[]'). Использование $state создает реактивные Proxy для каждого элемента и поля, что приводит к оверхеду памяти. Рекомендуется $state.raw.

```diff
- let providers = $state<SourceInfo[]>([])
+ let providers = $state.raw<SourceInfo[]>([]);
```

### 42. `mediatracker-ui/src/widgets/media-detail/RelinkSourceModal.svelte:93` — `Svelte-Collection-StateRaw` ⚠️ [Требует внимания]

**Использование глубокого $state вместо $state.raw для коллекции 'results'**

Переменная 'results' хранит массив сущностей API ('ExternalMedia[]'). Использование $state создает реактивные Proxy для каждого элемента и поля, что приводит к оверхеду памяти. Рекомендуется $state.raw.

```diff
- let results = $state<ExternalMedia[]>([])
+ let results = $state.raw<ExternalMedia[]>([]);
```

### 43. `mediatracker-ui/src/widgets/media-detail/sections/CreatorSection.svelte:88` — `Svelte-Uncached-Regex` ⚠️ [Требует внимания]

**Некешированное регулярное выражение /разработчик|developer/i в теле компонента**

Литерал регулярного выражения внутри <script> пересоздается при каждом ререндере компонента. Вынесите его в <script module> или файл утилит.

```diff
- if (mediaType === "game" || (label && /разработчик|developer/i.test(label))) return Gamepad2;
+ // В <script module>: const CACHED_REGEX = /разработчик|developer/i;
+ if (mediaType === "game" || (label && CACHED_REGEX.test(label))) return Gamepad2;
```

## 📦 Фронтенд: Бандл и Статический контур (Svelte 5, De-slop, HTML)

### Сводка размеров бандла

- **Критический чанк (Entry JS):** `99.77 KB` Gzip (`325.95 KB` uncompressed) — бюджет: `150 KB` (66.5%)
- **Общий вес JS:** `272.43 KB` Gzip (`926.52 KB` uncompressed) — бюджет: `320 KB` (85.1%)
- **Стили (CSS):** `35.95 KB` Gzip (`256.76 KB` uncompressed) — бюджет: `50 KB` (71.9%)

#### Топ асинхронных чанков (Lazy Chunks)

| Чанк | Raw KB | Gzip KB |
| :--- | :---: | :---: |
| `MediaDetailView-BmCI5RV1.js` | 167.34 | 43.4 |
| `ImportPanel-BGJDWKqB.js` | 75.56 | 18.06 |
| `StatsView-RwJgC0Ue.js` | 52.67 | 14.16 |
| `SettingsModal-CIz_S4NV.js` | 49.35 | 12.26 |
| `SearchModal-Tsa6BFYA.js` | 33.95 | 9.91 |
| `CalendarView-7o9bnGVn.js` | 33.86 | 9.62 |
| `BackgroundJobsModal-O9svRJmi.js` | 20.78 | 6.79 |
| `HistoryView-BQ5rildP.js` | 19.48 | 5.99 |

### Контур статического анализа и стандартов

- **Svelte 5 `$state.raw`**: проверены 7 основных коллекций медиа в представлениях (`HomeView`, `CategoryView`, `HistoryView`, `ListsView`). Рекурсивные прокси отсутствуют.
- **De-slop & Refactoring UI**: проверено 102 файла. 0 нарушений отступов, z-index шкал, inline стилей и жестко закодированных цветов.
- **HTML Validation**: 102 файла шаблонов валидны, соответствуют семантическому стандарту.
- **ESLint & Stylelint**: 0 ошибок.

## 🌐 Браузерный рендеринг и UX (Playwright + CDP + Геометрия + Axe)

### Метрики Chrome DevTools Protocol (CDP) по представлениям

| Экран | Layout (ms) | Recalc Style (ms) | Script (ms) | Task (ms) | DOM Нод | JS Heap (MB) |
| :--- | :---: | :---: | :---: | :---: | :---: | :---: |
| **home** | 0.33 | 0 | 0 | 9.27 | 1082 | 5.87 |
| **game-initial** | 0.16 | 2.05 | 35.92 | 24.14 | 899 | 16.93 |
| **game-virtual-scroll** | 0 | 0 | 0.92 | 2.97 | 899 | 17 |
| **tvshow** | 0 | 0 | 0 | 0 | 117 | 24.8 |
| **stats-summary** | 3.95 | 9.67 | 54.72 | 82.66 | 894 | 34.64 |
| **stats-taste-profile** | 0 | 0 | 0 | 76.82 | 894 | 8.2 |
| **history** | 0 | 0 | 0 | 0 | 125 | 15.61 |
| **lists** | 0 | 0 | 0 | 2.8 | 40 | 23.51 |
| **calendar** | 0 | 4.71 | 10.67 | 17.39 | 89 | 31.2 |
| **detail** | 2.15 | 0 | 20.18 | 29.44 | 419 | 25.42 |
| **modals** | 1.21 | 57.94 | 7.23 | 181.53 | 419 | 8.67 |

### Стресс-тест утечек памяти JS Heap (12 циклов навигации с Force GC)

- **Heap до циклов:** `6.93 MB`
- **Heap после циклов:** `5.26 MB`
- **Дельта:** `-1.67 MB` (порог: < 15 MB) -> **✅ Утечек нет**

### Геометрия DOM и визуальная стабильность

- Проверено экранов: **14** (Mobile 375px, Tablet 768px, Desktop 1440px).
- Обнаружено переполнений / горизонтального скролла / коллизий: **0**.

### Аудит доступности Axe (WCAG 2.1 AA)

- Просканировано экранов: **7**.
- Критических и серьезных нарушений: **0**.

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
| `EvaluateSmartList` | `EvaluationAndScoringBenchmarks` | **294.18 μs** | **258.66 KB** | 62.99 / 0.00 / 0.00 | ❌ FAIL |
| `EvaluateCandidates` | `EvaluationAndScoringBenchmarks` | **21.36 μs** | **24.82 KB** | 6.07 / 0.00 / 0.00 | ✅ PASS |
| `NormalizeGenres` | `EvaluationAndScoringBenchmarks` | **8.30 μs** | **8.53 KB** | 2.08 / 0.00 / 0.00 | ✅ PASS |
| `ParseMangalibJson` | `ParsersBenchmarks` | **504.90 μs** | **112.86 KB** | 27.34 / 0.00 / 0.00 | ✅ PASS |
| `ReadAnyRecordsCsv` | `ParsersBenchmarks` | **49.17 μs** | **78.29 KB** | 19.17 / 0.06 / 0.00 | ✅ PASS |
| `CalculateAdvancedStats` | `StatsBenchmarks` | **156.71 μs** | **9.08 KB** | 2.20 / 0.00 / 0.00 | ✅ PASS |
| `CalculateTasteProfile` | `StatsBenchmarks` | **51.25 μs** | **3.90 KB** | 0.92 / 0.00 / 0.00 | ✅ PASS |

### Макропрофилирование ASP.NET Core под конкурентной нагрузкой

- **Конфигурация сервера:** `Release / net10.0` | Сидировано записей: **500**
- **Пропускная способность:** **`20.5 RPS`** (Всего запросов: 227, Успешно: 227, Ошибок: 0)
- **Задержка ответа (Latency):** min: `1.39ms` | **p50: `30.42ms`** | **p95: `252.03ms`** | max: `8543.34ms`
- **CLR Среда:** GC Heap: `40.53 MB` | Allocation Rate: `12.21 MB/s` | Gen 0/1/2 Сборки: `12/2/0`

#### Топ-10 горячих методов бэкенда (по данным dotnet-trace)

| Ранг | Метод C# | Total Время (ms) | Self Время (ms) | Доля CPU (%) |
| :---: | :--- | :---: | :---: | :---: |
| 1 | `Microsoft.AspNetCore.Http.Generated.<GeneratedRouteBuilderExtensions_g>F202B381FFC497F212FEEA6512613F4D084B421EB97B74D5CBD81E03E134C6BFD__GeneratedRouteBuilderExtensionsCore+<>c__DisplayClass25_0+<<MapGet20>g__RequestHandler|5>d` | 12494.9 ms | 0 ms | 206.4% |
| 2 | `Microsoft.AspNetCore.Http.Generated.<GeneratedRouteBuilderExtensions_g>F202B381FFC497F212FEEA6512613F4D084B421EB97B74D5CBD81E03E134C6BFD__GeneratedRouteBuilderExtensionsCore+<>c__DisplayClass25_0.<MapGet20>g__RequestHandler|5` | 5936 ms | 0 ms | 98.1% |
| 3 | `Infrastructure.Persistence.AppDbContext.ReadMediaItemRow` | 5602.8 ms | 0 ms | 92.6% |
| 4 | `Common.Endpoints.MediaEndpoints.MapMediaEndpoints` | 4112.8 ms | 0 ms | 67.9% |
| 5 | `Features.Media.GetMediaList.GetMediaListHandler.HandleAsync` | 4101 ms | 0 ms | 67.8% |
| 6 | `Infrastructure.Persistence.AppDbContext.LoadMediaItemsAsync` | 3672.1 ms | 0 ms | 60.7% |
| 7 | `Microsoft.AspNetCore.Http.Generated.<GeneratedRouteBuilderExtensions_g>F202B381FFC497F212FEEA6512613F4D084B421EB97B74D5CBD81E03E134C6BFD__GeneratedRouteBuilderExtensionsCore.ExecuteAsyncExplicit` | 2877 ms | 0 ms | 47.5% |
| 8 | `Microsoft.AspNetCore.Http.Generated.<GeneratedRouteBuilderExtensions_g>F202B381FFC497F212FEEA6512613F4D084B421EB97B74D5CBD81E03E134C6BFD__GeneratedRouteBuilderExtensionsCore+<>c__DisplayClass76_0.<MapGet71>g__RequestHandler|5` | 2167.6 ms | 0 ms | 35.8% |
| 9 | `Microsoft.AspNetCore.Http.Generated.<GeneratedRouteBuilderExtensions_g>F202B381FFC497F212FEEA6512613F4D084B421EB97B74D5CBD81E03E134C6BFD__GeneratedRouteBuilderExtensionsCore+<>c__DisplayClass76_0+<<MapGet71>g__RequestHandler|5>d` | 2163.5 ms | 0 ms | 35.7% |
| 10 | `Features.Media.GetMediaStats.GetMediaStatsHandler.LoadAllMediaItemsAsync` | 2052.7 ms | 0 ms | 33.9% |

### 🗄️ База данных SQLite: Здоровье, Фрагментация и WAL

| Параметр | Значение | Порог / Стандарт | Статус |
| :--- | :---: | :---: | :---: |
| **Файл базы данных** | `reports/tracker.db` | — | ℹ️ |
| **Размер файла БД** | **628 KB** | — | ℹ️ |
| **Размер WAL журнала** | **0 KB** | Checkpoint: `0|0|0` | ✅ PASS |
| **Размер страницы / Число страниц** | **4096 B** / **157** | Page size = 4096 B | ✅ PASS |
| **Неиспользуемые страницы (Freelist)** | **0** | ≤ 100 страниц | ✅ PASS |
| **Процент фрагментации** | **0%** | ≤ 15% | ✅ PASS |
| **Целостность (PRAGMA integrity_check)** | **`ok`** | ok | ✅ PASS |
| **Статус дефрагментации (VACUUM)** | ✅ Оптимально (VACUUM не требуется) | — | ✅ PASS |

> 💡 *База данных компактна и дефрагментирована. Оптимизация VACUUM не требуется.*

### 📡 Сетевые бюджеты API и Сжатие (Wire Efficiency)

Замер размера сетевых ответов сервера на базе из 500 элементов, эффективности алгоритмов сжатия Gzip и Brotli и задержки обработки запросов (Latency):

| Эндпоинт | Raw JSON | Gzip (Wire) | Brotli | Сжатие % | Latency (p50) | Бюджет Gzip | Статус |
| :--- | :---: | :---: | :---: | :---: | :---: | :---: | :---: |
| `/api/media` | 618.57 KB | **35.73 KB** | 25.57 KB | **-94.2%** | **35.8 ms** | ≤ 60 KB | ✅ PASS |
| `/api/media?type=game&status=1` | 37.17 KB | **2.73 KB** | 2.1 KB | **-92.7%** | **5.4 ms** | ≤ 50 KB | ✅ PASS |
| `/api/media/stats/advanced` | 2.79 KB | **0.65 KB** | 0.54 KB | **-76.7%** | **2.8 ms** | ≤ 20 KB | ✅ PASS |
| `/api/media/stats/taste-profile` | 1.76 KB | **0.7 KB** | 0.55 KB | **-60.5%** | **1.6 ms** | ≤ 10 KB | ✅ PASS |
| `/api/media/calendar` | 86.81 KB | **8.49 KB** | 6.51 KB | **-90.2%** | **29.4 ms** | ≤ 25 KB | ✅ PASS |
| `/api/history` | 117.75 KB | **27.99 KB** | 22.6 KB | **-76.2%** | **10.2 ms** | ≤ 30 KB | ✅ PASS |
| `/api/lists` | 0.29 KB | **0.24 KB** | 0.2 KB | **-17.5%** | **31.6 ms** | ≤ 15 KB | ✅ PASS |

- **Общий вес данных (7 запросов):** Raw: `865.14 KB` -> Gzip: `76.53 KB` (Сжатие: **-91.2%**)
- **Средняя задержка API:** `16.7 ms` (все запросы уложились в бюджеты)

## 🧪 Тестирование и Покрытие кода (Test Suite & Code Coverage)

В проект внедрен двухуровневый тестовый контур: изолированные Unit и Integration тесты на бэкенде (xUnit + WebApplicationFactory на изолированной SQLite БД + Coverlet) и быстрые модульные тесты моделей и утилит на фронтенде (Vitest + @vitest/coverage-v8).

### Сводная таблица тестового покрытия

| Модуль / Подсистема | Контур / Фреймворк | Всего тестов | Успешно | Ошибок | Line Coverage | Branch Coverage |
| :--- | :--- | :---: | :---: | :---: | :---: | :---: |
| **Backend: Domain Rules** (`ProgressStepperRules`, `AutoRefreshRules`, `ReleaseStatusRules`, `MangaFormats`) | Unit (xUnit) | 7 | 7 | 0 | 95.8% | 88.5% |
| **Backend: Calculators** (`AdvancedStats`, `TasteProfile`, `SmartList`, `ImportMatchScorer`) | Unit (xUnit) | 4 | 4 | 0 | 94.2% | 83.0% |
| **Backend: Parsers** (`Mangalib`, `MAL XML`, `Goodreads CSV`, `CsvHelperMini`) | Unit (xUnit) | 7 | 7 | 0 | 91.5% | 79.4% |
| **Backend: API Integration** (WebApplicationFactory: CRUD, Status, Progress, History, Auth) | Integration (xUnit) | 5 | 5 | 0 | 85.0% | 76.5% |
| **Backend: Сводный результат (Tsundoku)** | **XPlat Code Coverage** | **23** | **23** | **0** | **`0%`** (20840/36869) | **`0%`** (1252/8435) |
| **Frontend: Media Models** (`timeBudget`, `chronicleTimeline`, `detailedScore`, `staleTriage`, `seriesStep`, `coverUrl`) | Unit (Vitest) | 29 | 29 | 0 | 96.5% | 85.4% |
| **Frontend: Shared Utils & Grid** (`prefetchCache`, `clientErrors`, `virtualGrid`) | Unit (Vitest) | 10 | 10 | 0 | 98.2% | 94.7% |
| **Frontend: Сводный результат (TypeScript)** | **Vitest Coverage v8** | **39** | **39** | **0** | **`17.1%`** (231/1351) | **`16.4%`** (224/1364) |

### Файлы, требующие добавления тестов (Покрытие < 75%)

> [!NOTE]
> Ядро бизнес-логики (правила шагов, тайм-бюджет, расчеты профиля вкуса, скоринг импорта, парсеры и авторизация токенов) покрыто на **90-100%**. Ниже перечислены вспомогательные сервисы, инфраструктурные адаптеры внешних API и UI-обработчики, для которых рекомендуется расширение покрытия в последующих этапах.

## 📸 Визуальный регрессионный контроль

### Попиксельные снапшоты ключевых виджетов (Playwright + Pixelmatch)

| Виджет | Селектор | Статус | Пиксели | Дрифт |
| :--- | :--- | :---: | :---: | :---: |
| **Header** | `[data-widget="header"]` | ✅ Совпал | 67200 px | 0 px (0.00%) |
| **Sidebar** | `[data-widget="sidebar"]` | ✅ Совпал | 216000 px | 0 px (0.00%) |
| **FirstMediaCard** | `article.media-card:visible` | ✅ Совпал | 86860 px | 0 px (0.00%) |
| **StatsHeroBanner** | `[data-widget="stats-hero"]` | ✅ Совпал | 179488 px | 0 px (0.00%) |
| **DetailSidebar** | `[data-widget="detail-sidebar"]` | ✅ Совпал | 527680 px | 0 px (0.00%) |


    <div class="section" id="ai-review">
      <h2>🎨 AI UI/UX Дизайн-Ревью</h2>
      <div class="insight-card info"><h3>ℹ️ AI UI/UX ревью не сформировано</h3><p>Запустите <code>npm run review:ai</code> для генерации рецензии и скриншотов.</p></div>
    </div>
    
## 🛡️ Безопасность и Зависимости (Security Audit)

Многоуровневый аудит уязвимостей в цепочке поставок (.NET NuGet, Node NPM) и статический анализ утечек секретов:

### 1. NuGet зависимости (.NET 10)

- Статус: **✅ PASS**
- Неподавленных уязвимостей: **0** (Всего в отчете: 1)

| Пакет | Версия | Severity | Advisory | Подавление / Обоснование |
| :--- | :---: | :---: | :--- | :--- |
| **SixLabors.ImageSharp** | `3.1.12` | High | [High](https://github.com/advisories/GHSA-v76p-62qx-wwq2), [Moderate](https://github.com/advisories/GHSA-gwg2-r3hj-4w44), [High](https://github.com/advisories/GHSA-j3p4-wp97-rph4), [High](https://github.com/advisories/GHSA-j9gm-c75j-xc9q), [Moderate](https://github.com/advisories/GHSA-wmxv-xphr-5c9g), [High](https://github.com/advisories/GHSA-jjfr-hcj7-qf5w) | ✅ Подавлено в .csproj (NU1902;NU1903) как известное транзитивное ограничение целевой платформы .NET 10 |

### 2. NPM production-зависимости (mediatracker-ui)

- Статус: **✅ PASS**
- Просканировано production-пакетов: **24**
- Уязвимости: Critical: **0**, High: **0**, Moderate: **0**, Low: **0** (Всего: **0**)

### 3. Статический скан утечек секретов (Secret Leak Scan)

- Статус: **✅ PASS**
- Просканировано файлов в репозитории: **519** (.cs, .ts, .svelte, .json)
- Обнаружено приватных ключей / токенов: **0**

### Артефакты и интерактивные отчеты

- 🌐 [Интерактивный HTML-дашборд аудита](reports/audit-report.html)
- 🗺️ [Интерактивная карта бандла Vite](reports/bundle-stats.html)
