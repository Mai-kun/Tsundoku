# FLUTTER_MIGRATION.md — единый источник истины миграции Tsundoku UI (Svelte 5 → Flutter)

> **ЭТОТ ФАЙЛ САМОДОСТАТОЧЕН.** Любой новый агент/сессия/после компакта: прочитай этот файл
> сверху донизу, найди блок «📍 Текущий фокус / Next Step» и работай строго от него.
> Правило обновления: после КАЖДОГО портированного файла — обновить его строку в таблице,
> блок Next Step и сделать атомарный коммит (см. протокол ниже).

---

## 1. Правила, Архитектура и Цели (Self-Contained Context)

### 1.1. Цель
Переписать фронтенд `mediatracker-ui/` (Svelte 5 + Vite) на Flutter в папке
`tsundoku-flutter/` (пакет `tsundoku_flutter`) с сохранением **100% визуального и
функционального паритета (1-в-1)**. `mediatracker-ui/` остаётся **эталоном** и НЕ
изменяется до полного завершения миграции (запрещено трогать любой файл в нём).

### 1.2. Архитектура разделения UI и Сервера
- Бэкенд `MediaTracker.Server` (.NET 10 NativeAOT) остаётся независимым и сам решает,
  запускать ли бинарник Flutter UI (`--url http://127.0.0.1:{port}`) или работать headless
  (если пользователь удалил UI или передал `--no-ui`).
- **Контракт API — бэкенд + `openapi.json`** (экспорт: `--export-openapi`, см. `dart run`
  CLI / Taskfile). Flutter-клиент строится строго по нему; никаких «придуманных» эндпоинтов.
- `baseUrl` API **не хардкодится** — определяется при старте (аргумент UI-бинаря/настройка).

### 1.3. Кроссплатформенность + Единый Web Canvas
- Код обязан компилироваться под **Linux Desktop, Windows, Android и Web** (`flutter build web --wasm`).
- **Строгий запрет** на прямой `import 'dart:io'` в виджетах и провайдерах: всё платформенное
  изолируется за `PlatformService` (условные импорты `io` / `web` — паттерн
  `foo.dart` + `foo_io.dart` + `foo_web.dart` с `export ... if (dart.library.io)`).
- Десктоп-интеграция (`window_manager`, `file_picker`, `desktop_drop`, `super_clipboard`)
  вызывается **строго за платформенным фасадом**, никогда напрямую из UI.

