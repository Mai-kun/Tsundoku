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

---

## 📍 Текущий фокус / Next Step

**Статус:** Этап 0 (инфраструктура) — ЗАВЕРШЁН и закоммичен. Портирование не начато.

**Прогресс: 6 / 207 файлов**

| Фаза | Файлов | Готово |
|---|---|---|
| 0 — Фундамент (типы/API/модели/логика/тема) | 58 | 6 |
| 1 — `shared/ui/` | 17 | 0 |
| 2 — `entities/` + карточки/сетка | 19 | 0 |
| 3 — Каркас: App/Layout/Home/Category | 13 | 0 |
| 4 — Детальная страница + Spatial Node Editor | 59 | 0 |
| 5 — Вью (Settings/Stats/Lists/History/Goals/Calendar) + модалки | 41 | 0 |
| **Всего** | **207** | **6** |

**Следующий конкретный файл:** `mediatracker-ui/src/shared/api/api.ts`
→ `lib/shared/api/api.dart` (dio-клиент с baseUrl-инъекцией, 1-в-1 эндпоинты).

**Следующие после него (жёсткая очерёдность Фазы 0):** `shared/types/models.ts` →
`dtos.ts` → `index.ts` → `app/tokens.css` + `app/app.css` (TsundokuTheme/ThemeData) →
`shared/api/*` (api.ts → jobsClient → navigationCategories → networkActivity → offlineMode
→ serverRestart) → `shared/i18n/*` → `shared/utils/*` → `entities/media/model/*` →
контроллеры `features/*` (change-status, drop-reason, mangalibAuth, prefetch-details,
update-progress) → `views/categoryModel.ts`. Файлы `⏭️ Заменено нативно` считаются
закрытыми; статус «Готово» фазы — когда все её строки ✅ или ⏭️.

---

## Полная таблица всех файлов (207 строк = 207 исходных файлов `mediatracker-ui/src/`)

> Проверено скриптом: `find mediatracker-ui/src -type f` = **207**; строк в таблице — **207**.
> Статусы: `⬜ Не начат` · `🟡 В работе` · `✅ Готов` · `⏭️ Заменено нативно` (с обязательным
> объяснением в «Пояснениях»). Колонка «Тест» — `⬜`/`✅` (тест полного цикла написан и зелёный).

| Фаза | Папка | Исходный файл (Svelte/TS) | Целевой файл (Dart) | Статус | Тест | Пояснения / Отклонения |
|---|---|---|---|---|---|---|
| 3 | `app` | `App.svelte` | `lib/app/app.dart` | ⬜ Не начат | ⬜ | — |
| 0 | `app` | `app.css` | `lib/shared/theme/tsundoku_theme.dart` | ✅ Готов | ✅ | daisyUI-слой tsundoku + @theme static → TsundokuPalette (литералы) + buildTsundokuTheme (ThemeData: кнопки/диалоги/скроллбар/поля); --font-sans: Inter; кривые/длительности (easeTap 0.2,0,0,1; viewFade/popover/dialog 140–150ms) |
| 0 | `app` | `clientErrors.ts` | `lib/app/client_errors.dart` | ⬜ Не начат | ⬜ | — |
| 3 | `app` | `main.ts` | `lib/app/main.dart` | ⬜ Не начат | ⬜ | — |
| 0 | `app` | `tokens.css` | `lib/shared/theme/tsundoku_tokens.dart` | ✅ Готов | ✅ | Все ~120 переменных → ThemeExtension<TsundokuTheme> (surfaces/borders/text/accent/status/13 chart/18 import-источников/9 badge); static const obsidian + themes-карта для смены тем; lerp всех групп |
| 0 | `entities/media/model/__tests__` | `chronicleTimeline.test.ts` | `test/entities/media/model/chronicle_timeline_test.dart` | ⬜ Не начат | ⬜ | — |
| 0 | `entities/media/model/__tests__` | `coverUrl.test.ts` | `test/entities/media/model/cover_url_test.dart` | ⬜ Не начат | ⬜ | — |
| 0 | `entities/media/model/__tests__` | `detailedScore.test.ts` | `test/entities/media/model/detailed_score_test.dart` | ⬜ Не начат | ⬜ | — |
| 0 | `entities/media/model/__tests__` | `seriesStep.test.ts` | `test/entities/media/model/series_step_test.dart` | ⬜ Не начат | ⬜ | — |
| 0 | `entities/media/model/__tests__` | `staleTriage.test.ts` | `test/entities/media/model/stale_triage_test.dart` | ⬜ Не начат | ⬜ | — |
| 0 | `entities/media/model/__tests__` | `timeBudget.test.ts` | `test/entities/media/model/time_budget_test.dart` | ⬜ Не начат | ⬜ | — |
| 0 | `entities/media/model` | `chronicleTimeline.ts` | `lib/entities/media/model/chronicle_timeline.dart` | ⬜ Не начат | ⬜ | — |
| 0 | `entities/media/model` | `coverUrl.ts` | `lib/entities/media/model/cover_url.dart` | ⬜ Не начат | ⬜ | — |
| 0 | `entities/media/model` | `detailedScore.ts` | `lib/entities/media/model/detailed_score.dart` | ⬜ Не начат | ⬜ | — |
| 0 | `entities/media/model` | `dropReasons.ts` | `lib/entities/media/model/drop_reasons.dart` | ⬜ Не начат | ⬜ | — |
| 0 | `entities/media/model` | `genreLabel.ts` | `lib/entities/media/model/genre_label.dart` | ⬜ Не начат | ⬜ | — |
| 0 | `entities/media/model` | `mediaLabels.ts` | `lib/entities/media/model/media_labels.dart` | ⬜ Не начат | ⬜ | — |
| 0 | `entities/media/model` | `progressRules.ts` | `lib/entities/media/model/progress_rules.dart` | ⬜ Не начат | ⬜ | — |
| 0 | `entities/media/model` | `seriesStep.ts` | `lib/entities/media/model/series_step.dart` | ⬜ Не начат | ⬜ | — |
| 0 | `entities/media/model` | `staleTriage.ts` | `lib/entities/media/model/stale_triage.dart` | ⬜ Не начат | ⬜ | — |
| 0 | `entities/media/model` | `timeBudget.ts` | `lib/entities/media/model/time_budget.dart` | ⬜ Не начат | ⬜ | — |
| 2 | `entities/media/ui` | `MediaPoster.svelte` | `lib/entities/media/ui/media_poster.dart` | ⬜ Не начат | ⬜ | — |
| 2 | `entities/media/ui` | `MediaScoreBadge.svelte` | `lib/entities/media/ui/media_score_badge.dart` | ⬜ Не начат | ⬜ | — |
| 2 | `entities/media/ui` | `MediaStatusBadge.svelte` | `lib/entities/media/ui/media_status_badge.dart` | ⬜ Не начат | ⬜ | — |
| 2 | `entities/media/ui` | `Placeholder404.svelte` | `lib/entities/media/ui/placeholder404.dart` | ⬜ Не начат | ⬜ | — |
| 0 | `features/change-status` | `statusController.svelte.ts` | `lib/features/change-status/status_controller.dart` | ⬜ Не начат | ⬜ | — |
| 5 | `features/create-media` | `BookFormFields.svelte` | `lib/features/create-media/book_form_fields.dart` | ⬜ Не начат | ⬜ | — |
| 5 | `features/create-media` | `CreateModal.svelte` | `lib/features/create-media/create_modal.dart` | ⬜ Не начат | ⬜ | — |
| 5 | `features/create-media` | `FormField.svelte` | `lib/features/create-media/form_field.dart` | ⬜ Не начат | ⬜ | — |
| 5 | `features/create-media` | `GameFormFields.svelte` | `lib/features/create-media/game_form_fields.dart` | ⬜ Не начат | ⬜ | — |
| 5 | `features/create-media` | `MangaFormFields.svelte` | `lib/features/create-media/manga_form_fields.dart` | ⬜ Не начат | ⬜ | — |
| 5 | `features/create-media` | `MovieFormFields.svelte` | `lib/features/create-media/movie_form_fields.dart` | ⬜ Не начат | ⬜ | — |
| 5 | `features/create-media` | `TvShowFormFields.svelte` | `lib/features/create-media/tv_show_form_fields.dart` | ⬜ Не начат | ⬜ | — |
| 5 | `features/drop-reason` | `DropReasonModal.svelte` | `lib/features/drop-reason/drop_reason_modal.dart` | ⬜ Не начат | ⬜ | — |
| 0 | `features/drop-reason` | `dropReasonPrompt.svelte.ts` | `lib/features/drop-reason/drop_reason_prompt.dart` | ⬜ Не начат | ⬜ | — |
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
| 3 | `features/filter-and-sort` | `FilterBar.svelte` | `lib/features/filter-and-sort/filter_bar.dart` | ⬜ Не начат | ⬜ | — |
| 5 | `features/goals` | `CreateGoalModal.svelte` | `lib/features/goals/create_goal_modal.dart` | ⬜ Не начат | ⬜ | — |
| 5 | `features/import-media` | `ImportModal.svelte` | `lib/features/import-media/import_modal.dart` | ⬜ Не начат | ⬜ | — |
| 5 | `features/import-media` | `ImportPanel.svelte` | `lib/features/import-media/import_panel.dart` | ⬜ Не начат | ⬜ | — |
| 0 | `features/import-media` | `mangalibAuth.svelte.ts` | `lib/features/import-media/mangalib_auth.dart` | ⬜ Не начат | ⬜ | — |
| 5 | `features/lists` | `CreateListModal.svelte` | `lib/features/lists/create_list_modal.dart` | ⬜ Не начат | ⬜ | — |
| 5 | `features/lists` | `ListPicker.svelte` | `lib/features/lists/list_picker.dart` | ⬜ Не начат | ⬜ | — |
| 5 | `features/lists` | `SmartListBuilder.svelte` | `lib/features/lists/smart_list_builder.dart` | ⬜ Не начат | ⬜ | — |
| 0 | `features/prefetch-details` | `externalDetailPrefetch.ts` | `lib/features/prefetch-details/external_detail_prefetch.dart` | ⬜ Не начат | ⬜ | — |
| 0 | `features/prefetch-details` | `mediaDetailPrefetch.ts` | `lib/features/prefetch-details/media_detail_prefetch.dart` | ⬜ Не начат | ⬜ | — |
| 5 | `features/search-external` | `SearchModal.svelte` | `lib/features/search-external/search_modal.dart` | ⬜ Не начат | ⬜ | — |
| 5 | `features/settings` | `FirstRunStorageModal.svelte` | `lib/features/settings/first_run_storage_modal.dart` | ⬜ Не начат | ⬜ | — |
| 5 | `features/settings` | `SettingsModal.svelte` | `lib/features/settings/settings_modal.dart` | ⬜ Не начат | ⬜ | — |
| 5 | `features/stale-triage` | `StaleBacklogModal.svelte` | `lib/features/stale-triage/stale_backlog_modal.dart` | ⬜ Не начат | ⬜ | — |
| 0 | `features/update-progress` | `optimisticProgress.svelte.ts` | `lib/features/update-progress/optimistic_progress.dart` | ⬜ Не начат | ⬜ | — |
| 0 | `features/update-progress` | `progressController.svelte.ts` | `lib/features/update-progress/progress_controller.dart` | ⬜ Не начат | ⬜ | — |
| 0 | `features/update-progress` | `seriesProgressController.svelte.ts` | `lib/features/update-progress/series_progress_controller.dart` | ⬜ Не начат | ⬜ | — |
| 0 | `features/update-progress` | `statusPromotionToast.svelte.ts` | `lib/features/update-progress/status_promotion_toast.dart` | ⬜ Не начат | ⬜ | — |
| 0 | `shared/api` | `api.ts` | `lib/shared/api/api.dart` | ⬜ Не начат | ⬜ | — |
| 0 | `shared/api` | `jobsClient.svelte.ts` | `lib/shared/api/jobs_client.dart` | ⬜ Не начат | ⬜ | — |
| 0 | `shared/api` | `navigationCategories.svelte.ts` | `lib/shared/api/navigation_categories.dart` | ⬜ Не начат | ⬜ | — |
| 0 | `shared/api` | `networkActivity.svelte.ts` | `lib/shared/api/network_activity.dart` | ⬜ Не начат | ⬜ | — |
| 0 | `shared/api` | `offlineMode.svelte.ts` | `lib/shared/api/offline_mode.dart` | ⬜ Не начат | ⬜ | — |
| 0 | `shared/api` | `serverRestart.svelte.ts` | `lib/shared/api/server_restart.dart` | ⬜ Не начат | ⬜ | — |
| 0 | `shared/i18n` | `index.svelte.ts` | `lib/shared/i18n/index.dart` | ⬜ Не начат | ⬜ | — |
| 0 | `shared/i18n` | `translations.ts` | `lib/shared/i18n/translations.dart` | ⬜ Не начат | ⬜ | — |
| 0 | `shared/types` | `dtos.ts` | `lib/shared/types/dtos.dart` | ✅ Готов | ✅ | Payload-классы с toJson (Create*/Update*/Smart/Import), read-only DTO с fromJson; CustomListDetail — отдельный класс (Dart не умеет Omit); CreateMediaBase supertype с полиморфным toJson |
| 0 | `shared/types` | `enums.ts` | `lib/shared/types/enums.dart` | ✅ Готов | ✅ | 1-в-1: числовые const-объекты → enum c `value`; строковые union → enum c `wire` (fromWire/tryFromWire); открытые union → String-typedef (решение #2); JobProgress перенесён сюда же |
| 0 | `shared/types` | `index.ts` | `lib/shared/types/index.dart` | ✅ Готов | ✅ | Barrel `export *` → Dart-экспорт-файл; тест гарантирует доступность всех типов через единый import |
| 0 | `shared/types` | `models.ts` | `lib/shared/types/models.dart` | ✅ Готов | ✅ | Плоский MediaItem (сервер шлёт плоский MediaListDto) + MediaDetail с detail-полями; Record→Map, string[]\|string→List (решения #3/#4); read-only модели без toJson (YAGNI) |
| 1 | `shared/ui` | `Badge.svelte` | `lib/shared/ui/badge.dart` | ⬜ Не начат | ⬜ | — |
| 1 | `shared/ui` | `Button.svelte` | `lib/shared/ui/button.dart` | ⬜ Не начат | ⬜ | — |
| 1 | `shared/ui` | `ConfirmModal.svelte` | `lib/shared/ui/confirm_modal.dart` | ⬜ Не начат | ⬜ | — |
| 1 | `shared/ui` | `ContextMenu.svelte` | `lib/shared/ui/context_menu.dart` | ⬜ Не начат | ⬜ | — |
| 1 | `shared/ui` | `Icons.ts` | `—` | ⏭️ Заменено нативно | ⬜ | Мост иконок lucide→Svelte заменяется прямым использованием пакета lucide_icons_flutter (те же имена иконок LucideIcons.*) |
| 1 | `shared/ui` | `ImageLightbox.svelte` | `lib/shared/ui/image_lightbox.dart` | ⬜ Не начат | ⬜ | — |
| 1 | `shared/ui` | `MediaCoverPlaceholder.svelte` | `lib/shared/ui/media_cover_placeholder.dart` | ⬜ Не начат | ⬜ | — |
| 1 | `shared/ui` | `Modal.svelte` | `lib/shared/ui/modal.dart` | ⬜ Не начат | ⬜ | — |
| 1 | `shared/ui` | `Panel.svelte` | `lib/shared/ui/panel.dart` | ⬜ Не начат | ⬜ | — |
| 1 | `shared/ui` | `PopoverMenu.svelte` | `lib/shared/ui/popover_menu.dart` | ⬜ Не начат | ⬜ | — |
| 1 | `shared/ui` | `Select.svelte` | `lib/shared/ui/select.dart` | ⬜ Не начат | ⬜ | — |
| 1 | `shared/ui` | `TotalBadge.svelte` | `lib/shared/ui/total_badge.dart` | ⬜ Не начат | ⬜ | — |
| 1 | `shared/ui` | `confirmDialog.svelte.ts` | `lib/shared/ui/confirm_dialog.dart` | ⬜ Не начат | ⬜ | — |
| 1 | `shared/ui` | `contextMenu.svelte.ts` | `lib/shared/ui/context_menu_controller.dart` | ⬜ Не начат | ⬜ | Контроллер стейта контекстного меню (Riverpod); выделен в отдельный файл, чтобы не сливаться с одноимённым виджетом context_menu.dart |
| 1 | `shared/ui` | `holdToDelete.svelte.ts` | `lib/shared/ui/hold_to_delete.dart` | ⬜ Не начат | ⬜ | — |
| 1 | `shared/ui` | `lightbox.svelte.ts` | `lib/shared/ui/lightbox.dart` | ⬜ Не начат | ⬜ | — |
| 1 | `shared/ui` | `toast.svelte.ts` | `lib/shared/ui/toast.dart` | ⬜ Не начат | ⬜ | — |
| 0 | `shared/utils/__tests__` | `clientErrors.test.ts` | `test/shared/utils/client_errors_test.dart` | ⬜ Не начат | ⬜ | — |
| 0 | `shared/utils/__tests__` | `perfMarks.test.ts` | `test/shared/utils/perf_marks_test.dart` | ⬜ Не начат | ⬜ | — |
| 0 | `shared/utils/__tests__` | `prefetchCache.test.ts` | `test/shared/utils/prefetch_cache_test.dart` | ⬜ Не начат | ⬜ | — |
| 0 | `shared/utils/__tests__` | `urlMediaParser.test.ts` | `test/shared/utils/url_media_parser_test.dart` | ⬜ Не начат | ⬜ | — |
| 0 | `shared/utils` | `appExit.ts` | `lib/shared/utils/app_exit.dart` | ⬜ Не начат | ⬜ | — |
| 0 | `shared/utils` | `historyFormatters.ts` | `lib/shared/utils/history_formatters.dart` | ⬜ Не начат | ⬜ | — |
| 0 | `shared/utils` | `perfMarks.ts` | `lib/shared/utils/perf_marks.dart` | ⬜ Не начат | ⬜ | — |
| 0 | `shared/utils` | `prefetchCache.ts` | `lib/shared/utils/prefetch_cache.dart` | ⬜ Не начат | ⬜ | — |
| 0 | `shared/utils` | `progressDebounce.ts` | `lib/shared/utils/progress_debounce.dart` | ⬜ Не начат | ⬜ | — |
| 0 | `shared/utils` | `reactivityDebug.svelte.ts` | `—` | ⏭️ Заменено нативно | ⬜ | Отладчик реактивности Svelte 5 не нужен: Flutter DevTools/Riverpod Observer покрывают диагностику стейта |
| 0 | `shared/utils` | `sourceUrlHelper.ts` | `lib/shared/utils/source_url_helper.dart` | ⬜ Не начат | ⬜ | — |
| 0 | `shared/utils` | `swrCache.ts` | `lib/shared/utils/swr_cache.dart` | ⬜ Не начат | ⬜ | — |
| 0 | `shared/utils` | `uiSettings.svelte.ts` | `lib/shared/utils/ui_settings.dart` | ⬜ Не начат | ⬜ | — |
| 0 | `shared/utils` | `unknownCreator.ts` | `lib/shared/utils/unknown_creator.dart` | ⬜ Не начат | ⬜ | — |
| 0 | `shared/utils` | `urlMediaParser.ts` | `lib/shared/utils/url_media_parser.dart` | ⬜ Не начат | ⬜ | — |
| 0 | `shared/utils` | `viewport.svelte.ts` | `lib/shared/utils/viewport.dart` | ⬜ Не начат | ⬜ | — |
| 5 | `views` | `CalendarView.svelte` | `lib/views/calendar_view.dart` | ⬜ Не начат | ⬜ | — |
| 3 | `views` | `CategoryView.svelte` | `lib/views/category_view.dart` | ⬜ Не начат | ⬜ | — |
| 5 | `views` | `GoalsView.svelte` | `lib/views/goals_view.dart` | ⬜ Не начат | ⬜ | — |
| 5 | `views` | `HistoryView.svelte` | `lib/views/history_view.dart` | ⬜ Не начат | ⬜ | — |
| 3 | `views` | `HomeView.svelte` | `lib/views/home_view.dart` | ⬜ Не начат | ⬜ | — |
| 5 | `views` | `ListsView.svelte` | `lib/views/lists_view.dart` | ⬜ Не начат | ⬜ | — |
| 4 | `views` | `MediaDetailView.svelte` | `lib/views/media_detail_view.dart` | ⬜ Не начат | ⬜ | — |
| 5 | `views` | `SettingsView.svelte` | `lib/views/settings_view.dart` | ⬜ Не начат | ⬜ | — |
| 4 | `views` | `ShowSeasonsView.svelte` | `lib/views/show_seasons_view.dart` | ⬜ Не начат | ⬜ | — |
| 5 | `views` | `StatsView.svelte` | `lib/views/stats_view.dart` | ⬜ Не начат | ⬜ | — |
| 3 | `views/__tests__` | `CategoryView.test.ts` | `test/views/category_view_test.dart` | ⬜ Не начат | ⬜ | — |
| 0 | `views/__tests__` | `categoryModel.test.ts` | `test/views/category_model_test.dart` | ⬜ Не начат | ⬜ | — |
| 0 | `views` | `categoryModel.ts` | `lib/views/category_model.dart` | ⬜ Не начат | ⬜ | — |
| 5 | `widgets/goals` | `GoalCard.svelte` | `lib/widgets/goals/goal_card.dart` | ⬜ Не начат | ⬜ | — |
| 3 | `widgets/layout` | `ActivityDropdown.svelte` | `lib/widgets/layout/activity_dropdown.dart` | ⬜ Не начат | ⬜ | — |
| 3 | `widgets/layout` | `AppShell.svelte` | `lib/widgets/layout/app_shell.dart` | ⬜ Не начат | ⬜ | — |
| 3 | `widgets/layout` | `BackgroundJobsModal.svelte` | `lib/widgets/layout/background_jobs_modal.dart` | ⬜ Не начат | ⬜ | — |
| 3 | `widgets/layout` | `CloseAppModal.svelte` | `lib/widgets/layout/close_app_modal.dart` | ⬜ Не начат | ⬜ | — |
| 3 | `widgets/layout` | `Header.svelte` | `lib/widgets/layout/header.dart` | ⬜ Не начат | ⬜ | — |
| 3 | `widgets/layout` | `Sidebar.svelte` | `lib/widgets/layout/sidebar.dart` | ⬜ Не начат | ⬜ | — |
| 3 | `widgets/layout` | `ToastContainer.svelte` | `lib/widgets/layout/toast_container.dart` | ⬜ Не начат | ⬜ | — |
| 2 | `widgets/media-card` | `BaseCard.svelte` | `lib/widgets/media-card/base_card.dart` | ⬜ Не начат | ⬜ | — |
| 2 | `widgets/media-card` | `BookCard.svelte` | `lib/widgets/media-card/book_card.dart` | ⬜ Не начат | ⬜ | — |
| 2 | `widgets/media-card` | `CardProgressControls.svelte` | `lib/widgets/media-card/card_progress_controls.dart` | ⬜ Не начат | ⬜ | — |
| 2 | `widgets/media-card` | `CardTitleBlock.svelte` | `lib/widgets/media-card/card_title_block.dart` | ⬜ Не начат | ⬜ | — |
| 2 | `widgets/media-card` | `GameCard.svelte` | `lib/widgets/media-card/game_card.dart` | ⬜ Не начат | ⬜ | — |
| 2 | `widgets/media-card` | `MangaCard.svelte` | `lib/widgets/media-card/manga_card.dart` | ⬜ Не начат | ⬜ | — |
| 2 | `widgets/media-card` | `MediaCard.svelte` | `lib/widgets/media-card/media_card.dart` | ⬜ Не начат | ⬜ | — |
| 2 | `widgets/media-card` | `MovieCard.svelte` | `lib/widgets/media-card/movie_card.dart` | ⬜ Не начат | ⬜ | — |
| 2 | `widgets/media-card` | `TvShowCard.svelte` | `lib/widgets/media-card/tv_show_card.dart` | ⬜ Не начат | ⬜ | — |
| 2 | `widgets/media-card` | `cardTypes.ts` | `lib/widgets/media-card/card_types.dart` | ⬜ Не начат | ⬜ | — |
| 4 | `widgets/media-detail` | `CoverManagerModal.svelte` | `lib/widgets/media-detail/cover_manager_modal.dart` | ⬜ Не начат | ⬜ | — |
| 4 | `widgets/media-detail` | `DetailHeader.svelte` | `lib/widgets/media-detail/detail_header.dart` | ⬜ Не начат | ⬜ | — |
| 4 | `widgets/media-detail` | `DetailSidebar.svelte` | `lib/widgets/media-detail/detail_sidebar.dart` | ⬜ Не начат | ⬜ | — |
| 4 | `widgets/media-detail` | `DetailTabs.svelte` | `lib/widgets/media-detail/detail_tabs.dart` | ⬜ Не начат | ⬜ | — |
| 4 | `widgets/media-detail` | `ExternalDetailModal.svelte` | `lib/widgets/media-detail/external_detail_modal.dart` | ⬜ Не начат | ⬜ | — |
| 4 | `widgets/media-detail` | `FillMissingModal.svelte` | `lib/widgets/media-detail/fill_missing_modal.dart` | ⬜ Не начат | ⬜ | — |
| 4 | `widgets/media-detail` | `MediaActivityModal.svelte` | `lib/widgets/media-detail/media_activity_modal.dart` | ⬜ Не начат | ⬜ | — |
| 4 | `widgets/media-detail` | `OverwriteConfirmModal.svelte` | `lib/widgets/media-detail/overwrite_confirm_modal.dart` | ⬜ Не начат | ⬜ | — |
| 4 | `widgets/media-detail` | `ProgressStepper.svelte` | `lib/widgets/media-detail/progress_stepper.dart` | ⬜ Не начат | ⬜ | — |
| 4 | `widgets/media-detail` | `RelationLoadButton.svelte` | `lib/widgets/media-detail/relation_load_button.dart` | ⬜ Не начат | ⬜ | — |
| 4 | `widgets/media-detail` | `RelinkSourceModal.svelte` | `lib/widgets/media-detail/relink_source_modal.dart` | ⬜ Не начат | ⬜ | — |
| 4 | `widgets/media-detail` | `SeasonRow.svelte` | `lib/widgets/media-detail/season_row.dart` | ⬜ Не начат | ⬜ | — |
| 4 | `widgets/media-detail` | `SyncRowsSkeleton.svelte` | `lib/widgets/media-detail/sync_rows_skeleton.dart` | ⬜ Не начат | ⬜ | — |
| 4 | `widgets/media-detail/__tests__` | `externalMapping.test.ts` | `test/widgets/media-detail/external_mapping_test.dart` | ⬜ Не начат | ⬜ | — |
| 4 | `widgets/media-detail/__tests__` | `ratingBadges.test.ts` | `test/widgets/media-detail/rating_badges_test.dart` | ⬜ Не начат | ⬜ | — |
| 4 | `widgets/media-detail/__tests__` | `relatedMatching.test.ts` | `test/widgets/media-detail/related_matching_test.dart` | ⬜ Не начат | ⬜ | — |
| 4 | `widgets/media-detail` | `detailFormatters.ts` | `lib/widgets/media-detail/detail_formatters.dart` | ⬜ Не начат | ⬜ | — |
| 4 | `widgets/media-detail` | `detailTypes.ts` | `lib/widgets/media-detail/detail_types.dart` | ⬜ Не начат | ⬜ | — |
| 4 | `widgets/media-detail` | `externalMapping.ts` | `lib/widgets/media-detail/external_mapping.dart` | ⬜ Не начат | ⬜ | — |
| 4 | `widgets/media-detail/panels` | `RelatedPanel.svelte` | `lib/widgets/media-detail/panels/related_panel.dart` | ⬜ Не начат | ⬜ | — |
| 4 | `widgets/media-detail/panels` | `RelatedPreviewModal.svelte` | `lib/widgets/media-detail/panels/related_preview_modal.dart` | ⬜ Не начат | ⬜ | — |
| 4 | `widgets/media-detail` | `ratingBadges.ts` | `lib/widgets/media-detail/rating_badges.dart` | ⬜ Не начат | ⬜ | — |
| 4 | `widgets/media-detail` | `relatedMatching.ts` | `lib/widgets/media-detail/related_matching.dart` | ⬜ Не начат | ⬜ | — |
| 4 | `widgets/media-detail` | `relationSources.ts` | `lib/widgets/media-detail/relation_sources.dart` | ⬜ Не начат | ⬜ | — |
| 4 | `widgets/media-detail/sections` | `BookEditionSection.svelte` | `lib/widgets/media-detail/sections/book_edition_section.dart` | ⬜ Не начат | ⬜ | — |
| 4 | `widgets/media-detail/sections` | `BookProgressSection.svelte` | `lib/widgets/media-detail/sections/book_progress_section.dart` | ⬜ Не начат | ⬜ | — |
| 4 | `widgets/media-detail/sections` | `CastSection.svelte` | `lib/widgets/media-detail/sections/cast_section.dart` | ⬜ Не начат | ⬜ | — |
| 4 | `widgets/media-detail/sections` | `CreatorSection.svelte` | `lib/widgets/media-detail/sections/creator_section.dart` | ⬜ Не начат | ⬜ | — |
| 4 | `widgets/media-detail/sections` | `GameDetailSection.svelte` | `lib/widgets/media-detail/sections/game_detail_section.dart` | ⬜ Не начат | ⬜ | — |
| 4 | `widgets/media-detail/sections` | `LinkedSourcesSection.svelte` | `lib/widgets/media-detail/sections/linked_sources_section.dart` | ⬜ Не начат | ⬜ | — |
| 4 | `widgets/media-detail/sections` | `MangaProgressSection.svelte` | `lib/widgets/media-detail/sections/manga_progress_section.dart` | ⬜ Не начат | ⬜ | — |
| 4 | `widgets/media-detail/sections` | `MediaFilesSection.svelte` | `lib/widgets/media-detail/sections/media_files_section.dart` | ⬜ Не начат | ⬜ | — |
| 4 | `widgets/media-detail/sections` | `MovieStatusSection.svelte` | `lib/widgets/media-detail/sections/movie_status_section.dart` | ⬜ Не начат | ⬜ | — |
| 4 | `widgets/media-detail/sections` | `NotesSection.svelte` | `lib/widgets/media-detail/sections/notes_section.dart` | ⬜ Не начат | ⬜ | — |
| 4 | `widgets/media-detail/sections` | `PeopleSizeToggle.svelte` | `lib/widgets/media-detail/sections/people_size_toggle.dart` | ⬜ Не начат | ⬜ | — |
| 4 | `widgets/media-detail/sections` | `ProgressCard.svelte` | `lib/widgets/media-detail/sections/progress_card.dart` | ⬜ Не начат | ⬜ | — |
| 4 | `widgets/media-detail/sections` | `QuickFactsSection.svelte` | `lib/widgets/media-detail/sections/quick_facts_section.dart` | ⬜ Не начат | ⬜ | — |
| 4 | `widgets/media-detail/sections` | `QuotesSection.svelte` | `lib/widgets/media-detail/sections/quotes_section.dart` | ⬜ Не начат | ⬜ | — |
| 4 | `widgets/media-detail/sections` | `TrailerSection.svelte` | `lib/widgets/media-detail/sections/trailer_section.dart` | ⬜ Не начат | ⬜ | — |
| 4 | `widgets/media-detail/sections` | `TvShowProgressSection.svelte` | `lib/widgets/media-detail/sections/tv_show_progress_section.dart` | ⬜ Не начат | ⬜ | — |
| 4 | `widgets/media-detail/tabs` | `EpisodesTab.svelte` | `lib/widgets/media-detail/tabs/episodes_tab.dart` | ⬜ Не начат | ⬜ | — |
| 4 | `widgets/media-detail/tabs` | `GalleryTab.svelte` | `lib/widgets/media-detail/tabs/gallery_tab.dart` | ⬜ Не начат | ⬜ | — |
| 4 | `widgets/media-detail/tabs` | `OverviewTab.svelte` | `lib/widgets/media-detail/tabs/overview_tab.dart` | ⬜ Не начат | ⬜ | — |
| 4 | `widgets/media-detail/tabs` | `RecommendationsTab.svelte` | `lib/widgets/media-detail/tabs/recommendations_tab.dart` | ⬜ Не начат | ⬜ | — |
| 4 | `widgets/media-detail/tabs` | `RelatedTab.svelte` | `lib/widgets/media-detail/tabs/related_tab.dart` | ⬜ Не начат | ⬜ | — |
| 2 | `widgets/media-grid` | `MediaGrid.svelte` | `lib/widgets/media-grid/media_grid.dart` | ⬜ Не начат | ⬜ | — |
| 2 | `widgets/media-grid` | `SectionRow.svelte` | `lib/widgets/media-grid/section_row.dart` | ⬜ Не начат | ⬜ | — |
| 2 | `widgets/media-grid/__tests__` | `virtualGrid.test.ts` | `—` | ⏭️ Заменено нативно | ⬜ | Тест JS-виртуализации не портируется; требования окна удаления покрываются widget/golden-тестами MediaGrid (Фаза 2) |
| 2 | `widgets/media-grid` | `gridLayout.svelte.ts` | `lib/widgets/media-grid/grid_layout.dart` | ⬜ Не начат | ⬜ | — |
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
| — | — | Багов пока не найдено (Этап 0: портирование не началось) | — | Таблица заполняется по мере прохождения файлов Фаз 0–5 |

---

## ⚖️ Спорные решения и развилки

> Заполняется по протоколу §1.6 п.11 (NO QUESTIONS): агент принял решение сам при
> неоднозначности / ограничении / выборе подхода — записать сюда обязательно.

| # | Файл | Спорный момент / вопрос | Принятое решение | Альтернатива / требует ли ревью |
|---|---|---|---|---|
| 1 | `shared/types/enums.ts` | TS-union не выражаются чистым enum: неизвестные wire-значения сервера; тайм-поля | `tryX` → null / `X.fromWire` → ArgumentError (fail fast); тайм-поля остаются wire-String 1-в-1, парсинг DateTime — у потребителей (YAGNI) | unknown-fallback enum-значения — нет (маскирует расхождение контракта); ревью не требуется |
| 2 | `shared/types/enums.ts` | Открытые union: `AppView` (…\|string-слаги), `SearchMediaType`/`SearchScope` («anime»/«all») | `AppView` → typedef String + `AppViews.builtin`; `SearchMediaType`/`SearchScope` → typedef String + known-наборы; `StatusFilter` → обёртка с nullable int | sealed-классы — избыточно для строковых union (YAGNI); ревью не требуется |
| 3 | `shared/types/models.ts` | `Record<number,number>`/`Record<string,number>` и `string[]\|string` не выражаются типом Dart напрямую | `Record` → `Map<int,double>`/`Map<String,double>` (JSON-ключи к int); `string[]\|string` (genres/tags) → `List<String>` (строка → split(',') + trim) | Плюрализация данных нет: строка «a, b» → [a, b] сохраняет содержимое; ревью не требуется |
| 4 | `shared/types/models.ts` | Иерархия MediaBase+5 вариантов и MediaItem/MediaDetail-union в Dart громоздка (переопределение nullable-полей запрещено) | Сервер шлёт плоский `MediaListDto` — порт в один плоский `MediaItem` (вариантные поля nullable, `type` различает) + `MediaDetail extends MediaItem` с detail-полями; сужения TS-типов теряются (nullable в потребителях) | Более строгая Dart-иерархия из 5 подклассов — двойной объём кода без выигрыша (YAGNI); ревью по желанию |
| 5 | `shared/theme/tsundoku_tokens.dart` | SDK 3.50 требует `ThemeExtension.copyWith`; per-field copyWith для 64 полей — объём без юзкейса | `copyWith()` — no-op копия (тема мержится целиком через lerp; YAGNI) | Полный named-copyWith — механическое раздувание; ревью не требуется |
| 6 | `shared/theme/tsundoku_theme.dart` | CSS-классы app.css (.panel/.tap/.media-card/scrollbar-thin/поповер-анимации) не выражаются в ThemeData | В ThemeData — только глобальное (диалоги/скроллбар 10px/поля/кнопки/кривые+длительности в TsundokuPalette); `.panel`/`.tap`/`thin-scroll` и анимации popover/dialog реализуются в соответствующих виджетах shared/ui (Фазы 1–3) | Глобальная имитация CSS-классов в ThemeData невозможна; ревью не требуется |

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