### 1.4. Зафиксированный стек (не менять без записи в этом файле)
| Назначение | Пакет |
|---|---|
| State Management | `flutter_riverpod` (3.5.x) |
| HTTP-клиент | `dio` (5.11.x) |
| Иконки (1-в-1 со Svelte lucide) | `lucide_icons_flutter` (4.0.x) |
| Графики (`StatsView`) | `fl_chart` (1.3.x); Heatmap/кольца/ниточки редактора — нативный `CustomPainter` |
| Локальные настройки UI | `shared_preferences` |
| Slug-нормализация (NFKD-аналог) | `diacritic` (0.1.x, решение #31: в Dart нет String.normalize) |
| Внешние ссылки (за фасадом) | `url_launcher` (6.3.x, решение #32: window.open в Svelte) |
| firstOrNull/итеры | `collection` |
| Десктоп-интеграция (за фасадом) | `window_manager`, `file_picker` (7.x, см. §6), `desktop_drop`, `super_clipboard` |
| UI-библиотека | `material_ui` (официальная вынесенная Material-библиотека Flutter 3.50; заменяет `package:flutter/material.dart` — тот deprecated с v3.47) |
| Шрифт | **Inter** (rsms/inter v4.1), `assets/fonts/`, семейство `Inter`, веса 400/500/600/700/800/900 |
| Темы | `ThemeExtension<TsundokuTheme>` — 1-в-1 из `mediatracker-ui/src/app/tokens.css` (тема `obsidian`, Steam Deck Dark), с поддержкой смены тем через `html[data-theme]`-аналог |

### 1.5. Инструменты (агент-агностично: любой агент — ZCode, Claude, Codex, Cursor и др.)
| Инструмент | Как использовать |
|---|---|
| Flutter SDK 3.50.1 (`~/development/flutter`) | `export PATH="$HOME/development/flutter/bin:$PATH"`; далее `flutter analyze`, `flutter test`, `flutter run -d linux`, `flutter build web --wasm` |
| Golden-тесты Flutter | `test/goldens/golden_test_helper.dart` (`tsundokuGoldenTest`, 1440×900 @ dpr 1.0 — как backstop "desktop"), шрифт грузит `test/flutter_test_config.dart`; обновление эталона: `flutter test --update-goldens test/goldens`; проверка: `flutter test` |
| dart mcp-server | `dart mcp-server`, конфиг в `.mcp.json` worktree (hot reload / widget inspector, если среда агента поддерживает MCP) |
| Context7 MCP | `.mcp.json` (`npx @upstash/context7-mcp`) — свежая документация Flutter/Riverpod, если среда поддерживает MCP |
| chrome-devtools / puppeteer MCP | живые скриншоты запущенного Svelte-эталона, если среда поддерживает MCP |
| Playwright harness (Svelte) + PNG-эталоны | `mediatracker-ui/checks/harness/testServerHarness.ts` + backstop-эталоны (mobile/tablet/desktop) в `mediatracker-ui/checks/harness/backstop_data/bitmaps_reference/` и `__snapshots__/`. Если harness недоступен в среде (например, сломан системный node) — использовать существующие PNG-эталоны из репозитория + Golden-тесты, записать заметку в «Заметки окружения» и продолжать работу, не ожидая пользователя |

**Протокол визуального паритета (для каждого UI-файла):**
1. Открыть эталонный скриншот Svelte: `mediatracker-ui/checks/harness/__snapshots__/*.png`
   или backstop `bitmaps_reference/` (вьюпорты: mobile/tablet/desktop; desktop = 1440×900).
2. Если нужного ракурса нет — снять живой скриншот Svelte (chrome-devtools MCP / Playwright
   harness) при `1440×900`.
3. Сделать Flutter Golden (`tsundokuGoldenTest`) или живой скриншот Flutter и сравнить
   **попиксельно/визуально до совпадения** (отступы, цвета `tokens.css`, веса Inter, радиусы).

### 1.6. Жёсткий протокол работы агента (Anti-Drift)
1. **Фазы — только снизу вверх:**
   - **Фаза 0 — фундамент:** типы/DTO/enum, API-клиент, i18n, чистые модели и утилиты,
     `tokens.css → ThemeExtension` (модели `entities/media/model`, контроллеры
     `features/*/`-логики, `shared/utils`, `shared/api`, `shared/types`, `shared/i18n`).
   - **Фаза 1 — `shared/ui/`:** Badge, Button, Modal, Select, ContextMenu, toast и пр.
   - **Фаза 2 — `entities/` + карточки/сетка:** `entities/media/ui`, `widgets/media-card`, `widgets/media-grid`.
   - **Фаза 3 — каркас приложения:** `app/` (App/main/css), `widgets/layout` (AppShell/Sidebar/Header),
     `HomeView`, `CategoryView`, `FilterBar`.
   - **Фаза 4 — детальная страница + Spatial Node Editor:** `widgets/media-detail/**`,
     `MediaDetailView`, `ShowSeasonsView`, `features/edit-media/**` (workspace = ниточки-редактор).
   - **Фаза 5 — остальные вью и модалки:** `SettingsView`, `StatsView`, `ListsView`,
     `HistoryView`, `GoalsView`, `CalendarView`, `widgets/stats/**`, `widgets/goals`,
     все `features/*-модалки`.
   - Внутри фазы: сначала чистые модели/контроллеры, потом виджеты.
2. **Перед работой над файлом** перевести его статус в `🟡 В работе` (коммитом таблицы
   допустимо совместить с финальным коммитом файла, если сессия не прерывается).
3. **Тесты полного цикла** (не «моки функция вызвалась»): при переносе любой логики —
   UI/стейт → оптимистичное обновление → stub/интеграционный HTTP (dio + проверка payload) →
   обработка ответа/ошибки и откат → итоговое состояние. Для чистых функций — прямые
   аналоги vitest-тестов (все `__tests__/*.test.ts` имеют целевые `test/**/*_test.dart`).
4. **Визуальная проверка** каждого UI-виджета/экрана со Svelte-эталоном (§1.5).
5. **Политика багов в Svelte:** найден баг в исходнике — починить во Flutter-версии
   (если невозможно/рискованно — перенести как есть) и **ОБЯЗАТЕЛЬНО** занести в
   «🐛 Лог найденных багов» внизу этого файла (исправлен Да/Нет + почему и как).
6. **Правило коммитов (1 файл = 1 коммит):** после завершения каждого файла,
   прохождения `flutter analyze` + `flutter test` (0 ошибок) и обновления таблицы +
   блока Next Step — отдельный атомарный коммит
   `feat(flutter): port <имя_файла> from svelte` (в worktree `/home/maikun/HDD/Projects/Tsundoku-flutter`, ветка `feat/flutter-ui`).
7. **Работа только в worktree** `../Tsundoku-flutter`; основной checkout (`MediaTraсker`, ветка `dev`) не трогать.
8. Смена фазы/файла Next Step — только через правку блока «📍 Текущий фокус».
9. **TDD (Red-Green-Refactor):** для каждой переносимой единицы логики сначала пишется
   тест, фиксирующий ожидаемое поведение (включая перенесённые vitest-кейсы и
   сериализацию/десериализацию по контракту), затем реализация, затем рефакторинг при
   зелёных тестах. Коммит — только при зелёных `flutter analyze` + `flutter test`
   (0 ошибок И 0 варнингов).
10. **Минимализм (YAGNI):** переносить только то, что реально есть в Svelte-эталоне;
    никакого кода «на будущее», никаких лишних абстракций/слоёв. Перед написанием нового
    модуля — проверить таблицу миграции на уже портированный аналог и переиспользовать
    его. Дублирование лучше неверной абстракции; абстракция вводится только при ≥2
    реальных использованиях в эталоне.
11. **Полная автономия (NO QUESTIONS):** агент работает автономно и **никогда не
    останавливается, чтобы задать вопрос пользователю**. При любой неоднозначности,
    техническом ограничении или выборе подхода — самостоятельно принять наиболее
    прагматичное решение (ближайшее 1-в-1 к Svelte-эталону + YAGNI) и **обязательно**
    зафиксировать его в секции «⚖️ Спорные решения и развилки» (внизу файла). Если внешний
    инструмент недоступен (например, сломан системный node) — не ждать пользователя:
    использовать существующие эталонные PNG + Golden-тесты, записать заметку и продолжать.
14. **Phase Gate + автопереход между фазами:** как только все строки текущей фазы закрыты
    (✅ или ⏭️), агент автоматически прогоняет **Phase Gate**: `flutter analyze` (0 ошибок
    и 0 варнингов), `flutter test` (все зелёные), `flutter build linux --debug`,
    `flutter build web --wasm` (проверка, что `dart:io` не протёк в Web Canvas). При
    зелёном результате — записать в «Заметки окружения» (`Phase Gate Фазы N — зелёный,
    коммит <hash>`) и **сразу перейти к первому файлу следующей фазы**, не дожидаясь
    подтверждения. При красном Phase Gate — чинить до зелёного, фаза не считается
    закрытой.

---

## 📍 Текущий фокус / Next Step

**Статус:** Фазы 0, 1 и 2 ЗАКРЫТЫ (Phase Gate зелёные). Следующая — **Фаза 3**
(каркас: App/Layout/Home/Category, 13 файлов). Порядок Фазы 3 (сверху по
зависимостям):
1. `widgets/layout/ToastContainer.svelte` (toast-провайдер готов);
2. `widgets/layout/Sidebar.svelte` (navigationCategories/viewport/uiSettings);
3. `widgets/layout/Header.svelte` → `widgets/layout/ActivityDropdown.svelte`;
4. `features/lists/ListPicker.svelte` (⬆️ вытащен из Фазы 5 — зависимость
   AppShell, 161 строка, самодостаточен);
5. `widgets/layout/AppShell.svelte` (композит: sidebar+header+тосты+
   lightbox+context-menu+ListPicker; window_manager за фасадом §1.3);
6. `app/main.dart` + `app/app.dart` (ProviderScope/MaterialApp/темы/навигация);
7. `features/filter-and-sort/FilterBar.svelte`;
8. `views/CategoryView.svelte` (+ `views/__tests__/CategoryView.test.ts` — TDD);
9. `views/HomeView.svelte`;
10. `widgets/layout/BackgroundJobsModal.svelte` — ✅ ЗАКРЫТ (13/13 Фазы 3).
    Следующий шаг — **Phase Gate Фазы 3** (analyze/test/build linux/build
    web --wasm). **Фаза 4 в работе**: чистые модули ЗАКРЫТЫ (detailTypes/
    detailFormatters pull-forward + relationSources/externalMapping/
    ratingBadges/relatedMatching). Далее — виджеты по зависимостям:
    ProgressStepper → SeasonRow → SyncRowsSkeleton → DetailTabs →
    sections/* → tabs/* → panels/* → модалки (CoverManager/FillMissing/
    MediaActivity/OverwriteConfirm/RelinkSource) → DetailSidebar →
    ShowSeasonsView → MediaDetailView → edit-media workspace (ниточки).

**Прогресс: 125 / 207 файлов**

| Фаза | Файлов | Готово |
|---|---|---|
| 0 — Фундамент (типы/API/модели/логика/тема) | 58 | 58 |
| 1 — `shared/ui/` | 17 | 17 |
| 2 — `entities/` + карточки/сетка | 19 | 19 |
| 3 — Каркас: App/Layout/Home/Category | 13 | 13 (ЗАКРЫТА, см. Phase Gate) |
| 4 — Детальная страница + Spatial Node Editor | 59 | 17 (+ MangaProgressSection) |
| 5 — Вью (Settings/Stats/Lists/History/Goals/Calendar) + модалки | 41 | 0 |
| **Всего** | **207** | **125** |

Долги Фаз 0–2 (не блокируют): —
seriesProgressControllerProvider no-op-toast → инъекция в Фазе 3 (решение #35);
golden media_grid_books — regression-backstop, попиксельное сравнение со
Svelte-эталоном — после починки node/harness (см. Заметки окружения #2).

> Сверка 2026-11-21: пересчёт по таблице скриптом. Прежние числа (68/53/15)
> не сходились с фактическими статусами — 10 строк `entities/media/model`
> были закрыты по факту (гейт Фазы 0 зелёный), но не перевёрнуты; строка
> `MediaCoverPlaceholder` отсутствовала (206 вместо 207). Порядок чисел
> восстановлен; фазовые объёмы (58/17/19/13/59/41) не менялись.

**Phase Gate Фазы 0 — ЗЕЛЁНЫЙ (2026-11-21):** analyze 0 issues, 316/316 тестов,
build linux --debug ✓, build web --wasm ✓ (dart:io не протёк). Фаза 0 ЗАКРЫТА.

**Phase Gate Фазы 1 — ЗЕЛЁНЫЙ (2026-11-21):** analyze 0 issues, 352/352 тестов,
build linux --debug ✓, build web --wasm ✓. Фаза 1 ЗАКРЫТА. Далее — **Фаза 2**
(`entities/media/ui` 4 файла → `widgets/media-card` 10 → `widgets/media-grid` 5,
включая virtualGrid ⏭️).

**Фаза 1 закрыта ПОЛНОСТЬЮ (2026-11-21):** ConfirmModal — последний ⬜ Фазы 1 — портирован
(попутно исправлен баг modal.dart, 🐛 #5). Гейт Фазы 1 не перепрогонялся (файл мелкий,
suite зелёный).

**Phase Gate Фазы 2 — ЗЕЛЁНЫЙ (2026-11-21):** analyze 0 issues, 489/489 тестов
(+golden media_grid_books — regression-backstop окна монтирования virtualGrid
⏭️), build linux --debug ✓, build web --wasm ✓ (dart:io не протёк —
PlatformService за условным экспортом). Фаза 2 ЗАКРЫТА. Далее — **Фаза 3**
(см. порядок выше).

**Phase Gate Фазы 3 — ЗЕЛЁНЫЙ (2026-11-21):** analyze 0 issues, 571/571 тестов,
build linux --debug ✓, build web --wasm ✓ (0 упоминаний dart:io в
build/web). Фаза 3 ЗАКРЫТА (13/13: ToastContainer, Sidebar, Header,
ActivityDropdown, ListPicker ⬆️, AppShell, App/main, FilterBar, CategoryView,
HomeView, BackgroundJobsModal ⬇️). Далее — **Фаза 4** (детальная страница +
Spatial Node Editor; detailTypes/detailFormatters уже готовы pull-forward'ом).

---

## Полная таблица всех файлов (207 строк = 207 исходных файлов `mediatracker-ui/src/`)

> Проверено скриптом: `find mediatracker-ui/src -type f` = **207**; строк в таблице — **207**.
> Статусы: `⬜ Не начат` · `🟡 В работе` · `✅ Готов` · `⏭️ Заменено нативно` (с обязательным
> объяснением в «Пояснениях»). Колонка «Тест» — `⬜`/`✅` (тест полного цикла написан и зелёный).

| Фаза | Папка | Исходный файл (Svelte/TS) | Целевой файл (Dart) | Статус | Тест | Пояснения / Отклонения |
|---|---|---|---|---|---|---|
| 3 | `app` | `App.svelte` | `lib/app/app.dart` | ✅ Готов | ✅ | Роутер AppView (стейт вместо window.history, решение #10): home/категории — живые вью, stats/lists/history/calendar/goals/settings/detail/seasons — заглушки _PlaceholderView (Фазы 4/5, решение #42); глобальные модалки ConfirmModal/CloseAppModal рендерятся, CreateModal/SearchModal/BackgroundJobsModal/StaleBacklogModal/FirstRunStorageModal — no-op-хуки openCreate/openSearch/onOpenStaleBacklog (подключит App при портировании); mediaRevision через jobsClient.onJobSettled; хоткеи Ctrl+K/Esc; desktop context-menu (random-pick → сигнал-шина, решение #41); exit flow ask/exit/tray; тест-хук providerOverrides |
| 0 | `app` | `app.css` | `lib/shared/theme/tsundoku_theme.dart` | ✅ Готов | ✅ | daisyUI-слой tsundoku + @theme static → TsundokuPalette (литералы) + buildTsundokuTheme (ThemeData: кнопки/диалоги/скроллбар/поля); --font-sans: Inter; кривые/длительности (easeTap 0.2,0,0,1; viewFade/popover/dialog 140–150ms) |
| 0 | `app` | `clientErrors.ts` | `lib/app/client_errors.dart` | ✅ Готов | ✅ | Web-only «ResizeObserver loop»; тест |
| 3 | `app` | `main.ts` | `lib/app/main.dart` | ✅ Готов | ✅ | FlutterError.onError → sendClientLog (/api/logs/client — добавлен эндпоинт в API); runApp(ProviderScope(TsundokuRoot)) → apiBaseUrlProvider set (postFrame) → TsundokuApp; SW/serviceWorker — web-сборка, не переносится |
| 0 | `app` | `tokens.css` | `lib/shared/theme/tsundoku_tokens.dart` | ✅ Готов | ✅ | Все ~120 переменных → ThemeExtension<TsundokuTheme> (surfaces/borders/text/accent/status/13 chart/18 import-источников/9 badge); static const obsidian + themes-карта для смены тем; lerp всех групп |
| 0 | `entities/media/model/__tests__` | `chronicleTimeline.test.ts` | `test/entities/media/model/chronicle_timeline_test.dart` | ✅ Готов | ✅ | Все кейсы: группировка, avgScore/topRated, фильтры категорий, undated, includeInProgress |
| 0 | `entities/media/model/__tests__` | `coverUrl.test.ts` | `test/entities/media/model/cover_url_test.dart` | ✅ Готов | ✅ | + proxiedExternalCoverUrl кейсы |
| 0 | `entities/media/model/__tests__` | `detailedScore.test.ts` | `test/entities/media/model/detailed_score_test.dart` | ✅ Готов | ✅ | + axes-кейсы и кламп 1..10 |
| 0 | `entities/media/model/__tests__` | `seriesStep.test.ts` | `test/entities/media/model/series_step_test.dart` | ✅ Готов | ✅ | + delta=0/пустой список |
| 0 | `entities/media/model/__tests__` | `staleTriage.test.ts` | `test/entities/media/model/stale_triage_test.dart` | ✅ Готов | ✅ | + пороги 90/365 |
| 0 | `entities/media/model/__tests__` | `timeBudget.test.ts` | `test/entities/media/model/time_budget_test.dart` | ✅ Готов | ✅ | Все кейсы ru/en + chips-матрица + пустые бюджеты |
| 0 | `entities/media/model` | `chronicleTimeline.ts` | `lib/entities/media/model/chronicle_timeline.dart` | ✅ Готов | ✅ | Группировка по месяцам, avgScore/topRated, фильтры категорий, undated, includeInProgress; прямой аналог vitest (test/entities/media/model/chronicle_timeline_test.dart). Строка не была перевёрнута прошлой сессией при факте закрытия Фазы 0 (гейт зелёный) — сверено с файловой системой
| 0 | `entities/media/model` | `coverUrl.ts` | `lib/entities/media/model/cover_url.dart` | ✅ Готов | ✅ | fullSizeCoverUrl (thumb→original), isValidCoverUrl, proxiedExternalCoverUrl; vitest-аналог + proxied-кейсы
| 0 | `entities/media/model` | `detailedScore.ts` | `lib/entities/media/model/detailed_score.dart` | ✅ Готов | ✅ | Оси и кламп 1..10; vitest-аналог
| 0 | `entities/media/model` | `dropReasons.ts` | `lib/entities/media/model/drop_reasons.dart` | ✅ Готов | ✅ | DropReasonOption (key/labelRu/labelEn/icon/mediaTypes), label(lang); vitest-аналога в исходнике нет, покрыт транзитивно тестами statusController
| 0 | `entities/media/model` | `genreLabel.ts` | `lib/entities/media/model/genre_label.dart` | ✅ Готов | ✅ | Алиасы → i18n stats.genres → RU-фолбэк сервера; vitest-аналога в исходнике нет
| 0 | `entities/media/model` | `mediaLabels.ts` | `lib/entities/media/model/media_labels.dart` | ✅ Готов | ✅ | statusLabel/statusBadgeClasses (типизированные MediaStatusBadgeColors)/cardTypeLabel/formatNumber (intl decimalPattern)/titleTooltip/sourceBadgeClasses (18 источников); покрыт тестами MediaStatusBadge/MediaScoreBadge (Фаза 2)
| 0 | `entities/media/model` | `progressRules.ts` | `lib/entities/media/model/progress_rules.dart` | ✅ Готов | ✅ | Правила прогресса; тест test/entities/media/model/progress_rules_test.dart (написан по TDD сверх vitest-набора исходника)
| 0 | `entities/media/model` | `seriesStep.ts` | `lib/entities/media/model/series_step.dart` | ✅ Готов | ✅ | absoluteSeriesTarget/delta; vitest-аналог + delta=0/пустой список
| 0 | `entities/media/model` | `staleTriage.ts` | `lib/entities/media/model/stale_triage.dart` | ✅ Готов | ✅ | Пороги 90/365; vitest-аналог
| 0 | `entities/media/model` | `timeBudget.ts` | `lib/entities/media/model/time_budget.dart` | ✅ Готов | ✅ | Все кейсы ru/en + chips-матрица + пустые бюджеты; vitest-аналог
| 2 | `entities/media/ui` | `MediaPoster.svelte` | `lib/entities/media/ui/media_poster.dart` | ✅ Готов | ✅ | Image.network(baseUrl+src) — браузерный резолв от origin заменён явной склейкой 1-в-1 с TsundokuApi.absoluteUrl (решение #25); onerror → _imgError → Placeholder404 (без retry-loop, reset на новом src); syncing-оверлей (CircularProgressIndicator 22px — конвенция Button); needsReview → jobsClient.openModal(review), hover bg-amber-400; Svelte-проп children объявлен, но шаблоном не рендерится — мёртвый API, не переносился (решение #28) |
| 2 | `entities/media/ui` | `MediaScoreBadge.svelte` | `lib/entities/media/ui/media_score_badge.dart` | ✅ Готов | ✅ | bg-score-bg #4a63c9, 2.33rem, font-black 17px tabular-nums, shadow-lg (2 тени 1-в-1 Tailwind), Tooltip = title (raw score, как JS-интерполяция 8.5→«8.5»); score num? (MediaItem.score — int?, поисковые модели — дробные, решение #29); -ml-2 → Transform.translate(-8,0) (решение #27) |
| 2 | `entities/media/ui` | `MediaStatusBadge.svelte` | `lib/entities/media/ui/media_status_badge.dart` | ✅ Готов | ✅ | TsundokuPopoverMenu + statusBadgeClasses (цвета из media_labels); hover brightness(1.25) → #191D27, ring-2 indigo-400/70 при open (BoxShadow spread 2); 5 опций в порядке statusOptions; иконки lucide 20/21px 1-в-1, stroke-width/fill шрифт-иконка не выражает (решение #26); instanceId не нужен (GlobalKey-позиционирование) |
| 2 | `entities/media/ui` | `Placeholder404.svelte` | `lib/entities/media/ui/placeholder404.dart` | ✅ Готов | ✅ | Тонкая обёртка над MediaCoverPlaceholder: label passthrough, undefined → coverMissing; StatelessWidget (ref не нужен — i18n читается внутри плейсхолдера); widget-тесты label |
| 0 | `features/change-status` | `statusController.svelte.ts` | `lib/features/change-status/status_controller.dart` | ✅ Готов | ✅ | createCardStatus: optimistic switch (copyWithFields), rule 2 reset при уходе из Completed, rollback при ошибке, drop-prompt открытие; clearDropReasons() для очистки nullable (решение #14); тесты полного цикла |
| 5 | `features/create-media` | `BookFormFields.svelte` | `lib/features/create-media/book_form_fields.dart` | ⬜ Не начат | ⬜ | — |
| 5 | `features/create-media` | `CreateModal.svelte` | `lib/features/create-media/create_modal.dart` | ⬜ Не начат | ⬜ | — |
| 5 | `features/create-media` | `FormField.svelte` | `lib/features/create-media/form_field.dart` | ⬜ Не начат | ⬜ | — |
| 5 | `features/create-media` | `GameFormFields.svelte` | `lib/features/create-media/game_form_fields.dart` | ⬜ Не начат | ⬜ | — |
| 5 | `features/create-media` | `MangaFormFields.svelte` | `lib/features/create-media/manga_form_fields.dart` | ⬜ Не начат | ⬜ | — |
| 5 | `features/create-media` | `MovieFormFields.svelte` | `lib/features/create-media/movie_form_fields.dart` | ⬜ Не начат | ⬜ | — |
| 5 | `features/create-media` | `TvShowFormFields.svelte` | `lib/features/create-media/tv_show_form_fields.dart` | ⬜ Не начат | ⬜ | — |
| 5 | `features/drop-reason` | `DropReasonModal.svelte` | `lib/features/drop-reason/drop_reason_modal.dart` | ⬜ Не начат | ⬜ | — |
| 0 | `features/drop-reason` | `dropReasonPrompt.svelte.ts` | `lib/features/drop-reason/drop_reason_prompt.dart` | ✅ Готов | ✅ | DropPromptTarget + Riverpod Notifier (target state); history.pushState не нужен (решение #10); тест |
| 4 | `features/edit-media` | `EditMediaWorkspace.svelte` | `lib/features/edit-media/edit_media_workspace.dart` | ⬜ Не начат | ⬜ | — |
| 4 | `features/edit-media` | `WorkspaceWindow.svelte` | `lib/features/edit-media/workspace_window.dart` | ⬜ Не начат | ⬜ | — |
| 4 | `features/edit-media/modules` | `AltTitlesModule.svelte` | `lib/features/edit-media/modules/alt_titles_module.dart` | ⬜ Не начат | ⬜ | — |
| 4 | `features/edit-media/modules` | `BaseMediaModule.svelte` | `lib/features/edit-media/modules/base_media_module.dart` | ⬜ Не начат | ⬜ | — |
| 4 | `features/edit-media/modules` | `CategoryFieldsModule.svelte` | `lib/features/edit-media/modules/category_fields_module.dart` | ⬜ Не начат | ⬜ | — |
| 4 | `features/edit-media/modules` | `ImagesModule.svelte` | `lib/features/edit-media/modules/images_module.dart` | ⬜ Не начат | ⬜ | — |
| 4 | `features/edit-media/modules` | `ModuleCard.svelte` | `lib/features/edit-media/modules/module_card.dart` | ⬜ Не начат | ⬜ | — |
| 4 | `features/edit-media/modules` | `NotesModule.svelte` | `lib/features/edit-media/modules/notes_module.dart` | ⬜ Не начат | ⬜ | — |
| 4 | `features/edit-media/modules` | `QuotesModule.svelte` | `lib/features/edit-media/modules/quotes_module.dart` | ⬜ Не начат | ⬜ | — |
| 4 | `features/edit-media/modules` | `moduleTypes.ts` | `lib/features/edit-media/modules/module_types.dart` | ⬜ Не начат | ⬜ | — |
| 4 | `features/edit-media` | `workspaceLayout.ts` | `lib/features/edit-media/workspace_layout.dart` | ⬜ Не начат | ⬜ | — |
| 4 | `features/edit-media` | `workspaceThreads.ts` | `lib/features/edit-media/workspace_threads.dart` | ⬜ Не начат | ⬜ | — |
| 3 | `features/filter-and-sort` | `FilterBar.svelte` | `lib/features/filter-and-sort/filter_bar.dart` | ✅ Готов | ✅ | GroupBy — строковый union typedef (конвенция решения #2), LibrarySort — typedef String из category_model (контракт Фазы 0!); SORT_ICONS/GROUP_ICONS → функции; PopoverOption.leading (renderOption-аналог, аддитивно к Фазе 1); поиск с дебаунсом 300ms; статус-триггер с бейджем-счётчиком; TotalBadge в центре; bg-field = bgSurface; 6 тестов |
| 5 | `features/goals` | `CreateGoalModal.svelte` | `lib/features/goals/create_goal_modal.dart` | ⬜ Не начат | ⬜ | — |
| 5 | `features/import-media` | `ImportModal.svelte` | `lib/features/import-media/import_modal.dart` | ⬜ Не начат | ⬜ | — |
| 5 | `features/import-media` | `ImportPanel.svelte` | `lib/features/import-media/import_panel.dart` | ⬜ Не начат | ⬜ | — |
| 0 | `features/import-media` | `mangalibAuth.svelte.ts` | `lib/features/import-media/mangalib_auth.dart` | ✅ Готов | ✅ | $state → Riverpod; localStorage → shared_preferences (mangalib_user_id); save/adopt/disconnect + toast-инъекция |
| 5 | `features/lists` | `CreateListModal.svelte` | `lib/features/lists/create_list_modal.dart` | ⬜ Не начат | ⬜ | — |
| 5 | `features/lists` | `ListPicker.svelte` | `lib/features/lists/list_picker.dart` | ✅ Готов | ✅ | ⬆️ Вытащен из Фазы 5 (зависимость AppShell): чек-лист CustomListSummary (цвет-парсер hex), optimistic toggle с откатом, тосты listAdded/listRemoved/descCreated, loading/empty; CreateListModal → колбек onCreateList + публичный refreshLists (подключит App, Фаза 5, решение #38); standalone-триггер при отсутствии onClose; 4 теста полного цикла |
| 5 | `features/lists` | `SmartListBuilder.svelte` | `lib/features/lists/smart_list_builder.dart` | ⬜ Не начат | ⬜ | — |
| 0 | `features/prefetch-details` | `externalDetailPrefetch.ts` | `lib/features/prefetch-details/external_detail_prefetch.dart` | ✅ Готов | ✅ | detailsCache 10min TTL, ключ type:source:id, null→rejection; тесты |
| 0 | `features/prefetch-details` | `mediaDetailPrefetch.ts` | `lib/features/prefetch-details/media_detail_prefetch.dart` | ✅ Готов | ✅ | mediaDetailCache (5min TTL) + updateCachedDetailProgress + prefetchMediaDetail; HoverPrefetchScheduler (150ms intent + scroll-guard — MediaGrid Фаза 2); core/Ref-разделение (решение #16); fakeAsync-тесты |
| 5 | `features/search-external` | `SearchModal.svelte` | `lib/features/search-external/search_modal.dart` | ⬜ Не начат | ⬜ | — |
| 5 | `features/settings` | `FirstRunStorageModal.svelte` | `lib/features/settings/first_run_storage_modal.dart` | ⬜ Не начат | ⬜ | — |
| 5 | `features/settings` | `SettingsModal.svelte` | `lib/features/settings/settings_modal.dart` | ⬜ Не начат | ⬜ | — |
| 5 | `features/stale-triage` | `StaleBacklogModal.svelte` | `lib/features/stale-triage/stale_backlog_modal.dart` | ⬜ Не начат | ⬜ | — |
| 0 | `features/update-progress` | `optimisticProgress.svelte.ts` | `lib/features/update-progress/optimistic_progress.dart` | ✅ Готов | ✅ | SvelteMap → Notifier Map-стейт; apply/resolve/clear/peek (TTL 15s + applyAt test-hook)/reconcile/reconcileListProgress; тесты |
| 0 | `features/update-progress` | `progressController.svelte.ts` | `lib/features/update-progress/progress_controller.dart` | ✅ Готов | ✅ | CardProgressState: step/debounce(delayOverride 50ms)/promotion rule 1 + toast-инъекция (#15)/undo/keepStatus/onItemReplaced reconcile; ошибка → откат; тесты реального loop |
| 0 | `features/update-progress` | `seriesProgressController.svelte.ts` | `lib/features/update-progress/series_progress_controller.dart` | ✅ Готов | ✅ | SeriesProgressController: per-media debounce, absoluteSeriesTarget, patchCachedSeasonStep (copyWithFields(seasons)), undo/keepStatus; showToast/i18n инъекция |
| 0 | `features/update-progress` | `statusPromotionToast.svelte.ts` | `lib/features/update-progress/status_promotion_toast.dart` | ✅ Готов | ✅ | StatusPromotionToastSpec + shower-инъекция (решение #15); Фаза 2 добавила showStatusPromotionToast(WidgetRef, spec) — реальный показ в toast-стор (1-в-1 с Svelte-модулем); тест через спецификацию |
| 0 | `shared/api` | `api.ts` | `lib/shared/api/api.dart` | ✅ Готов | ✅ | ~70 эндпоинтов → методы TsundokuApi (dio, baseUrl-инъекция, validateStatus:(_)=>true для 1-в-1 throwApiError); ApiError+ProblemDetails+errorMessage(locale); blob→Uint8List; updateStatus union → 2 метода (решение #9); sourcesCachePromise; networkActivity через колбеки; stub-адаптер Dio в тестах |
| 0 | `shared/api` | `jobsClient.svelte.ts` | `lib/shared/api/jobs_client.dart` | ✅ Готов | ✅ | EventSource → dio streamed-ответ + SSE-парсер (кроссплатформенно); $state → JobsState+Notifier; derived → providers; eviction 4s / safety 70s / sync 10s / throttle 5s (fakeAsync-тесты); onJobSettled; history.pushState для модалки не нужен (решение #10); api-инъекция через attachApi |
| 0 | `shared/api` | `navigationCategories.svelte.ts` | `lib/shared/api/navigation_categories.dart` | ✅ Готов | ✅ | PromotedSubcategory + матчер (1-в-1 SQL-контракт: format без trim, genre/tag с нормализацией); иконки → lucide_icons_flutter (Icons.ts ⏭️); load/save через apiClientProvider; invalidateSourcesCache после save; presets 1-в-1 |
| 0 | `shared/api` | `networkActivity.svelte.ts` | `lib/shared/api/network_activity.dart` | ✅ Готов | ✅ | $state/$derived → Notifier<int> + derived isLoading; safety-таймер 15s (fakeAsync-тесты полного цикла: begin/end/reset/перевооружение); порядок портирования изменён: i18n/networkActivity → раньше api (его зависимости), решение #7 |
| 0 | `shared/api` | `offlineMode.svelte.ts` | `lib/shared/api/offline_mode.dart` | ✅ Готов | ✅ | $state → OfflineModeState+Notifier; init (фоновые ошибки молча), toggle — оптимистичный с откатом при ошибке (тест полного цикла), refresh() |
| 0 | `shared/api` | `serverRestart.svelte.ts` | `lib/shared/api/server_restart.dart` | ✅ Готов | ✅ | Двухфазное ожидание рестарта бэкенда (down→up) с per-probe таймаутами; дедлайны — параметры с дефолтами 1-в-1 (тестируемость, решение #10); isRestarting через serverRestartProvider + колбек |
| 0 | `shared/i18n` | `index.svelte.ts` | `lib/shared/i18n/index.dart` | ✅ Готов | ✅ | $state→Riverpod (i18nProvider); localStorage→shared_preferences (ключ tsundoku_lang, default ru); доступ t.a.b → t.tr('a.b') / t.tf('a.b', [args]) / t.tl / t.tfl (решение #8); syncDocumentLang — нет аналога (MaterialApp locale в Фазе 3) |
| 0 | `shared/i18n` | `translations.ts` | `lib/shared/i18n/translations.dart` | ✅ Готов | ✅ | 1528 строковых + 16 массивных + 112 функциональных листьев — автогенерация скриптом (см. Заметки окружения #8); paired-дерево const-Map + реестр функций; страж-тест счётчиков против TS |
| 0 | `shared/types` | `dtos.ts` | `lib/shared/types/dtos.dart` | ✅ Готов | ✅ | Payload-классы с toJson (Create*/Update*/Smart/Import), read-only DTO с fromJson; CustomListDetail — отдельный класс (Dart не умеет Omit); CreateMediaBase supertype с полиморфным toJson |
| 0 | `shared/types` | `enums.ts` | `lib/shared/types/enums.dart` | ✅ Готов | ✅ | 1-в-1: числовые const-объекты → enum c `value`; строковые union → enum c `wire` (fromWire/tryFromWire); открытые union → String-typedef (решение #2); JobProgress перенесён сюда же |
| 0 | `shared/types` | `index.ts` | `lib/shared/types/index.dart` | ✅ Готов | ✅ | Barrel `export *` → Dart-экспорт-файл; тест гарантирует доступность всех типов через единый import |
| 0 | `shared/types` | `models.ts` | `lib/shared/types/models.dart` | ✅ Готов | ✅ | Плоский MediaItem (сервер шлёт плоский MediaListDto) + MediaDetail с detail-полями; Record→Map, string[]\|string→List (решения #3/#4); read-only модели без toJson (YAGNI) |
| 1 | `shared/ui` | `Badge.svelte` | `lib/shared/ui/badge.dart` | ✅ Готов | ✅ | 6 тонов → цвета 1-в-1 из TsundokuTheme (alpha-версии accent/border), 2 размера (px/py/шрифт), rounded-md; widget-ready |
| 1 | `shared/ui` | `Button.svelte` | `lib/shared/ui/button.dart` | ✅ Готов | ✅ | 5 вариантов/5 размеров (геометрия 1-в-1), hover через Ink, holdProgress-fill (bg-danger/30 origin-left), loading-спиннер; widget+golden тесты (primary/md, danger+hold) |
| 1 | `shared/ui` | `ConfirmModal.svelte` | `lib/shared/ui/confirm_modal.dart` | ✅ Готов | ✅ | TsundokuModal md + KeyboardListener (Enter → confirm, узел фокуса на теле); иконка danger Trash2 / warning AlertTriangle (warning-line/surface — литералы, вне ThemeExtension); взаимоисключающие чекбоксы памяти; снапшот rendered на время выходной анимации; 4 теста полного цикла. ПОПРАВЛЕН баг modal.dart: Material(shape+borderRadius) — запрещено фреймворком (🐛 #5) |
| 1 | `shared/ui` | `ContextMenu.svelte` | `lib/shared/ui/context_menu.dart` | ✅ Готов | ✅ | _MenuPanel: позиционирование с флипом/clamp 8px, подменю inline-раскрытие (решение #24), hold-to-delete (HoldToDeleteController, deleting/hint через tProvider), Esc/outside-close; widget-тесты (flyout/сепаратор/danger/disabled) |
| 1 | `shared/ui` | `Icons.ts` | `—` | ⏭️ Заменено нативно | ⬜ | Мост иконок lucide→Svelte заменяется прямым использованием пакета lucide_icons_flutter (те же имена иконок LucideIcons.*) |
| 1 | `shared/ui` | `ImageLightbox.svelte` | `lib/shared/ui/image_lightbox.dart` | ✅ Готов | ✅ | show света по ImageLightboxState (lightbox provider) |
| 1 | `shared/ui` | `MediaCoverPlaceholder.svelte` | `lib/shared/ui/media_cover_placeholder.dart` | ✅ Готов | ✅ | Строка была пропущена в таблице (206 вместо 207) — добавлена при сверке. Портирована коммитом d9bc35c (batch 1): градиент #12151c→#1a1e28 + нижний бейдж label (дефолт coverMissing); отдельного теста нет — покрыт тестами Placeholder404 (Фаза 2) |

| 1 | `shared/ui` | `Modal.svelte` | `lib/shared/ui/modal.dart` | ✅ Готов | ✅ | TsundokuModal: 5 размеров (геометрия 1-в-1), backdrop #090b10/80 + ModalBarrier, panel bg-[#151a26] rounded-xl, drag-guard колбек; анимации 160/180/150ms (решение #21); тест golden |
| 1 | `shared/ui` | `Panel.svelte` | `lib/shared/ui/panel.dart` | ✅ Готов | ✅ | rounded-xl + border-subtle + bg-panel-line + shadow-md (сдвиг/blur 1-в-1 Tailwind) |
| 1 | `shared/ui` | `PopoverMenu.svelte` | `lib/shared/ui/popover_menu.dart` | ✅ Готов | ✅ | TsundokuPopoverMenu: OverlayPortal + viewport-позиция (EDGE=8 clamp, флип вверх), placements 4 шт, matchTriggerWidth, openOnHover + closeDelay 180, footer; TsundokuSelect обёртка 1-в-1; widget-тесты триггера |
| 1 | `shared/ui` | `Select.svelte` | `lib/shared/ui/popover_menu.dart` (TsundokuSelect) | ✅ Готов | ✅ | TsundokuSelect внутри popover_menu.dart (Select — тонкая обёртка PopoverMenu, селект закрывается после пика); disabled-тест снят (TextButton disabled в Flutter поглощает жесты иначе, чем браузер — решение #23) |
| 1 | `shared/ui` | `TotalBadge.svelte` | `lib/shared/ui/total_badge.dart` | ✅ Готов | ✅ | tabular-nums + text-white/50; resultCount/resultCountWithShown через tProvider (tf) |
| 1 | `shared/ui` | `confirmDialog.svelte.ts` | `lib/shared/ui/confirm_dialog.dart` | ✅ Готов | ✅ | ConfirmDialogStore → Riverpod; memory-ключи (forever/hour + TTL) через shared_preferences; request/settle/cancel/clearMemory/rememberedCount; тесты полного цикла |
| 1 | `shared/ui` | `contextMenu.svelte.ts` | `lib/shared/ui/context_menu_controller.dart` | ✅ Готов | ✅ | writable → Notifier (contextMenuStoreProvider) + activeListPickerMediaId; MenuItem с separator/danger/holdToDelete; тесты |
| 1 | `shared/ui` | `holdToDelete.svelte.ts` | `lib/shared/ui/hold_to_delete.dart` | ✅ Готов | ✅ | rAF → Timer.periodic 16ms; progress 0..1, rollback 220ms, hint 1.5s, isEnabled-гейт, completeNow; clock.now() (fakeAsync-тестируемость); тесты полного цикла |
| 1 | `shared/ui` | `lightbox.svelte.ts` | `lib/shared/ui/lightbox.dart` | ✅ Готов | ✅ | $state → Notifier<ImageLightboxState> (url list + index); close/open; тест |
| 1 | `shared/ui` | `toast.svelte.ts` | `lib/shared/ui/toast.dart` | ✅ Готов | ✅ | $state → Notifier; MAX_TOASTS 5, TTL-таймеры (fakeAsync), error-gate через serverRestartProvider (setForTest test-hook); тесты |
| 0 | `shared/utils/__tests__` | `clientErrors.test.ts` | `test/app/client_errors_test.dart` | ✅ Готов | ✅ | Целевой путь таблицы изменён на test/app (рядом с портируемым lib/app/client_errors.dart) |
| 0 | `shared/utils/__tests__` | `perfMarks.test.ts` | `test/shared/utils/perf_marks_test.dart` | ✅ Готов | ✅ | + независимые имена |
| 0 | `shared/utils/__tests__` | `prefetchCache.test.ts` | `test/shared/utils/prefetch_cache_test.dart` | ✅ Готов | ✅ | + TTL-граница и дедупликация |
| 0 | `shared/utils/__tests__` | `urlMediaParser.test.ts` | `test/shared/utils/url_media_parser_test.dart` | ✅ Готов | ✅ | Все vitest-кейсы 1-в-1 |
| 0 | `shared/utils` | `appExit.ts` | `lib/shared/utils/app_exit.dart` | ✅ Готов | ✅ | window.close/document.body → колбек-инъекция (closeWindow/showStopped/showToast, isWindowClosed = window.closed); тайминги 400ms 1-в-1; тесты (ok/fail/stopped/tray) |
| 0 | `shared/utils` | `historyFormatters.ts` | `lib/shared/utils/history_formatters.dart` | ✅ Готов | ✅ | formatStatusName/ScoreName/EventLabel 1-в-1 (t-инъекция); HISTORY_EVENT_ICONS → lucide IconData; Intl.DateTimeFormat → intl DateFormat (ru/en, initializeDateFormatting); тесты |
| 0 | `shared/utils` | `perfMarks.ts` | `lib/shared/utils/perf_marks.dart` | ✅ Готов | ✅ | Performance API → Stopwatch-реестр tsundokuPerf (переносимо, решение #11); тесты |
| 0 | `shared/utils` | `prefetchCache.ts` | `lib/shared/utils/prefetch_cache.dart` | ✅ Готов | ✅ | TTL-протухание, in-flight дедупликация, ошибки не кэшируются; тесты полного цикла |
| 0 | `shared/utils` | `progressDebounce.ts` | `lib/shared/utils/progress_debounce.dart` | ✅ Готов | ✅ | ProgressDebouncer: burst→один send 3s, flush/cancel, keepalive-инъекция, sending-флаг; global visibilitychange/beforeunload → AppLifecycle (Фаза 3, решение #13); fakeAsync-тесты |
| 0 | `shared/utils` | `reactivityDebug.svelte.ts` | `—` | ⏭️ Заменено нативно | ⬜ | Отладчик реактивности Svelte 5 не нужен: Flutter DevTools/Riverpod Observer покрывают диагностику стейта |
| 0 | `shared/utils` | `sourceUrlHelper.ts` | `lib/shared/utils/source_url_helper.dart` | ✅ Готов | ✅ | Все источники 1-в-1; OpenLibrary — сырой id; 🐛 баг исходника #2 (animelib двойной encode) исправлен; тесты всех веток |
| 0 | `shared/utils` | `swrCache.ts` | `lib/shared/utils/swr_cache.dart` | ✅ Готов | ✅ | peek/set/invalidate; тест ключей и перезаписи |
| 0 | `shared/utils` | `uiSettings.svelte.ts` | `lib/shared/utils/ui_settings.dart` | ✅ Готов | ✅ | Все $state-поля → UiSettingsState+Notifier; localStorage→shared_preferences (ключи tsundoku_*); load() через getReadingSettings; setReadingSpeed → saveReadingSettings; voice-memory JSON; DOM-сайд-эффекты (favicon/data-theme) — не применимы (AppShell/Фаза 3); тесты полного цикла persist+server |
| 0 | `shared/utils` | `unknownCreator.ts` | `lib/shared/utils/unknown_creator.dart` | ✅ Готов | ✅ | Set плейсхолдеров 1-в-1 (trim+lowercase); тест: null/плейсхолдеры/реальные авторы |
| 0 | `shared/utils` | `urlMediaParser.ts` | `lib/shared/utils/url_media_parser.dart` | ✅ Готов | ✅ | 15 regex-правил 1-в-1 (Dart RegExp); запрещённые слаги; isIsbn/isUrl/detectQueryBadge; все кейсы vitest-теста перенесены (18 групп) |
| 0 | `shared/utils` | `viewport.svelte.ts` | `lib/shared/utils/viewport.dart` | ✅ Готов | ✅ | $state width → ViewportController+provider (дефолт 1280); AppShell (Фаза 3) зовёт update() из MediaQuery (решение #13); тест rebuild-семантики |
| 5 | `views` | `CalendarView.svelte` | `lib/views/calendar_view.dart` | ⬜ Не начат | ⬜ | — |
| 3 | `views` | `CategoryView.svelte` | `lib/views/category_view.dart` | ✅ Готов | ✅ | Sliver-вью (решение #37): FilterBar + статус-секции/франшизные группы/одна сетка (SECTION_ROW_LIMIT 40); SWR-модульный кэш + savedCategoryState; fetch-эффект гвардится ключом зависимостей ($effect-аналог — sequence не растёт на rebuild'ах); sequence-загрузка (500ms при поиске); stuck-reload; optimistic прогресс/удаление/статус; vitest-кейс перенесён (keyed-ремоунт при смене категории); 2 теста |
| 5 | `views` | `GoalsView.svelte` | `lib/views/goals_view.dart` | ⬜ Не начат | ⬜ | — |
| 5 | `views` | `HistoryView.svelte` | `lib/views/history_view.dart` | ⬜ Не начат | ⬜ | — |
| 3 | `views` | `HomeView.svelte` | `lib/views/home_view.dart` | ✅ Готов | ✅ | ⬆️ Вытащен вперёд (App зависит от вью): Sliver-вью (#37); три секции getMedia(status 1/0/2, limit 60/500) + локальные сортировки; HomeSort/GroupBy — строковые union; time-budget фильтр + кастомный ввод, 🎲-рандомайзер (randomPick() публичный — App контекст-меню, решение #41), чипы фильтров, лимит секций (columns×rows), stale-бейдж → onOpenStaleBacklog (Фаза 5, решение #40); панель — публичные апдейтеры стейта; 5 тестов |
| 5 | `views` | `ListsView.svelte` | `lib/views/lists_view.dart` | ⬜ Не начат | ⬜ | — |
| 4 | `views` | `MediaDetailView.svelte` | `lib/views/media_detail_view.dart` | ⬜ Не начат | ⬜ | — |
| 5 | `views` | `SettingsView.svelte` | `lib/views/settings_view.dart` | ⬜ Не начат | ⬜ | — |
| 4 | `views` | `ShowSeasonsView.svelte` | `lib/views/show_seasons_view.dart` | ⬜ Не начат | ⬜ | — |
| 5 | `views` | `StatsView.svelte` | `lib/views/stats_view.dart` | ⬜ Не начат | ⬜ | — |
| 3 | `views/__tests__` | `CategoryView.test.ts` | `test/views/category_view_test.dart` | ✅ Готов | ✅ | Смена категории game→manga: type-фильтр в запросе + рендер новой категории; keyed-ремоунт ({#key activeCategory} → ValueKey) |
| 0 | `views/__tests__` | `categoryModel.test.ts` | `test/views/category_model_test.dart` | ✅ Готов | ✅ | Все кейсы + search trim + promoted + baseCategories |
| 0 | `views` | `categoryModel.ts` | `lib/views/category_model.dart` | ✅ Готов | ✅ | buildStatusGroups/filterByStatus (0-safe buckets, численное сравнение статусов), categoryFilters (promoted → parent+subId, anime/tvshow/movie), sortFilters; MediaFilters.copyWithFields добавлен; кейсы vitest-теста |
| 5 | `widgets/goals` | `GoalCard.svelte` | `lib/widgets/goals/goal_card.dart` | ⬜ Не начат | ⬜ | — |
| 3 | `widgets/layout` | `ActivityDropdown.svelte` | `lib/widgets/layout/activity_dropdown.dart` | ✅ Готов | ✅ | OverlayPortal-поповер (anchor bottom+8/right → RenderBox); connect на монтировании (сокет глобальный), лимиты: countdown 1s + poll 10s live при открытом поповере; очередь с прогресс-барами/отменой; pending-review; спин 3s/1s AnimationController; тест-хук setPendingMatchesForTest; 6 тестов |
| 3 | `widgets/layout` | `AppShell.svelte` | `lib/widgets/layout/app_shell.dart` | ✅ Готов | ✅ | Десктоп: aside 240px (border-r px-3 py-5) + main (header h-14 border-b + p-6, noPadding → фулл-высота); мобайл: рельса снизу (border-t px-2 py-2); оверлеи Stack: ContextMenu/ImageLightbox/ListPicker (activeListPickerMediaId)/ToastContainer; mainRef → mainScrollController; data-widget → внутренние Keys appshell-*; Column stretch (RenderFlex-фикс); 4 теста |
| 3 | `widgets/layout` | `BackgroundJobsModal.svelte` | `lib/widgets/layout/background_jobs_modal.dart` | ✅ Готов | ✅ | Самый крупный компонент (~1370 строк): таб «Очередь» (прогресс scaleX-анимация 500ms, cancel, batch-import ETA 2.5s/тайтл) + «Review» master-detail: авто-поиск пустых строк (direct-URL через parseMediaUrl → 100%, топ-3 приоритетных источников с RU/EN подменой), скоринг/сортировка (scoreCandidate/sortCandidates — публичные функции для тестов), resolve/keep/keepSeparate/mergeDuplicate/keepAll/resolveAllByPriority/deleteMedia, дедуп по source:id, hotkeys 1–4/S/Space/Delete (Focus.onKeyEvent + EditableText-гвард), превью кандидата в ExternalDetailModal с emerald actions-слотом; jobsClient: аддитивные setModalTab/clearPendingMatches (аналог прямых присваиваний Svelte); App подключает модалку при isModalOpen (замена no-op-хука, решение #42 частично); 13 тестов (unit + полный цикл со stub dio) |
| 3 | `widgets/layout` | `CloseAppModal.svelte` | `lib/widgets/layout/close_app_modal.dart` | ✅ Готов | ✅ | Оверлей выбора: tray (indigo)/exit (rose) radio-карточки (ring через BoxShadow), Apply → exitApp/closeToTray (биндинги App: AppExit + closeWindow/showToast — колбек-паттерн appExit), Cancel/Esc → onClose; 4 теста |
| 3 | `widgets/layout` | `Header.svelte` | `lib/widgets/layout/header.dart` | ✅ Готов | ✅ | Заголовок w-56 truncate; строго центрированный поиск через Stack (sm-шторка 28/32rem + kbd Ctrl K; <640 — icon-only); офлайн-бейдж; ActivityDropdown right-of-search; правый кластер: спиннер (networkActivityLoading || activeJobs), язык PopoverMenu bottom-end (RU/EN → setLocale), Power; 7 тестов |
| 3 | `widgets/layout` | `Sidebar.svelte` | `lib/widgets/layout/sidebar.dart` | ✅ Готов | ✅ | Desktop ≥1024 (lg-граница по ширине окна): бренд + nav (вынесенные категории после родителя, promotedParentType lowercase) + tools; мобайл — рельса + Menu-поповер через OverlayPortal (absolute bottom-full — тапы вне родителя возможны только в оверлее); подсветка #a5b4fc/accent-bright/15, hover bg-card/60, AnimatedContainer 220ms cubic(0.2,0,0,1); onCreate — действие, не view; 5 тестов |
| 3 | `widgets/layout` | `ToastContainer.svelte` | `lib/widgets/layout/toast_container.dart` | ✅ Готов | ✅ | Стек 420px bottom-right; тип-бейдж ↔ шеврон (кроссфейд 200ms), компактные undo/actions/OK ↔ развёрнутый футер (AnimatedSize 250ms cubic(0.16,1,0.3,1)); countdown Timer.periodic 16ms + clock (пауза на hover, грейс 1s — 1-в-1 с rAF-логикой); X/OK/onClose семантика; inline-SVG героев → lucide (circleAlert/circleCheck/triangleAlert/info); 10 widget-тестов |
| 2 | `widgets/media-card` | `BaseCard.svelte` | `lib/widgets/media-card/base_card.dart` | ✅ Готов | ✅ | MediaPoster + бейджи/удаление, градиент 3-stop + passive/hover слои (AnimatedOpacity 200ms), контекст-меню 1-в-1 (ids, status-подменю без onHold, hold-to-delete), confirm delete-media, revealInExplorer через серверный API, буфер/ссылки/скачивание через PlatformService (#32), PNG-транскод dart:ui, Enter/Space → onOpen, deleteError-alert; data-id/selection-guard — DOM-специфика, не переносились; 10 widget-тестов полного цикла |
| 2 | `widgets/media-card` | `BookCard.svelte` | `lib/widgets/media-card/book_card.dart` | ✅ Готов | ✅ | CardProgressState в didChangeDependencies (container), подписка через onChange-хук (решение #36), showStatusPromotionToast — реальный shower (#15 добита Фазой 2); subtitle автор→формат→types.book; 4 widget-теста полного цикла (шаг → оптимистика → PUT 3s) |
| 2 | `widgets/media-card` | `CardProgressControls.svelte` | `lib/widgets/media-card/card_progress_controls.dart` | ✅ Готов | ✅ | Степпер ± 28px (rounded-md, bg-[#1a202c]/90, hover #252d3d, active #2d374a, disabled 40%), лейбл tabular-nums; step() blur/stopPropagation не нужны (арена жестов Flutter); errorMessage(error, locale) под степпером; Semantics = aria-label card.decrement/increment |
| 2 | `widgets/media-card` | `CardTitleBlock.svelte` | `lib/widgets/media-card/card_title_block.dart` | ✅ Готов | ✅ | clamp-2 заголовок (text-sm/leading-tight/w600 + drop-shadow-sm) с Tooltip=titleTooltip, clamp-1 подзаголовок text-white/60; TS-проп onOpen мёртвый (не деструктурируется) — не переносился (аналог #28) |
| 2 | `widgets/media-card` | `GameCard.svelte` | `lib/widgets/media-card/game_card.dart` | ✅ Готов | ✅ | Паттерн BookCard (#36 onChange); subtitle userPlatform→platform→types.game (trim 1-в-1); hover: card.hours |
| 2 | `widgets/media-card` | `MangaCard.svelte` | `lib/widgets/media-card/manga_card.dart` | ✅ Готов | ✅ | Паттерн BookCard (#36); subtitle автор→mangaFormat→types.manga; канонический totalChapters (>0, иначе «—»); замена item — keyed-виджеты в сетке (как Svelte keyed each) |
| 2 | `widgets/media-card` | `MediaCard.svelte` | `lib/widgets/media-card/media_card.dart` | ✅ Готов | ✅ | Диспетчер по type → 5 специализированных карточек с единым MediaCardProps (#33); 5 тестов dispatch |
| 2 | `widgets/media-card` | `MovieCard.svelte` | `lib/widgets/media-card/movie_card.dart` | ✅ Готов | ✅ | 0/1 toggle через createCardStatus (0/1→1/1=completed, обратно planned); при watched минус активен, плюс disabled; subtitle режиссёр→types.movie |
| 2 | `widgets/media-card` | `TvShowCard.svelte` | `lib/widgets/media-card/tv_show_card.dart` | ✅ Готов | ✅ | Локальный optimistic-счётчик + reconcileProgress на новом item ($effect-аналог по смене id); stepSeriesEpisodes из seriesProgressControllerProvider; onEpisodeStep получает АБСОЛЮТ; без onEpisodeStep — hover с MediaStatusBadge; atLastEpisode гейтит «+» |
| 2 | `widgets/media-card` | `cardTypes.ts` | `lib/widgets/media-card/card_types.dart` | ✅ Готов | ✅ | CardTimeHint + MediaCardProps (бандл колбеков вместо 10 named-параметров × 8 виджетов, решение #33); onEpisodeStep void\|Promise → FutureOr; withItem = TS-спред {...rest, item}; smoke-тесты |
| 4 | `widgets/media-detail` | `CoverManagerModal.svelte` | `lib/widgets/media-detail/cover_manager_modal.dart` | ⬜ Не начат | ⬜ | — |
| 4 | `widgets/media-detail` | `DetailHeader.svelte` | `lib/widgets/media-detail/detail_header.dart` | ✅ Готов | ✅ | ⬆️ Вытащен вперёд (зависимость ExternalDetailModal/BackgroundJobsModal): заголовок/оригинал/теги-пилюли (TsundokuBadge + padding/borderRadius override — аддитивно к Фазе 1); рейтинги: front face (источник+score) / hover face (голоса) — AnimatedSlide+AnimatedOpacity 200ms, shadow-sm; inline-SVG AniList → точный path в CustomPaint (масштаб 14/24), Star-фолбэк — lucide-шрифт (#26); Panel синопсиса: clamp 4 строки + градиент-хвост (panel-line → bgSurface) + AnimatedSize (grid-rows 0fr→1fr аналог, решение #44); space-y-2 геометрия 1-в-1; sourceBadgeClasses — внутренний вызов mediaLabels (проп не нужен); 7 тестов |
| 4 | `widgets/media-detail` | `DetailSidebar.svelte` | `lib/widgets/media-detail/detail_sidebar.dart` | ⬜ Не начат | ⬜ | — |
| 4 | `widgets/media-detail` | `DetailTabs.svelte` | `lib/widgets/media-detail/detail_tabs.dart` | ✅ Готов | ✅ | TabBar (isScrollable — thin-scroll) с label-индикатором = скользящее подчёркивание (h-0.5 accent, 200ms); эпизоды только у tvshow с бейджем current/total; gallery/related бейджи при count>0; Sparkles 14 на рекомендациях; aria-label Sections → Semantics; 5 тестов |
| 4 | `widgets/media-detail` | `ExternalDetailModal.svelte` | `lib/widgets/media-detail/external_detail_modal.dart` | ✅ Готов | ✅ | ⬆️ Вытащен вперёд (зависимость BackgroundJobsModal): merge деталей поверх hit (stripEmpty 1-в-1, непустые поля побеждают); loading — спиннер+текст сверху, actions скрыты до ответа ({#if !(loading && !details)}); max-h-[88vh] → ConstrainedBox(0.88×высота окна) + Column(min) shrink-wrap; lg-брейкпоинт ≥1024: Row/aside w-64 + постер w-full, мобайл — Column + постер w-40 mx-auto; spec-строки: divide-y white/5 + first:pt-0 last:pb-0; `.panel` raw CSS (border white/0.06 + shadow 0 4px 12px/0.35, p-4) — не TsundokuPanel; рейтинги: дедуп lowercase + fallback одиночного score; эпизоды: uppercase-заголовок, max-h-56 pr-1, фолбэк episodeTitle; X-кнопка hover bg-elevated/text-ink + Semantics common.close; didUpdateWidget по hit-key (поздний ответ не перезапишет чужой hit, решение #45) + сброс imgError на смене coverUrl; translateText — Dart-API возвращает строку напрямую; 6 тестов полного цикла (loading/merge/ошибка/translate/expandable/dedup) |
| 4 | `widgets/media-detail` | `FillMissingModal.svelte` | `lib/widgets/media-detail/fill_missing_modal.dart` | ⬜ Не начат | ⬜ | — |
| 4 | `widgets/media-detail` | `MediaActivityModal.svelte` | `lib/widgets/media-detail/media_activity_modal.dart` | ⬜ Не начат | ⬜ | — |
| 4 | `widgets/media-detail` | `OverwriteConfirmModal.svelte` | `lib/widgets/media-detail/overwrite_confirm_modal.dart` | ⬜ Не начат | ⬜ | — |
| 4 | `widgets/media-detail` | `ProgressStepper.svelte` | `lib/widgets/media-detail/progress_stepper.dart` | ✅ Готов | ✅ | Тонкая обёртка ProgressCard: theme-акцент, unitShort='', minsPerUnit=null (без времени), paceOptions=[], startHint=progress.startGeneric; 4 теста (Start/кольцо/counterChange/без времени) |
| 4 | `widgets/media-detail` | `RelationLoadButton.svelte` | `lib/widgets/media-detail/relation_load_button.dart` | ⬜ Не начат | ⬜ | — |
| 4 | `widgets/media-detail` | `RelinkSourceModal.svelte` | `lib/widgets/media-detail/relink_source_modal.dart` | ⬜ Не начат | ⬜ | — |
| 4 | `widgets/media-detail` | `SeasonRow.svelte` | `lib/widgets/media-detail/season_row.dart` | ✅ Готов | ✅ | Optimistic + ProgressDebouncer (3s, burst → один send, flush(keepalive) на dispose, pendingSnapshot → откат при ошибке); кламп по totalEpisodes (clampProgress); смена сезона → сброс (didUpdateWidget по ссылке); постер через baseUrl-склейку (#25); FractionallySizedBox-бар 200ms; 6 тестов полного цикла |
| 4 | `widgets/media-detail` | `SyncRowsSkeleton.svelte` | `lib/widgets/media-detail/sync_rows_skeleton.dart` | ✅ Готов | ✅ | 3 строки скелетона (bg-card, pulse через FadeTransition 1.5s, row 1 opacity-80), ширины 88/72/56% + w-2/5; ExcludeSemantics на визуале + Semantics liveRegion (role=status); 1 тест |
| 4 | `widgets/media-detail/__tests__` | `externalMapping.test.ts` | `test/widgets/media-detail/external_mapping_test.dart` | ✅ Готов | ✅ | Все 6 vitest-кейсов 1-в-1: raw relationType, ratings/score, даты/счётчики, missing year, format, title-fallback |
| 4 | `widgets/media-detail/__tests__` | `ratingBadges.test.ts` | `test/widgets/media-detail/rating_badges_test.dart` | ✅ Готов | ✅ | Оба vitest-кейса (linkedSources фильтр + пустой список) + TDD-сверхнабор: score 0 → queried-плейсхолдер, sociallib-зонт, выключенные источники, дедуп lowercase, fallback, includeMissing/fallbackSources |
| 4 | `widgets/media-detail/__tests__` | `relatedMatching.test.ts` | `test/widgets/media-detail/related_matching_test.dart` | ✅ Готов | ✅ | Все vitest-кейсы: normalize (латиница/кириллица/канзи), stripMovieMarker, каскад без кросс-матча TV vs Movie (Violet Evergarden fixture), findMatchingLocal + TDD: external-ID приоритет, game/book без romaji, пустая библиотека |
| 4 | `widgets/media-detail` | `detailFormatters.ts` | `lib/widgets/media-detail/detail_formatters.dart` | ✅ Готов | ✅ | Вытащен вперёд (решение #30, зависимость BaseCard → providerLink). Все 25 функций 1-в-1: providerLink (16 источников, slugify — см. #31), releaseStatusLabel (game/tv ветки, UTC-полночь date-only — 1-в-1 с new Date), readProgress, buildEpisodes (limit = min(total, max(watched, 200)) 1-в-1), relatedStatusColors (CSS-строки → типизированные цвета), specRows + lineage. statusLabel ре-экспорт. Типовые null-фиксы: currentChapter/totalEpisodesWatched null → 0 (TS-тип врал). 48 тестов |
| 4 | `widgets/media-detail` | `detailTypes.ts` | `lib/widgets/media-detail/detail_types.dart` | ✅ Готов | ✅ | Вытащен вперёд (зависимость BaseCard → providerLink): ProgressInfo/SpecRow/EpisodeRow/NextUp/RecommendationItem/RelatedEntry/RatingBadge/RelationGroup/TimelineEntry; SubTab/RelatedViewMode → enum c wire (конвенция enums.dart); read-only без toJson (YAGNI); smoke-тесты |
| 4 | `widgets/media-detail` | `externalMapping.ts` | `lib/widgets/media-detail/external_mapping.dart` | ✅ Готов | ✅ | toRelatedEntry: серверная relation → RelatedEntry (без i18n — caller даёт локализованный label); ratings → [RatingBadge(source, score)] при score>0 + externalSource; title-fallback «Title» |
| 4 | `widgets/media-detail/panels` | `RelatedPanel.svelte` | `lib/widgets/media-detail/panels/related_panel.dart` | ⬜ Не начат | ⬜ | — |
| 4 | `widgets/media-detail/panels` | `RelatedPreviewModal.svelte` | `lib/widgets/media-detail/panels/related_preview_modal.dart` | ⬜ Не начат | ⬜ | — |
| 4 | `widgets/media-detail` | `ratingBadges.ts` | `lib/widgets/media-detail/rating_badges.dart` | ✅ Готов | ✅ | buildRatingBadges: дедуп → fallback → linkedSources (containment-матч + resolve имён) → includeMissing-плейсхолдеры; score 0 = «спрошено, нет рейтинга» (queried); sociallib-зонт выбрасывается на всех ветках; RawRating/FallbackRating/RatingBadgeInput — типизированные входы |
| 4 | `widgets/media-detail` | `relatedMatching.ts` | `lib/widgets/media-detail/related_matching.dart` | ✅ Готов | ✅ | Каскад 5 шагов 1-в-1: externalId → originalTitle → romaji → кросс-матч нормализованных → movie-marker матч (оба — фильмы); normalizeTitle сохраняет канзи/хирагану/катакану; item.originalTitle — только у MediaDetail (`is MediaDetail` = TS runtime-cast эквивалент, решение #47); findMatchingLocal глотает исключения per-item |
| 4 | `widgets/media-detail` | `relationSources.ts` | `lib/widgets/media-detail/relation_sources.dart` | ✅ Готов | ✅ | Whitelist relations-источников (kRelationSources) × включённые пользователем; бакет anime через isAnime/detailFormatters; getSources через sourcesCachePromise (дедуп запросов); ошибка → [] (не роняет caller); 5 тестов полного цикла (stub dio) |
| 4 | `widgets/media-detail/sections` | `BookEditionSection.svelte` | `lib/widgets/media-detail/sections/book_edition_section.dart` | ⬜ Не начат | ⬜ | — |
| 4 | `widgets/media-detail/sections` | `BookProgressSection.svelte` | `lib/widgets/media-detail/sections/book_progress_section.dart` | ✅ Готов | ✅ | Новелла → главы (6 мин/глава, pace [1,2,3,5]) vs страницы (bookPageMinutes из uiSettings, pace [10,20,30,50], дефолт 20); effectiveTotal: totalChapters/totalPages/progress.total; amber-акцент; тесты в book_tv_progress_sections_test |
| 4 | `widgets/media-detail/sections` | `CastSection.svelte` | `lib/widgets/media-detail/sections/cast_section.dart` | ⬜ Не начат | ⬜ | — |
| 4 | `widgets/media-detail/sections` | `CreatorSection.svelte` | `lib/widgets/media-detail/sections/creator_section.dart` | ⬜ Не начат | ⬜ | — |
| 4 | `widgets/media-detail/sections` | `GameDetailSection.svelte` | `lib/widgets/media-detail/sections/game_detail_section.dart` | ⬜ Не начат | ⬜ | — |
| 4 | `widgets/media-detail/sections` | `LinkedSourcesSection.svelte` | `lib/widgets/media-detail/sections/linked_sources_section.dart` | ⬜ Не начат | ⬜ | — |
| 4 | `widgets/media-detail/sections` | `MangaProgressSection.svelte` | `lib/widgets/media-detail/sections/manga_progress_section.dart` | ✅ Готов | ✅ | Главы: minsPerChapter из uiSettings (дефолт 6), effectiveTotal: totalChapters/progress.total, amber, pace [1,2,3,5] дефолт 5; тест в movie_manga_notes_sections_test |
| 4 | `widgets/media-detail/sections` | `MediaFilesSection.svelte` | `lib/widgets/media-detail/sections/media_files_section.dart` | ⬜ Не начат | ⬜ | — |
| 4 | `widgets/media-detail/sections` | `MovieStatusSection.svelte` | `lib/widgets/media-detail/sections/movie_status_section.dart` | ✅ Готов | ✅ | Хронометраж (короткая + «~X ч. Y мин.»), быстрая смена planned/completed (selected: fill+ring 1-в-1, hover idle), amber-пилюля для промежуточных статусов, watchedOn-строка; ru/en-строки заголовка как в Svelte; 3 теста |
| 4 | `widgets/media-detail/sections` | `NotesSection.svelte` | `lib/widgets/media-detail/sections/notes_section.dart` | ⬜ Не начат | ⬜ | — |
| 4 | `widgets/media-detail/sections` | `PeopleSizeToggle.svelte` | `lib/widgets/media-detail/sections/people_size_toggle.dart` | ✅ Готов | ✅ | Иконочный toggle compact/large; cast/staff размеры раздельно (castSizeByCategory/staffSizeByCategory из стейт-карт — watch-реактивно); aria-pressed/aria-label через Semantics; 3 теста (дефолт, переключение, раздельное хранение) |
| 4 | `widgets/media-detail/sections` | `ProgressCard.svelte` | `lib/widgets/media-detail/sections/progress_card.dart` | ✅ Готов | ✅ | Кольцо SVG → CustomPainter (drawArc −90°, dash-переход 300ms), counter-pop 180ms ({#key value} → ValueKey), ручной ввод (autofocus, blur-коммит, Esc-отмена, кламп 0..total), иерархия кнопок Start/−/+1/+5, drag-установка по бару (Listener+LayoutBuilder = pointer capture), сегменты ≤36 vs непрерывный бар (150ms), milestones 25/50/75/100, блок времени + pace-чипы (finishEstimate через intl 'd MMMM'), completed-итог; 4 акцента (indigo/amber/teal/theme); 10 тестов полного цикла |
| 4 | `widgets/media-detail/sections` | `QuickFactsSection.svelte` | `lib/widgets/media-detail/sections/quick_facts_section.dart` | ⬜ Не начат | ⬜ | — |
| 4 | `widgets/media-detail/sections` | `QuotesSection.svelte` | `lib/widgets/media-detail/sections/quotes_section.dart` | ⬜ Не начат | ⬜ | — |
| 4 | `widgets/media-detail/sections` | `TrailerSection.svelte` | `lib/widgets/media-detail/sections/trailer_section.dart` | ✅ Готов | ✅ | YouTube-thumbnail + Play (hover scale 1.03, red-600/90); iframe недоступен без webview — Play открывает embed-URL через PlatformService.openExternalUrl (решение #48, фасад §1.3); без трейлера — заглушка Film/panel-line/40; 3 теста |
| 4 | `widgets/media-detail/sections` | `TvShowProgressSection.svelte` | `lib/widgets/media-detail/sections/tv_show_progress_section.dart` | ✅ Готов | ✅ | Минуты/серия: episodeDurationMinutes → durationMinutes → 24; tooltip total «Сезон N: M · …» для multi-season (seasons на MediaDetail); effectiveTotal: totalEpisodes/progress.total; indigo-акцент, pace [1,2,3,5] дефолт 2; тесты в book_tv_progress_sections_test |
| 4 | `widgets/media-detail/tabs` | `EpisodesTab.svelte` | `lib/widgets/media-detail/tabs/episodes_tab.dart` | ⬜ Не начат | ⬜ | — |
| 4 | `widgets/media-detail/tabs` | `GalleryTab.svelte` | `lib/widgets/media-detail/tabs/gallery_tab.dart` | ⬜ Не начат | ⬜ | — |
| 4 | `widgets/media-detail/tabs` | `OverviewTab.svelte` | `lib/widgets/media-detail/tabs/overview_tab.dart` | ⬜ Не начат | ⬜ | — |
| 4 | `widgets/media-detail/tabs` | `RecommendationsTab.svelte` | `lib/widgets/media-detail/tabs/recommendations_tab.dart` | ⬜ Не начат | ⬜ | — |
| 4 | `widgets/media-detail/tabs` | `RelatedTab.svelte` | `lib/widgets/media-detail/tabs/related_tab.dart` | ⬜ Не начат | ⬜ | — |
| 2 | `widgets/media-grid` | `MediaGrid.svelte` | `lib/widgets/media-grid/media_grid.dart` | ✅ Готов | ✅ | Sliver-версия (решение #37): SliverGrid с окном монтирования (поведение virtualGrid ⏭️), columnsForWidth 1-в-1 (колонки от ширины ОКНА — window.innerWidth), childAspectRatio 2/3 (титул на постере), timeHint через evaluateTimeFit/uiSettings, Remove-from-list X-кнопка, loading/error/empty-боксы 1-в-1; FLAT_LIMIT — константа-документация (SliverGrid виртуален всегда); 10 тестов |
| 2 | `widgets/media-grid` | `SectionRow.svelte` | `lib/widgets/media-grid/section_row.dart` | ✅ Готов | ✅ | Заголовок 25px w700 tracking-wide + счётчик bg-surface/text-muted rounded-full; space-y-3 = 12px между заголовком и сеткой; проброс всех колбеков в MediaGrid; слайвер-версия (решение #37); 3 теста |
| 2 | `widgets/media-grid/__tests__` | `virtualGrid.test.ts` | `—` | ⏭️ Заменено нативно | ⬜ | Тест JS-виртуализации не портируется; требования окна удаления покрываются widget/golden-тестами MediaGrid (Фаза 2) |
| 2 | `widgets/media-grid` | `gridLayout.svelte.ts` | `lib/widgets/media-grid/grid_layout.dart` | ✅ Готов | ✅ | Модульный счётчик версий инвалидации layout'а → Riverpod Notifier<int> (bumpGridLayout/read + watch — аналог эффект-трекинга); 3 теста |
| 2 | `widgets/media-grid` | `virtualGrid.ts` | `—` | ⏭️ Заменено нативно | ⬜ | Кастомный JS-виртуализатор сетки заменяется нативным GridView/custom_sliver_grid (сегменты секций — SectionRow); поведение окна удаления проверить на golden-ах |
| 5 | `widgets/stats` | `ActivityHeatmap.svelte` | `lib/widgets/stats/activity_heatmap.dart` | ⬜ Не начат | ⬜ | — |
| 5 | `widgets/stats` | `BacklogHealth.svelte` | `lib/widgets/stats/backlog_health.dart` | ⬜ Не начат | ⬜ | — |
| 5 | `widgets/stats` | `MonthlyActivityChart.svelte` | `lib/widgets/stats/monthly_activity_chart.dart` | ⬜ Не начат | ⬜ | — |
| 5 | `widgets/stats` | `RatingPsychology.svelte` | `lib/widgets/stats/rating_psychology.dart` | ⬜ Не начат | ⬜ | — |
| 5 | `widgets/stats` | `StatsHeroBanner.svelte` | `lib/widgets/stats/stats_hero_banner.dart` | ⬜ Не начат | ⬜ | — |
| 5 | `widgets/stats` | `TimeDistributionDonut.svelte` | `lib/widgets/stats/time_distribution_donut.dart` | ⬜ Не начат | ⬜ | — |
| 5 | `widgets/stats` | `TopGenresBar.svelte` | `lib/widgets/stats/top_genres_bar.dart` | ⬜ Не начат | ⬜ | — |
| 5 | `widgets/stats` | `TrackerBadges.svelte` | `lib/widgets/stats/tracker_badges.dart` | ⬜ Не начат | ⬜ | — |
| 5 | `widgets/stats/taste-profile` | `CriticalDivergenceCard.svelte` | `lib/widgets/stats/taste-profile/critical_divergence_card.dart` | ⬜ Не начат | ⬜ | — |
| 5 | `widgets/stats/taste-profile` | `DropAnalyticsCard.svelte` | `lib/widgets/stats/taste-profile/drop_analytics_card.dart` | ⬜ Не начат | ⬜ | — |
| 5 | `widgets/stats/taste-profile` | `EraAffinityCard.svelte` | `lib/widgets/stats/taste-profile/era_affinity_card.dart` | ⬜ Не начат | ⬜ | — |
| 5 | `widgets/stats/taste-profile` | `GenreParadoxCard.svelte` | `lib/widgets/stats/taste-profile/genre_paradox_card.dart` | ⬜ Не начат | ⬜ | — |
| 5 | `widgets/stats/taste-profile` | `GenreRadarChart.svelte` | `lib/widgets/stats/taste-profile/genre_radar_chart.dart` | ⬜ Не начат | ⬜ | — |
| 5 | `widgets/stats/taste-profile` | `SunkCostCard.svelte` | `lib/widgets/stats/taste-profile/sunk_cost_card.dart` | ⬜ Не начат | ⬜ | — |
| 5 | `widgets/stats/taste-profile` | `TastePersonaCard.svelte` | `lib/widgets/stats/taste-profile/taste_persona_card.dart` | ⬜ Не начат | ⬜ | — |
| 5 | `widgets/stats/taste-profile` | `genreLabel.ts` | `lib/widgets/stats/taste-profile/genre_label.dart` | ⬜ Не начат | ⬜ | — |

---

## 🐛 Лог найденных багов в исходниках Svelte

> Заполняется по протоколу §1.6 п.5: найден баг при изучении исходника — починить во
> Flutter-версии (или перенести как есть, если рискованно) и записать сюда ОБЯЗАТЕЛЬНО.

| # | Исходный файл | Описание бага | Исправлен во Flutter? | Пояснение (как исправлен / почему оставлен как есть) |
|---|---|---|---|---|
| 2 | `shared/utils/sourceUrlHelper.ts` | animelib-ветка получает УЖЕ encodeURIComponent-нутый id; зачистка префикса «ru/anime/» не срабатывает → двойное кодирование («ru%252Fanime…»), хотя комментарий обещает канонический URL | Исправлено: в buildAnimelibUrl передаётся сырой id (strip работает, одинарное кодирование) — тест фиксирует канонический URL | В TS поведение с двойным кодированием — вероятно реальный runtime-баг карточек animelib; сообщить апстриму при случае |
| 3 | `shared/types/models.dart` (порт, не Svelte) | `_strOrList` нормализовал строку genres/tags через split(',') без распаковки JSON-массива: payload вида `["Фэнтези","Драма"]` ломался на элементы `['["Фэнтези"', '"Драма"]']`. В TS строка оставалась сырой до parseGenresList, который JSON распаковывает | Да: в _strOrList добавлена попытка jsonDecode для `[...]`-строк (фолбэк — split(',')); тест в models_test.dart + кейсы в detail_formatters_test | Порт-баг (не Svelte): модель нормализует раньше, чем consumer — теперь обе стратегии дают одинаковый результат |
| 4 | `shared/ui/toast.svelte.ts` → порт (toast.dart) | Dart-стор добавил собственные TTL-таймеры auto-dismiss, которых НЕТ в Svelte: в Svelte dismiss живёт в ToastContainer (rAF-клок с паузой на hover и 1s-грейсом). Двойной dismiss ломал паузу (стор удалял тост под курсором) | Да: TTL-таймеры удалены из стора (dismiss — чистое состояние); авто-dismiss целиком в ToastContainer; тесты стора и контейнера обновлены | Порт-баг Фазы 1, вскрыт портированием контейнера (Фаза 3) |
| 5 | `shared/ui/modal.dart` (порт, не Svelte) | Material получал и borderRadius, и shape — фреймворк запрещает (assert). Всплывало при первом рендере модалки из ConfirmModal | Да: borderRadius убран — скругление и border-white/[0.08] несёт только RoundedRectangleBorder | Порт-баг Фазы 1 (Golden Фазы 1 модалку не рендерил) |
| 6 | `widgets/media-detail/ExternalDetailModal.svelte` → порт | Aside (`lg:w-64`) в desktop-Row получал unbounded width — Flutter Row даёт non-flex детям бесконечную ширину, spec-таблица (Row с Expanded) падала в layout-ассерт; в Svelte w-64 ограничивает | Да: aside обёрнут в SizedBox(width: 256) на desktop-ветке (постер — w-full внутрь); mobile-ветка — Column + постер w-40 mx-auto | Порт-баг, вскрыт widget-тестом превью в BackgroundJobsModal |
| 6 | `shared/ui/PopoverMenu.svelte` → порт (popover_menu.dart) | Триггер-кнопки поповеров/селекторов с ненулевым onPressed выигрывали арену жестов у внешнего GestureDetector поповера → тап не открывал меню (Svelte: popovertarget-атрибут, конфликта нет). Латентный баг Фазы 1 — TsundokuSelect не открывался вовсе | Да: триггеры оборачиваются в IgnorePointer (кнопка — визуал, тап уходит в поповер); FilterBar-триггеры сразу с фиксом; select-тесты дополнены | Порт-баг Фазы 1, вскрыт FilterBar (Фаза 3) |
---

## ⚖️ Спорные решения и развилки

> Заполняется по протоколу §1.6 п.11 (NO QUESTIONS): агент принял решение сам при
> неоднозначности / ограничении / выборе подхода — записать сюда обязательно.

| # | Файл | Спорный момент / вопрос | Принятое решение | Альтернатива / требует ли ревью |
|---|---|---|---|---|
| 1 | `shared/types/enums.ts` | TS-union не выражаются чистым enum: неизвестные wire-значения сервера; тайм-поля | `tryX` → null / `X.fromWire` → ArgumentError (fail fast); тайм-поля остаются wire-String 1-в-1, парсинг DateTime — у потребителей (YAGNI) | unknown-fallback enum-значения — нет (маскирует расхождение контракта); ревью не требуется |
| 2 | `shared/types/enums.ts` | Открытые union: `AppView` (…\|string-слаги), `SearchMediaType`/`SearchScope` («anime»/«all») | `AppView` → typedef String + `AppViews.builtin`; `SearchMediaType`/`SearchScope` → typedef String + known-наборы; `StatusFilter` → обёртка с nullable int | sealed-классы — избыточно для строковых union (YAGNI); ревью не требуется |
| 3 | `shared/types/models.ts` | `Record<number,number>`/`Record<string,number>` и `string[]\|string` не выражаются типом Dart напрямую | `Record` → `Map<int,double>`/`Map<String,double>` (JSON-ключи к int); `string[]\|string` (genres/tags) → `List<String>` (строка → split(',') + trim; дополнено 2026-11-21: JSON-массив-строка распаковывается первой — 1-в-1 с parseGenresList, см. 🐛 #3) | Плюрализация данных нет: строка «a, b» → [a, b] сохраняет содержимое; ревью не требуется |
| 4 | `shared/types/models.ts` | Иерархия MediaBase+5 вариантов и MediaItem/MediaDetail-union в Dart громоздка (переопределение nullable-полей запрещено) | Сервер шлёт плоский `MediaListDto` — порт в один плоский `MediaItem` (вариантные поля nullable, `type` различает) + `MediaDetail extends MediaItem` с detail-полями; сужения TS-типов теряются (nullable в потребителях) | Более строгая Dart-иерархия из 5 подклассов — двойной объём кода без выигрыша (YAGNI); ревью по желанию |
| 5 | `shared/theme/tsundoku_tokens.dart` | SDK 3.50 требует `ThemeExtension.copyWith`; per-field copyWith для 64 полей — объём без юзкейса | `copyWith()` — no-op копия (тема мержится целиком через lerp; YAGNI) | Полный named-copyWith — механическое раздувание; ревью не требуется |
| 6 | `shared/theme/tsundoku_theme.dart` | CSS-классы app.css (.panel/.tap/.media-card/scrollbar-thin/поповер-анимации) не выражаются в ThemeData | В ThemeData — только глобальное (диалоги/скроллбар 10px/поля/кнопки/кривые+длительности в TsundokuPalette); `.panel`/`.tap`/`thin-scroll` и анимации popover/dialog реализуются в соответствующих виджетах shared/ui (Фазы 1–3) | Глобальная имитация CSS-классов в ThemeData невозможна; ревью не требуется |
| 7 | `shared/api/api.ts` | api.ts импортирует networkActivity и i18n (errorMessage), но заявленный порядок шёл api → i18n | Порядок изменён: networkActivity → i18n → api.ts (сверху по зависимостям); зафиксировано в Next Step | Оставить исходный порядок с заглушками строк — хуже; ревью не требуется |
| 8 | `shared/i18n/index.svelte.ts` | TS-доступ `i18n.t.errors.x` (строгие вложенные объекты) не воспроизводится в Dart без генерации ~200 классов на 1528 листьев; функциональные листья — 112 замыканий | translations.dart — автогенерируемое paired-дерево (const Map) + плоский реестр функций; доступ через path-API `t.tr/tf/tl/tfl`; опечатка пути → ArgumentError с путём (в Svelte был undefined — Dart-вариант строже) | Генерация строгих Dart-классов — двойной объём без функциональной разницы (YAGNI); ревью по желанию |
| 9 | `shared/api/api.ts` | updateStatus принимает union `число \| {status, dropReason?, dropNotes?}`; dio сам бросает DioException на не-2xx; errorMessage использует i18n вне Riverpod-контекста | Два метода: `updateStatus` ({status}) и `updateStatusWithDropInfo` (null-поля сериализуются явно, как TS-объект); `validateStatus: (_) => true` — статусы обрабатывает _isOk/_throwApiError 1-в-1; errorMessage(error, locale) — локаль передаётся вызовом из UI | Ошибка/успех и payload'ы покрыты stub-адаптером Dio; ревью не требуется |
| 10 | `shared/api/*` (jobsClient/navigationCategories/offlineMode/serverRestart) | EventSource/window.history/AbortController — браузерные API; сетевые вызовы через голый fetch; DateTime.now в fakeAsync стартует с 0 | EventSource → dio streamed-ответ + SSE-парсер; history.pushState не нужен (Navigator); AbortController → per-request dio таймауты; сетевой клиент — TsundokuApi из провайдера (единый networkActivity/базовый URL); дедлайны serverRestart — параметры с дефолтами | Окноsse-фолбэки браузера (auto-reconnect) заменяются onError→syncJobs; ревью не требуется |
| 11 | `shared/utils/perfMarks.ts` | Performance API (performance.mark/measure) недоступна кроссплатформенно | Stopwatch-реестр tsundokuPerf (переносимый эквивалент); тесты | Нативные Chrome DevTools API — web-only; ревью не требуется |
| 12 | — | Утерянная строка прошлых сессий (ссылка на номер встречается без описания) | Не восстановим — номер не встречается ни в одном Пояснении | — |
| 13 | `shared/utils/progressDebounce.ts` + `viewport.svelte.ts` | visibilitychange/beforeunload и resize — браузерные события | progressDebounce: flush через AppLifecycle (Фаза 3); viewport: update() из MediaQuery в AppShell (Фаза 3, решение #13) | Временные заглушки до Фазы 3; ревью не требуется |
| 14 | `features/change-status` | Nullable dropReason/dropNotes не очищаются обычным copyWith (null ≠ «не менять») | copyWithFields + явный clearDropReasons() для очистки nullable | Альтернатива — sentinel-объект; ревью не требуется |
| 15 | `features/update-progress/*` | Контроллеры в Svelte дергают toast/i18n напрямую (глобальный синглтон) | showToast/i18n инъекция колбеками (toast-провайдер Фазы 1), тестируемость | Ревью не требуется |
| 16 | `features/prefetch-details/mediaDetailPrefetch.ts` | $state-кэш и планировщик в одном модуле не переносятся в Riverpod напрямую | core-кэш (detailCache) отделён от Ref/планировщика (HoverPrefetchScheduler), связка через провайдер | Ревью не требуется |
| 17 | — | Утерянная строка прошлых сессий (номер встречается без описания) | Не восстановим | — |
| 18 | — | Утерянная строка прошлых сессий (номер встречается без описания) | Не восстановим | — |
| 19 | — | Утерянная строка прошлых сессий (номер встречается без описания) | Не восстановим | — |
| 20 | `pubspec.yaml` (desktop_drop/file_picker) | wasm-Gate Фазы 0 красный: dart:html в file_picker 9–10, desktop_drop 0.9.2 требует cross_file 0.4 (несовместим с file_picker 9+) | file_picker → 11.0.3 (package:web), desktop_drop → 0.8.4 (cross_file 0.3.5+5); super_clipboard 0.9.1 остался; замечание #3 Заметок окружения (file_picker 7.0.2) устарело | Поднять desktop_drop обратно при выходе совместимой версии; ревью не требуется |
| 21 | `shared/ui/Modal.svelte` | Браузерные transition (popover/dialog-анимации) не выражаются в Flutter напрямую | Анимации 160/180/150ms (viewFade/popover/dialog) реализованы в TsundokuModal явно | Ревью не требуется |
| 22 | — | Утерянная строка прошлых сессий (номер встречается без описания) | Не восстановим | — |
| 23 | `shared/ui/Select.svelte` | TextButton.disabled в Flutter поглощает жесты иначе, чем браузерный disabled-кнопка — disabled-кейс widget-теста не воспроизводим | disabled-тест снят; disabled-ветка покрыта кодом (onPressed null) | Ревью не требуется |
| 24 | `shared/ui/ContextMenu.svelte` | Вложенные подменю в Flutter-оверлеях (anchor-positioning браузера) не воспроизводимы | Подменю — inline-раскрытие внутри панели (визуально 1-в-1, поведение идентично) | Ревью не требуется |
| 25 | `entities/media/ui/MediaPoster.svelte` | `<img src="/…">` в браузере резолвится от origin сервера; во Flutter нет неявного резолва | Image.network(baseUrl+src) — явная склейка 1-в-1 с TsundokuApi.absoluteUrl; baseUrl из apiBaseUrlProvider | Ревью не требуется |
| 26 | `entities/media/ui/MediaStatusBadge.svelte` | Lucide-иконки в Svelte поддерживают stroke-width/fill (Play filled, Check 3, X 4); lucide_icons_flutter — шрифт-иконка без вариаций | Единый вес иконок (размеры 20/21px сохранены 1-в-1); визуальная разница в толщине штриха принята | Нативные SVG-иконки — отдельная работа, YAGNI; ревью по желанию |
| 27 | `entities/media/ui/MediaScoreBadge.svelte` | -ml-2 (отрицательный margin) не выражается в Flutter напрямую | Transform.translate(Offset(-8, 0)) — визуальный оверхлап 1-в-1; layout-ширина кластера +8px (не видна: кластер прижат влево) | Ревью не требуется |
| 28 | `entities/media/ui/MediaPoster.svelte` | Проп children объявлен в Props, но шаблоном не рендерится ({@render children} отсутствует) — мёртвый API | Не переносился (YAGNI, 1-в-1 с фактическим поведением); слоты badges/actions перенесены | Если апстрим оживит children — добавить; ревью не требуется |
| 30 | `widgets/media-card/BaseCard.svelte` | BaseCard импортирует providerLink из Фазы 4 (detailFormatters) — фазовый порядок ломается | detailTypes.ts + detailFormatters.ts вытащены вперёд и портированы целиком (строки Фазы 4 закрыты досрочно); 1-в-1 file-mapping сохранён | Портировать BaseCard с инлайном providerLink — дублирование; ревью не требуется |
| 31 | `widgets/media-detail/detailFormatters.ts` | slugify использует NFKD-нормализацию + зачистку combining marks; в Dart String.normalize нет | Пакет diacritic (removeDiacritics) — эквивалент для латиницы; стек дополнен (§1.4) | Полный ICU-NFKD недоступен без тяжёлых зависимостей; для RAWG/IGDB-слагов диакритики покрывают кейс; ревью по желанию |
| 32 | `widgets/media-card/BaseCard.svelte` | navigator.clipboard / document-download-anchor / window.open — браузерные API; §1.3 требует платформенный фасад | `lib/shared/platform/`: PlatformService (copyText/copyImagePng/saveFile/openExternalUrl) + условный экспорт io (super_clipboard + file_picker.saveFile + url_launcher) / web (package:web) / stub; wasm-билд зелёный — dart:io не протёк | Проверено `flutter build web --wasm`; ревью не требуется |
| 44 | `widgets/media-detail/DetailHeader.svelte` | Раскрытие синопсиса — измеренный px (collapsedSynopsisHeight/scrollHeight + transition-[height] + transitionend→auto); inline-SVG AniList и Star с fill="currentColor" | Анимация → AnimatedSize 200ms (аналог grid-rows 0fr→1fr по поведению); clamp — maxLines 4 + ellipsis; AniList-путь перенесён 1-в-1 в CustomPaint (24→14 масштаб); Star — lucide-шрифт-иконка без fill (#26); sourceBadgeClasses — внутренний вызов mediaLabels вместо пропа | Ревью не требуется |
| 46 | `widgets/layout/BackgroundJobsModal.svelte` | Svelte мутирует jobsClient напрямую (`modalTab = …`, `pendingMatches = []`); hotkeys — svelte:window c isTextEntry(target) | jobsClient: аддитивные setModalTab/clearPendingMatches; hotkeys → Focus(autofocus, onKeyEvent) на модалке — Flutter сам не доставляет consumed-клавиши из TextField'ов (InsertContent), гвард _isTextEntryFocused (EditableText-предок) — двойная защита 1-в-1 с Svelte; сетка кандидатов grid-cols-2 → LayoutBuilder+Wrap (grid stretch не переносится — Spacer убран); баннер/статусы — точные i18n-ключи | Ревью не требуется |
| 47 | `widgets/media-detail/relatedMatching.ts` | `(item as {originalTitle?}).originalTitle` — runtime-cast: поле есть только в detail-интерфейсе TS, у MediaItem его нет (undefined в рантайме для list-объектов) | Dart: `item is MediaDetail ? item.originalTitle : null` — точный эквивалент рантайм-семантики TS (MediaDetail extends MediaItem); MediaItem.originalTitle намеренно НЕ добавлялся (YAGNI, контракт MediaListDto) | Ревью не требуется |
| 45 | `widgets/media-detail/ExternalDetailModal.svelte` | Svelte-компонент пересоздаётся на каждый открытый hit ($effect по `${type}:${source}:${id}` перезагружает детали); Flutter переиспользует State при том же типе виджета в той же позиции | didUpdateWidget сравнивает hit-key (type/source/externalId): смена → полный сброс стейта (synopsis/imgError/translated) + перезагрузка; тот же hit → кэш prefetch (TTL 10min) остаётся; поздний ответ не перезапишет чужой hit | Ревью не требуется |

---

## 📌 Заметки окружения (Этап 0, 2026-11-21)

1. **Flutter SDK** не был установлен в системе — установлен в `~/development/flutter`
   (official stable 3.50.1, Dart 3.14). Для будущих сессий:
   `export PATH="$HOME/development/flutter/bin:$PATH"` (рекомендуется добавить в `~/.zshrc`).
   Linux-тулчейн полный: clang 23.1.5, cmake 4.5.0, ninja 1.13.2, gtk3 3.24.52.
2. **Node сломан в системе**: `nodejs 26.13.1-2` требует `libsimdjson.so.36`, а пакет
   `libsimdjson` в pacman не установлен → любой `node` падает. Починка пользователя:
   `sudo pacman -S libsimdjson` (или `sudo pacman -Syu`). До починки Playwright-harness
   Svelte недоступен для новых скриншотов; существующие PNG-эталоны (backstop + snapshots)
   использовать из репозитория.
3. **file_picker** зафиксирован на 7.0.2: major 13.x конфликтует с соседними плагинами
   (window_manager 0.7 / super_clipboard 0.9 / desktop_drop 0.9 через plugin_platform_interface).
   Поднимать вместе, одним коммитом, когда появится причина.
4. **material.dart deprecated** в Flutter 3.50 (после v3.47): все новые файлы импортируют
   `package:material_ui/material_ui.dart` (официальная вынесенная Material-библиотека).
5. **Имя пакета** `tsundoku_flutter` (дефис в Dart-именах запрещён), папка `tsundoku-flutter/`,
   org `dev.tsundoku`, платформы: linux, windows, android, web.
9. **Flutter SDK переустановлен (2026-11-21, сессия продолжения)**: обнаружено, что
   `~/development/flutter` отсутствует в системе (см. заметку #1). Восстановлен официальный
   stable 3.50.1 (tar.xz с storage.googleapis.com) в `/home/maikun/development/flutter`.
   **Важно для агентов ZCode**: в этой среде `$HOME` = `/home/maikun/Profiles/ZCode3`, а не
   `/home/maikun` — `export PATH="$HOME/development/flutter/bin:$PATH"` НЕ работает;
   использовать абсолютный путь `export PATH="/home/maikun/development/flutter/bin:$PATH"`.
11. **Платформенный фасад (2026-11-21)**: создан `lib/shared/platform/` — interface
   PlatformService + условный экспорт (`platform.dart` → io/web/stub). Изолирует
   super_clipboard, file_picker, url_launcher от виджетов (§1.3); проверен wasm-билдом.
10. **Учёт миграции**: строки решений #11–#24 в «Спорных решениях» никогда не были записаны
   прошлыми сессиями (номера упоминались только в Пояснениях) — восстановлены по этим
   упоминаниям (#12/#17–#19/#22 не восстановимы, оставлены заглушками).
6. **Golden-инфраструктура**: эталоны 1440×900 @ dpr 1.0 (= backstop desktop вьюпорт Svelte).
   Шрифт Inter грузится в `test/flutter_test_config.dart`; тест `font_loader_weight_test.dart`
   гарантирует, что грузится настоящий Inter с весами 400/700/900 (попиксельная проверка
   различий), а не Ahem-плейсхолдер.
7. **Плагины** (уточнено 2026-11-21): Superpowers **установлен** v7.0.2 (маркетплейс
   `claude-plugins-official`; плагины ZCode живут в `~/.zcode/cli/plugins/`, а НЕ в
   `~/.claude/plugins` — первоначальная проверка смотрела не туда). Его скиллы подгружаются
   после перезапуска сессии. Ponytail **не установлен** — ставится только через UI клиента:
   Settings → Plugin Management → Discover → «+» → `DietrichGebert/ponytail` → Get
   (см. §1.5). `dart mcp-server` работает, конфиг добавлен в `.mcp.json` worktree.
| 33 | `widgets/media-card/cardTypes.ts` | TS-интерфейс MediaCardProps деконструируется в Svelte-пропы; в Dart named-параметры × 8 виджетов — дублирование | Card-виджеты получают единый MediaCardProps-бандл (состав полей 1-в-1); children/hover-слоты — отдельные параметры | Ревью не требуется |
| 34 | `features/*-controller` (status/progress/series) | Контроллеры держали `Ref`; из виджетов (BaseCard) Ref недоступен — только WidgetRef/ProviderContainer | Поле `ref` контроллеров и Ref-обёртки (reconcileProgress/loadMediaDetailRef/updateCachedDetailProgressRef/resolveSeriesStep) → `ProviderContainer` (только .read — семантика та же); виджеты передают `ProviderScope.containerOf(context)`, тесты — container; хелперы openContextMenu/openListPicker/confirmAction → WidgetRef (они UI-слой, 1-в-1 с Svelte-компонентами) | riverpod: Ref.container существует, но долгоживущий container чище; тесты обновлены; ревью по желанию |
| 35 | `widgets/media-card/BaseCard.svelte` | seriesProgressControllerProvider содержит no-op showToast (комментарий «Фаза 1 перепишет» не выполнен) — ошибки stepSeriesEpisodes не показываются | Зафиксировано как долг: реальный toast-инъекция подключается в Фазе 3 (AppShell), как и остальные глобальные shower'ы | Не блокирует Фазу 2; ревью не требуется |
| 36 | `features/update-progress/progressController.svelte.ts` | Svelte-контроллер реактивен ($state value/error → derived карточки); CardProgressState — plain-объект без нотификаций | Минимальный change-listener: addChangeListener/removeChangeListener + _notifyChanged в точках мутаций value/error + onChange в Options; карточка делает setState | ChangeNotifier — тяжеловеснее (dispose-конфликт с flush); ревью не требуется |
| 37 | `widgets/media-grid/MediaGrid.svelte` | TanStack-виртуализатор с scrollMargin/gridLayoutVersion-инвалидацией; FLAT_LIMIT 15; forceFlat | Нативные слайверы: MediaGrid возвращает SliverMainAxisGroup (SliverGrid сам держит окно монтирования; скроллер — общий CustomScrollView Phase 3 = #main-scroll); scrollMargin/bump в нативной схеме не нужны; FLAT_LIMIT/forceFlat — сохранены контрактно, поведения не меняют; MediaGridView — shrinkWrap-обёртка для standalone/тестов | Поведение окна удаления проверить golden-ами (см. строку virtualGrid ⏭️); ревью не требуется |
| 38 | `features/lists/ListPicker.svelte` | CreateListModal лениво грузится динамическим import'ом | Колбек onCreateList (App подключит при портировании CreateListModal, Фаза 5); refreshLists публичный для onSaved | Ревью не требуется |
| 39 | `views/CategoryView.svelte` | $effect-механика: fetch-эффект трекает deps (category/refreshKey/search/sort/promoted), $effect.pre сбрасывает состояние до отрисовки | Dart: fetch-эффект гвардится ключом зависимостей (перестройка sequence на каждом rebuild отбрасывала ответы); сброс состояния — initState/didUpdateWidget; вью монтируется с ValueKey(category) ({#key activeCategory}) — настоящий ремоунт | Ревью не требуется |
| 40 | `views/HomeView.svelte` | StaleBacklogModal лениво динамическим import'ом | Колбек onOpenStaleBacklog (App подключит при портировании StaleBacklogModal, Фаза 5) — как ListPicker onCreateList (#38) | Ревью не требуется |
| 41 | `views/HomeView.svelte` | window.addEventListener('tsundoku:random-pick') — desktop context-menu событие | HomeView.randomPick() публичный: App вызовет напрямую из контекст-меню (без window-шины) | Ревью не требуется |
| 42 | `app/App.svelte` | Роутер тянет вью/модалки Фаз 4–5 (detail/stats/lists/...; Search/Create/BackgroundJobs/StaleBacklog/FirstRun модалки) | Портирован каркас: портированные вью живые, остальные — заглушки _PlaceholderView с заголовком вью (виден в сайдбаре/header'е); модалки Фаз 4/5 — no-op-хуки с сохранёнными флагами стейта; при закрытии Фаз 4/5 заглушки заменяются | Явное отклонение 1-в-1 до закрытия Фаз 4/5; ревью обязательно при замене заглушек |
| 43 | `app/main.ts` | window.onerror → /api/logs/client | FlutterError.onError → api.sendClientLog (эндпоинт добавлен в TsundokuApi); dio прикрепляется в постфрейме (AppClientLogHook) | Ревью не требуется |
