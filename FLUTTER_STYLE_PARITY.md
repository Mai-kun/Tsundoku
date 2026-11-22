# 🎯 Аудит и выравнивание стилей Flutter UI 1-в-1 со Svelte (Tailwind CSS / tokens.css)

## 📍 Текущий фокус / Next Step
* **Фаза:** S4 (features/**)
* **Текущий файл:** `mediatracker-ui/src/features/search-external/SearchModal.svelte` -> `tsundoku-flutter/lib/features/search-external/search_modal.dart`
* **Цель:** Сверка SearchModal: поисковый инпут с иконкой, дебаунс, сетка карточек внешнего поиска, пагинация, модалка.

---

## 📐 Строгий словарь перевода Tailwind CSS / CSS → Flutter

### 1. Отступы (Spacing, 1 unit = 4px)
| Tailwind класс | Пиксели (Flutter) | Код Flutter |
| :--- | :--- | :--- |
| `p-0.5` / `gap-0.5` | 2px | `EdgeInsets.all(2)` / `const SizedBox(width: 2)` |
| `p-1` / `gap-1` | 4px | `EdgeInsets.all(4)` / `const SizedBox(width: 4)` |
| `p-1.5` / `gap-1.5` | 6px | `EdgeInsets.all(6)` / `const SizedBox(width: 6)` |
| `p-2` / `gap-2` | 8px | `EdgeInsets.all(8)` / `const SizedBox(width: 8)` |
| `p-2.5` / `gap-2.5` | 10px | `EdgeInsets.all(10)` / `const SizedBox(width: 10)` |
| `p-3` / `gap-3` | 12px | `EdgeInsets.all(12)` / `const SizedBox(width: 12)` |
| `p-3.5` / `gap-3.5` | 14px | `EdgeInsets.all(14)` / `const SizedBox(width: 14)` |
| `p-4` / `gap-4` | 16px | `EdgeInsets.all(16)` / `const SizedBox(width: 16)` |
| `p-5` / `gap-5` | 20px | `EdgeInsets.all(20)` / `const SizedBox(width: 20)` |
| `p-6` / `gap-6` | 24px | `EdgeInsets.all(24)` / `const SizedBox(width: 24)` |
| `p-7` / `gap-7` | 28px | `EdgeInsets.all(28)` / `const SizedBox(width: 28)` |
| `p-8` / `gap-8` | 32px | `EdgeInsets.all(32)` / `const SizedBox(width: 32)` |
| `p-10` / `gap-10` | 40px | `EdgeInsets.all(40)` / `const SizedBox(width: 40)` |
| `p-12` / `gap-12` | 48px | `EdgeInsets.all(48)` / `const SizedBox(width: 48)` |
| `p-16` / `gap-16` | 64px | `EdgeInsets.all(64)` / `const SizedBox(width: 64)` |
*Никаких округлений «на глаз»! Строго 4 * unit.*

### 2. Размеры и ограничения ширины (Max-width & Width)
| Tailwind класс | Ограничение (Flutter) |
| :--- | :--- |
| `max-w-xs` | `ConstrainedBox(constraints: BoxConstraints(maxWidth: 320))` |
| `max-w-sm` | `ConstrainedBox(constraints: BoxConstraints(maxWidth: 384))` |
| `max-w-md` | `ConstrainedBox(constraints: BoxConstraints(maxWidth: 448))` |
| `max-w-lg` | `ConstrainedBox(constraints: BoxConstraints(maxWidth: 512))` |
| `max-w-xl` | `ConstrainedBox(constraints: BoxConstraints(maxWidth: 576))` |
| `max-w-2xl` | `ConstrainedBox(constraints: BoxConstraints(maxWidth: 672))` |
| `max-w-3xl` | `ConstrainedBox(constraints: BoxConstraints(maxWidth: 768))` |
| `max-w-4xl` | `ConstrainedBox(constraints: BoxConstraints(maxWidth: 896))` |
| `max-w-5xl` | `ConstrainedBox(constraints: BoxConstraints(maxWidth: 1024))` |
| `max-w-6xl` | `ConstrainedBox(constraints: BoxConstraints(maxWidth: 1152))` |
| `max-w-7xl` | `ConstrainedBox(constraints: BoxConstraints(maxWidth: 1280))` |
| `w-fit` | `MainAxisSize.min` (кнопка НЕ растягивается на всю ширину `double.infinity`, если в Svelte нет `w-full` / `flex-1`) |

### 3. Сетки и адаптивные брейкпоинты
| Брейкпоинт | Мин. ширина | Значение во Flutter |
| :--- | :--- | :--- |
| `sm` | 640px | `constraints.maxWidth >= 640` |
| `md` | 768px | `constraints.maxWidth >= 768` |
| `lg` | 1024px | `constraints.maxWidth >= 1024` |
| `xl` | 1280px | `constraints.maxWidth >= 1280` |
| `2xl` | 1536px | `constraints.maxWidth >= 1536` |
*Если в Svelte `grid-cols-1 md:grid-cols-2`, в Dart на `>=768px` ровно 2 колонки с тем же `gap`.*

### 4. Типографика (Размеры, вес, leading, tracking)
| Tailwind класс | Размер / Высота строки | FontWeight во Flutter |
| :--- | :--- | :--- |
| `text-[10px]` | `fontSize: 10` | - |
| `text-[11px]` | `fontSize: 11` | - |
| `text-xs` | `fontSize: 12, height: 16/12` | - |
| `text-[13px]` | `fontSize: 13` | - |
| `text-sm` | `fontSize: 14, height: 20/14` | - |
| `text-base` | `fontSize: 16, height: 24/16` | - |
| `text-lg` | `fontSize: 18, height: 28/18` | - |
| `text-xl` | `fontSize: 20, height: 28/20` | - |
| `text-2xl` | `fontSize: 24, height: 32/24` | - |
| `text-3xl` | `fontSize: 30, height: 36/30` | - |
| `font-normal` | - | `FontWeight.w400` |
| `font-medium` | - | `FontWeight.w500` |
| `font-semibold` | - | `FontWeight.w600` |
| `font-bold` | - | `FontWeight.w700` |
| `font-extrabold` | - | `FontWeight.w800` |
| `tracking-tight` | `letterSpacing: -0.025 * fontSize` | - |
| `tracking-wide` | `letterSpacing: 0.025 * fontSize` | - |
| `tracking-wider` | `letterSpacing: 0.05 * fontSize` | - |
| `tracking-widest` | `letterSpacing: 0.1 * fontSize` | - |

### 5. Скругления (Border Radius)
| Tailwind класс | Значение во Flutter |
| :--- | :--- |
| `rounded-none` | `BorderRadius.zero` |
| `rounded-sm` | `BorderRadius.circular(2)` |
| `rounded` | `BorderRadius.circular(4)` |
| `rounded-md` | `BorderRadius.circular(6)` |
| `rounded-lg` | `BorderRadius.circular(8)` |
| `rounded-xl` | `BorderRadius.circular(12)` |
| `rounded-2xl` | `BorderRadius.circular(16)` |
| `rounded-3xl` | `BorderRadius.circular(24)` |
| `rounded-full` | `BorderRadius.circular(9999)` |

### 6. Цвета и палитра (Tokens & App CSS)
* **Поверхности:**
  * Canvas: `#0d0f14`
  * Surface: `#12151c`
  * Card: `#151a26` (Hover: `#1a1e28`)
  * Elevated: `#171b24`
  * Overlay: `#181b24`
  * Panel: `#1a1e28`
  * Modal: `#181b24`
* **Границы:**
  * Subtle: `rgba(255, 255, 255, 0.06)`
  * Strong: `rgba(255, 255, 255, 0.14)`
* **Текст:**
  * Ink / Primary: `#f3f4f6`
  * Secondary / Dim: `#d1d5db`
  * Muted: `#9ca3af`
* **Акцент:**
  * Base: `#473bb8` (Hover: `#3d32a0`)
  * Bright: `#5446cf` (Hover: `#5f52b8`)
  * Soft: `#a5b4fc`
* **Статусы:**
  * Success: `#228b57` (Soft: `#86efac`, Surface: `#0f241d`)
  * Warning: `#b87c14` (Text: `#fcd34d`, Surface: `#281e0e`)
  * Danger: `#b92b42` (Text: `#fda4af`, Soft: `rgba(185, 43, 66, 0.12)`, Surface: `#2b1016`)
* **Фирменные цвета источников (Бренды! ЗАПРЕЩЕНО заменять на фиолетовый):**
  * MangaLib / SocialLib: Accent `#c25e2e`, Dim `rgba(194, 94, 46, 0.75)`, Border `rgba(194, 94, 46, 0.25)`, Surface `rgba(194, 94, 46, 0.08)`, Text `#e89a74`
  * TMDB: Accent `#90cea1`, Border `rgba(144, 206, 161, 0.2)`, Surface `rgba(144, 206, 161, 0.05)`, Text `#bbf7d0`
  * RAWG: Accent `#f87171`, Border `rgba(248, 113, 113, 0.2)`, Surface `rgba(248, 113, 113, 0.05)`, Text `#fca5a5`
  * Simkl: Accent `#94b447`, Border `rgba(148, 180, 71, 0.22)`, Surface `rgba(148, 180, 71, 0.06)`, Text `#c8dc8f`
  * Kinopoisk: Accent `#c79438`, Border `rgba(199, 148, 56, 0.22)`, Surface `rgba(199, 148, 56, 0.06)`, Text `#fcd34d`
  * IMDb: Accent `#cfa63e`, Border `rgba(207, 166, 62, 0.22)`, Surface `rgba(207, 166, 62, 0.06)`, Text `#fde68a`
  * Kitsu: Accent `#e0646c`, Border `rgba(224, 100, 108, 0.22)`, Surface `rgba(224, 100, 108, 0.06)`, Text `#fda4af`
  * MangaDex: Accent `#c9603f`, Border `rgba(201, 96, 63, 0.22)`, Surface `rgba(201, 96, 63, 0.06)`, Text `#e8a28c`
  * MangaUpdates: Accent `#a78bfa`, Border `rgba(167, 139, 250, 0.2)`, Surface `rgba(167, 139, 250, 0.05)`, Text `#c4b5fd`
  * OpenLibrary: Accent `#d6a858`, Border `rgba(214, 168, 88, 0.2)`, Surface `rgba(214, 168, 88, 0.05)`, Text `#fde68a`
  * Letterboxd: Accent `#228b57`, Border `rgba(34, 139, 87, 0.25)`, Surface `rgba(34, 139, 87, 0.08)`, Text `#72d59e`
  * Goodreads: Accent `#d6a858`, Border `rgba(214, 168, 88, 0.2)`, Surface `rgba(214, 168, 88, 0.05)`, Text `#fde68a`
  * Steam: Accent `#66c0f4`, Border `rgba(102, 192, 244, 0.2)`, Surface `rgba(102, 192, 244, 0.05)`, Text `#bae6fd`
  * AniList: Accent `#3d8fc9`, Border `rgba(61, 143, 201, 0.22)`, Surface `rgba(61, 143, 201, 0.06)`, Text `#7dd3fc`
  * Shikimori & MAL: Accent `#688ce4`, Border `rgba(104, 140, 228, 0.2)`, Surface `rgba(104, 140, 228, 0.05)`, Text `#c7d2fe`
  * Custom / Universal: Accent `#473bb8`, Border `rgba(71, 59, 184, 0.2)`, Surface `rgba(88, 68, 224, 0.05)`, Text `#a5b4fc`
  * Anixart: Accent `#9a68d0`, Border `rgba(154, 104, 208, 0.25)`, Surface `rgba(154, 104, 208, 0.08)`, Text `#c9a8ec`
* **Бейджи источников (Source Badges):**
  * AniList: `#02a9ff` (Surface `0.15`, Border `0.3`)
  * SocialLib: `#ec4899` (Surface `0.15`, Border `0.3`, Text `#f472b6`)
  * Shikimori: `#2e51a2` (Surface `0.2`, Border `0.4`, Text `#688ce4`)
  * MAL: Text `#60a5fa`
  * MangaDex: `#ff6740` (Surface `0.15`, Border `0.3`)
  * MangaUpdates: `#3b82f6` (Surface `0.2`, Border `0.3`)
  * TMDB: `#01b4e4` (Surface `0.15`, Border `0.3`)
  * Kitsu: `#fd755c` (Surface `0.15`, Border `0.3`, Text `#fb923c`)
  * IGDB: `#9146ff` (Surface `0.2`, Border `0.4`, Text `#a855f7`)

### 7. Правило единых отступов каркаса
* `AppShell.svelte`: основной контейнер `<main id="main-scroll" class="flex-1 overflow-y-auto px-4 py-4 md:px-8 md:py-6">`.
* Если страница имеет собственный full-width layout (например `SettingsView`), она компенсирует отступы или `AppShell` предоставляет специальный режим без паддингов, чтобы в Settings не пропадали отступы справа/сверху, а на `Stats/Lists/History/Calendar/Goals` отступы не удваивались!

### 8. Запрет отсебятины
* Если в `.svelte` нет тултипа (`title=` / tooltip), хинта, лишней рамки или иконки — **удалить** их из `.dart`. Никаких лишних рамок или несогласованных тултипов!

---

## 📊 Матрица паритета стилей и верстки (Таблица аудита 1:1)

| Фаза | Svelte-файл | Dart-файл | Статус | Выявленные отличия CSS/Layout | Исправлено |
| :--- | :--- | :--- | :--- | :--- | :--- |
| S0 | `mediatracker-ui/src/app/tokens.css` | `tsundoku-flutter/lib/shared/theme/tsundoku_tokens.dart` | ✅ Сверен 1:1 | Все семантические токены, бренды источников (--color-import-*), бейджи (--color-badge-*), чарты и поверхности идентичны 1-в-1 | 0 отличий |
| S0 | `mediatracker-ui/src/app/app.css` | `tsundoku-flutter/lib/shared/theme/tsundoku_theme.dart` | ✅ Сверен 1:1 | Все статические переменные @theme static, радиусы, скроллбар, анимации и ThemeData соответствуют app.css 1-в-1 | 0 отличий |
| S1 | `mediatracker-ui/src/shared/ui/Button.svelte` | `tsundoku-flutter/lib/shared/ui/button.dart` | ✅ Сверен 1:1 | Добавлены рамки border-subtle для secondary и border-strong для outline; исправлен паддинг iconOnly на p-0 с квадратным размером | Да |
| S1 | `mediatracker-ui/src/shared/ui/Badge.svelte` | `tsundoku-flutter/lib/shared/ui/badge.dart` | ✅ Сверен 1:1 | Все размеры, padding (px-1.5/px-2, py-0.5), rounded-md (6px), шрифты 10/12px и тоны совпадают 1-в-1 | 0 отличий |
| S1 | `mediatracker-ui/src/shared/ui/Panel.svelte` | `tsundoku-flutter/lib/shared/ui/panel.dart` | ✅ Сверен 1:1 | rounded-xl (12px), border-subtle, bg-surface, p-4 (16px), shadow-md совпадают 1-в-1 | 0 отличий |
| S1 | `mediatracker-ui/src/shared/ui/Modal.svelte` | `tsundoku-flutter/lib/shared/ui/modal.dart` | ✅ Сверен 1:1 | Добавлена тень shadow-2xl shadow-black/60 (elevation+shadowColor), добавлен contentPadding; размеры md/lg/xl/search/jobs и backdrop #090b10/80 выверены 1-в-1 | Да |
| S1 | `mediatracker-ui/src/shared/ui/ConfirmModal.svelte` | `tsundoku-flutter/lib/shared/ui/confirm_modal.dart` | ✅ Сверен 1:1 | Устранён двойной отступ через contentPadding: EdgeInsets.zero; p-6 (24px), цвета и размеры кнопок/чекбоксов 1-в-1 | Да |
| S1 | `mediatracker-ui/src/shared/ui/PopoverMenu.svelte` | `tsundoku-flutter/lib/shared/ui/popover_menu.dart` | ✅ Сверен 1:1 | Исправлен размер шрифта опций на 14px (text-sm), паддинг на py-2 (8px), rounded-sm (2px); фон #1c202b, border-white/10, shadow-2xl выверены 1-в-1 | Да |
| S1 | `mediatracker-ui/src/shared/ui/Select.svelte` | `tsundoku-flutter/lib/shared/ui/popover_menu.dart` | ✅ Сверен 1:1 | Исправлен border-radius на 8px (rounded-lg), цвет текста #f3f4f6 (text-ink); h-10 (40px), px-3 (12px), ChevronDown 14px text-muted 1-в-1 | Да |
| S1 | `mediatracker-ui/src/shared/ui/ContextMenu.svelte` | `tsundoku-flutter/lib/shared/ui/context_menu.dart` | ✅ Сверен 1:1 | Фон #181b24, radius 12px, p-1.5 (6px), item padding 7x10px, font 13px, иконки 15px, цвета danger/hover совпадают 1-в-1 | 0 отличий |
| S1 | `mediatracker-ui/src/widgets/layout/ToastContainer.svelte` | `tsundoku-flutter/lib/widgets/layout/toast_container.dart` | ✅ Сверен 1:1 | Позиция bottom-right, gap 10px, карточки p-3 (12px), rounded-xl (12px), цвета бейджей/полос, кнопки size-7 (28px) выверены 1-в-1 | 0 отличий |
| S1 | `mediatracker-ui/src/shared/ui/ImageLightbox.svelte` | `tsundoku-flutter/lib/shared/ui/image_lightbox.dart` | ✅ Сверен 1:1 | Добавлены rounded-lg (8px), border-white/20, shadow-2xl на изображение, динамический max-h-[85dvh], rounded-lg на кнопку закрытия 1-в-1 | Да |
| S1 | `mediatracker-ui/src/shared/ui/TotalBadge.svelte` | `tsundoku-flutter/lib/shared/ui/total_badge.dart` | ✅ Сверен 1:1 | Plain counter, text-xs (12px), text-white/50, tabular-nums совпадают 1-в-1 | 0 отличий |
| S1 | `mediatracker-ui/src/shared/ui/MediaCoverPlaceholder.svelte` | `tsundoku-flutter/lib/shared/ui/media_cover_placeholder.dart` | ✅ Сверен 1:1 | Градиент #12151c->#1a1e28, opacity 0.9, оверлей black/85->40, p-2 (8px), font 10px w600 совпадают 1-в-1 | 0 отличий |
| S2 | `mediatracker-ui/src/widgets/layout/AppShell.svelte` | `tsundoku-flutter/lib/widgets/layout/app_shell.dart` | ✅ Сверен 1:1 | lg=1024px, sidebar w-60 (240px) px-3 py-5, header h-14 (56px), main p-6 (24px) / noPadding p-0, borders white/0.07 1-в-1 | 0 отличий |
| S2 | `mediatracker-ui/src/widgets/layout/Header.svelte` | `tsundoku-flutter/lib/widgets/layout/header.dart` | ✅ Сверен 1:1 | Паддинг выровнен под px-4 sm:px-6 lg:px-8 (16/24/32px); заголовок w-56, поиск 448/512px, Ctrl K, язык w-88px 1-в-1 | Да |
| S2 | `mediatracker-ui/src/widgets/layout/Sidebar.svelte` | `tsundoku-flutter/lib/widgets/layout/sidebar.dart` | ✅ Сверен 1:1 | Brand px-3 pb-7 (28px), h-10 (40px), active #a5b4fc, gap 12px, tools border-t pt-4, mobile flyout выверены 1-в-1 | 0 отличий |
| S2 | `mediatracker-ui/src/features/filter-and-sort/FilterBar.svelte` | `tsundoku-flutter/lib/features/filter-and-sort/filter_bar.dart` | ✅ Сверен 1:1 | Высота кнопок и инпута h-10 (40px, size=lg), rounded-lg (8px), search 18px text-sm (14px), padding 12/16px, rounded-full бейдж | Да |
| S2 | `mediatracker-ui/src/widgets/layout/ActivityDropdown.svelte` | `tsundoku-flutter/lib/widgets/layout/activity_dropdown.dart` | ✅ Сверен 1:1 | Trigger 36x36px, popover 320/384px, bg #181b24, p-3 (12px), бейджи active/pending, лимиты API 1-в-1 | 0 отличий |
| S2 | `mediatracker-ui/src/widgets/layout/BackgroundJobsModal.svelte` | `tsundoku-flutter/lib/widgets/layout/background_jobs_modal.dart` | ✅ Сверен 1:1 | Размер jobs (88vh, 92vw, max 1600px), full-bleed шапка через contentPadding: zero, табы, master-detail 1-в-1 | Да |
| S2 | `mediatracker-ui/src/widgets/layout/CloseAppModal.svelte` | `tsundoku-flutter/lib/widgets/layout/close_app_modal.dart` | ✅ Сверен 1:1 | Backdrop #090b10/80, max-w-md (448px), bg #151a26/95, p-5 (20px), опции p-3.5 (14px), кнопки px-4 py-2 1-в-1 | 0 отличий |
| S3 | `mediatracker-ui/src/entities/media/ui/MediaPoster.svelte` | `tsundoku-flutter/lib/entities/media/ui/media_poster.dart` | ✅ Сверен 1:1 | Object-cover, Placeholder404, syncing black/80 22px, needsReview amber-500/90 10px, badges/actions p-2.5 1-в-1 | 0 отличий |
| S3 | `mediatracker-ui/src/entities/media/ui/MediaScoreBadge.svelte` | `tsundoku-flutter/lib/entities/media/ui/media_score_badge.dart` | ✅ Сверен 1:1 | Круг 37.28px (2.33rem), -ml-2 (-8px), bg #4a63c9, font-black 17px, tabular-nums, shadow-lg 1-в-1 | 0 отличий |
| S3 | `mediatracker-ui/src/entities/media/ui/MediaStatusBadge.svelte` | `tsundoku-flutter/lib/entities/media/ui/media_status_badge.dart` | ✅ Сверен 1:1 | Круг 37.28px (2.33rem), statusBadgeClasses цвета, Lucide иконки, ring-indigo-400/70 при открытии, hover:brightness-125 1-в-1 | 0 отличий |
| S3 | `mediatracker-ui/src/entities/media/ui/Placeholder404.svelte` | `tsundoku-flutter/lib/entities/media/ui/placeholder404.dart` | ✅ Сверен 1:1 | 1:1 проброс в MediaCoverPlaceholder с опциональным label | 0 отличий |
| S3 | `mediatracker-ui/src/widgets/media-card/BaseCard.svelte` | `tsundoku-flutter/lib/widgets/media-card/base_card.dart` | ✅ Сверен 1:1 | aspect-[2/3], rounded-xl, border-white/5, hover:border-white/10, shadow-lg, focus-within:ring-2 indigo-500/30, градиент inset-x-0 bottom-0 px-3 pt-16 pb-3, убран лишний padding с hover 1-в-1 | Да |
| S3 | `mediatracker-ui/src/widgets/media-card/CardTitleBlock.svelte` | `tsundoku-flutter/lib/widgets/media-card/card_title_block.dart` | ✅ Сверен 1:1 | line-clamp-2, text-sm (14px), font-semibold, leading-tight, drop-shadow-sm, mt-0.5 (2px), text-xs (12px) text-white/60 1-в-1 | 0 отличий |
| S3 | `mediatracker-ui/src/widgets/media-card/CardProgressControls.svelte` | `tsundoku-flutter/lib/widgets/media-card/card_progress_controls.dart` | ✅ Сверен 1:1 | gap-1.5 (6px), кнопки h-7 w-7 (28px), rounded-md (6px), border-white/10, bg-[#1a202c]/90, text-xs tabular-nums 1-в-1 | Да |
| S3 | `mediatracker-ui/src/widgets/media-card/MediaCard.svelte` | `tsundoku-flutter/lib/widgets/media-card/media_card.dart` | ✅ Сверен 1:1 | 1:1 роутер карточек по MediaType (Game, Book, Manga, Movie, TvShow) | 0 отличий |
| S3 | `mediatracker-ui/src/widgets/media-card/BookCard.svelte` | `tsundoku-flutter/lib/widgets/media-card/book_card.dart` | ✅ Сверен 1:1 | BaseCard, подзаголовок (автор/ранобэ/книга), hover-степпер CardProgressControls 1-в-1 | 0 отличий |
| S3 | `mediatracker-ui/src/widgets/media-card/GameCard.svelte` | `tsundoku-flutter/lib/widgets/media-card/game_card.dart` | ✅ Сверен 1:1 | BaseCard, подзаголовок (userPlatform/platform/game), hover-степпер часов CardProgressControls 1-в-1 | 0 отличий |
| S3 | `mediatracker-ui/src/widgets/media-card/MangaCard.svelte` | `tsundoku-flutter/lib/widgets/media-card/manga_card.dart` | ✅ Сверен 1:1 | BaseCard, подзаголовок (автор/mangaFormat/manga), hover-степпер глав CardProgressControls 1-в-1 | 0 отличий |
| S3 | `mediatracker-ui/src/widgets/media-card/MovieCard.svelte` | `tsundoku-flutter/lib/widgets/media-card/movie_card.dart` | ✅ Сверен 1:1 | BaseCard, подзаголовок (режиссёр/фильм), hover-степпер 0/1 переключения completed CardProgressControls 1-в-1 | 0 отличий |
| S3 | `mediatracker-ui/src/widgets/media-card/TvShowCard.svelte` | `tsundoku-flutter/lib/widgets/media-card/tv_show_card.dart` | ✅ Сверен 1:1 | BaseCard, подзаголовок (тип • сезоны), hover: CardProgressControls или MediaStatusBadge 1-в-1 | 0 отличий |
| S3 | `mediatracker-ui/src/widgets/media-grid/MediaGrid.svelte` | `tsundoku-flutter/lib/widgets/media-grid/media_grid.dart` | ✅ Сверен 1:1 | Брейкпоинты колонок 2..6 (640/1024/1280/1536), rowGap 16px (gap-4), loading 240px, error/empty min-h-72 (288px), remove button 32px 1-в-1 | 0 отличий |
| S3 | `mediatracker-ui/src/widgets/media-grid/SectionRow.svelte` | `tsundoku-flutter/lib/widgets/media-grid/section_row.dart` | ✅ Сверен 1:1 | Заголовок 25px bold tracking-wide, счётчик px-2.5 py-0.5 rounded-full, space-y-3 (12px) 1-в-1 | 0 отличий |
| S4 | `mediatracker-ui/src/features/settings/SettingsModal.svelte` | `tsundoku-flutter/lib/features/settings/settings_modal.dart` | ✅ Сверен 1:1 | Full-bleed модалка (ModalSize.xl, contentPadding: zero), header px-6 py-4, TsundokuButton.ghost close button, 10 табов 1-в-1 | Да |
| S4 | `mediatracker-ui/src/features/settings/FirstRunStorageModal.svelte` | `tsundoku-flutter/lib/features/settings/first_run_storage_modal.dart` | ✅ Сверен 1:1 | ModalSize.md, убран двойной padding через contentPadding: zero (p-6 24px), опции p-3.5, h-9 bg-indigo-600 px-5 button 1-в-1 | Да |
| S4 | `mediatracker-ui/src/features/import-media/ImportModal.svelte` | `tsundoku-flutter/lib/features/import-media/import_modal.dart` | ✅ Сверен 1:1 | ModalSize.xl, убран двойной padding через contentPadding: zero (p-6 24px), in-only fade, ImportPanel integration 1-в-1 | Да |
| S4 | `mediatracker-ui/src/features/import-media/ImportPanel.svelte` | `tsundoku-flutter/lib/features/import-media/import_panel.dart` | ✅ Сверен 1:1 | Сетка провайдеров grid-cols-1 sm:2 lg:4 (gap-2.5 10px, mainAxisExtent 70px), p-3 rounded-xl border, icon 40x40 rounded-lg, 1:1 токены брендовых цветов sourceTheme, MangaLib сетки 5 сайтов (grid-cols-2 sm:3) и 6 папок (grid-cols-2 sm:3), space-y-6 (24px) вертикальный ритм, custom accordion (JSON/CSV snippet), убран лишний folderInput в шапке 1-в-1 | Да |
| S4 | `mediatracker-ui/src/features/search-external/SearchModal.svelte` | `tsundoku-flutter/lib/features/search-external/search_modal.dart` | В очереди |  |  |
| S4 | `mediatracker-ui/src/features/edit-media/EditMediaWorkspace.svelte` | `tsundoku-flutter/lib/features/edit-media/edit_media_workspace.dart` | В очереди |  |  |
| S4 | `mediatracker-ui/src/features/edit-media/WorkspaceWindow.svelte` | `tsundoku-flutter/lib/features/edit-media/workspace_window.dart` | В очереди |  |  |
| S4 | `mediatracker-ui/src/features/edit-media/modules/ModuleCard.svelte` | `tsundoku-flutter/lib/features/edit-media/module_card.dart` | В очереди |  |  |
| S4 | `mediatracker-ui/src/features/edit-media/modules/BaseMediaModule.svelte` | `tsundoku-flutter/lib/features/edit-media/base_media_module.dart` | В очереди |  |  |
| S4 | `mediatracker-ui/src/features/edit-media/modules/CategoryFieldsModule.svelte` | `tsundoku-flutter/lib/features/edit-media/category_fields_module.dart` | В очереди |  |  |
| S4 | `mediatracker-ui/src/features/edit-media/modules/AltTitlesModule.svelte` | `tsundoku-flutter/lib/features/edit-media/alt_titles_module.dart` | В очереди |  |  |
| S4 | `mediatracker-ui/src/features/edit-media/modules/ImagesModule.svelte` | `tsundoku-flutter/lib/features/edit-media/images_module.dart` | В очереди |  |  |
| S4 | `mediatracker-ui/src/features/edit-media/modules/NotesModule.svelte` | `tsundoku-flutter/lib/features/edit-media/notes_module.dart` | В очереди |  |  |
| S4 | `mediatracker-ui/src/features/edit-media/modules/QuotesModule.svelte` | `tsundoku-flutter/lib/features/edit-media/quotes_module.dart` | В очереди |  |  |
| S4 | `mediatracker-ui/src/features/create-media/CreateModal.svelte` | `tsundoku-flutter/lib/features/create-media/create_modal.dart` | В очереди |  |  |
| S4 | `mediatracker-ui/src/features/create-media/FormField.svelte` | `tsundoku-flutter/lib/features/create-media/form_field.dart` | В очереди |  |  |
| S4 | `mediatracker-ui/src/features/create-media/BookFormFields.svelte` | `tsundoku-flutter/lib/features/create-media/book_form_fields.dart` | В очереди |  |  |
| S4 | `mediatracker-ui/src/features/create-media/GameFormFields.svelte` | `tsundoku-flutter/lib/features/create-media/game_form_fields.dart` | В очереди |  |  |
| S4 | `mediatracker-ui/src/features/create-media/MangaFormFields.svelte` | `tsundoku-flutter/lib/features/create-media/manga_form_fields.dart` | В очереди |  |  |
| S4 | `mediatracker-ui/src/features/create-media/MovieFormFields.svelte` | `tsundoku-flutter/lib/features/create-media/movie_form_fields.dart` | В очереди |  |  |
| S4 | `mediatracker-ui/src/features/create-media/TvShowFormFields.svelte` | `tsundoku-flutter/lib/features/create-media/tvshow_form_fields.dart` | В очереди |  |  |
| S4 | `mediatracker-ui/src/features/drop-reason/DropReasonModal.svelte` | `tsundoku-flutter/lib/features/drop-reason/drop_reason_modal.dart` | В очереди |  |  |
| S4 | `mediatracker-ui/src/features/goals/CreateGoalModal.svelte` | `tsundoku-flutter/lib/features/goals/create_goal_modal.dart` | В очереди |  |  |
| S4 | `mediatracker-ui/src/features/lists/CreateListModal.svelte` | `tsundoku-flutter/lib/features/lists/create_list_modal.dart` | В очереди |  |  |
| S4 | `mediatracker-ui/src/features/lists/ListPicker.svelte` | `tsundoku-flutter/lib/features/lists/list_picker.dart` | В очереди |  |  |
| S4 | `mediatracker-ui/src/features/lists/SmartListBuilder.svelte` | `tsundoku-flutter/lib/features/lists/smart_list_builder.dart` | В очереди |  |  |
| S4 | `mediatracker-ui/src/features/stale-triage/StaleBacklogModal.svelte` | `tsundoku-flutter/lib/features/stale-triage/stale_backlog_modal.dart` | В очереди |  |  |
| S5 | `mediatracker-ui/src/widgets/media-detail/DetailHeader.svelte` | `tsundoku-flutter/lib/widgets/media-detail/detail_header.dart` | В очереди |  |  |
| S5 | `mediatracker-ui/src/widgets/media-detail/DetailSidebar.svelte` | `tsundoku-flutter/lib/widgets/media-detail/detail_sidebar.dart` | В очереди |  |  |
| S5 | `mediatracker-ui/src/widgets/media-detail/DetailTabs.svelte` | `tsundoku-flutter/lib/widgets/media-detail/detail_tabs.dart` | В очереди |  |  |
| S5 | `mediatracker-ui/src/widgets/media-detail/ProgressStepper.svelte` | `tsundoku-flutter/lib/widgets/media-detail/progress_stepper.dart` | В очереди |  |  |
| S5 | `mediatracker-ui/src/widgets/media-detail/SeasonRow.svelte` | `tsundoku-flutter/lib/widgets/media-detail/season_row.dart` | В очереди |  |  |
| S5 | `mediatracker-ui/src/widgets/media-detail/RelationLoadButton.svelte` | `tsundoku-flutter/lib/widgets/media-detail/relation_load_button.dart` | В очереди |  |  |
| S5 | `mediatracker-ui/src/widgets/media-detail/SyncRowsSkeleton.svelte` | `tsundoku-flutter/lib/widgets/media-detail/sync_rows_skeleton.dart` | В очереди |  |  |
| S5 | `mediatracker-ui/src/widgets/media-detail/CoverManagerModal.svelte` | `tsundoku-flutter/lib/widgets/media-detail/cover_manager_modal.dart` | В очереди |  |  |
| S5 | `mediatracker-ui/src/widgets/media-detail/ExternalDetailModal.svelte` | `tsundoku-flutter/lib/widgets/media-detail/external_detail_modal.dart` | В очереди |  |  |
| S5 | `mediatracker-ui/src/widgets/media-detail/FillMissingModal.svelte` | `tsundoku-flutter/lib/widgets/media-detail/fill_missing_modal.dart` | В очереди |  |  |
| S5 | `mediatracker-ui/src/widgets/media-detail/MediaActivityModal.svelte` | `tsundoku-flutter/lib/widgets/media-detail/media_activity_modal.dart` | В очереди |  |  |
| S5 | `mediatracker-ui/src/widgets/media-detail/OverwriteConfirmModal.svelte` | `tsundoku-flutter/lib/widgets/media-detail/overwrite_confirm_modal.dart` | В очереди |  |  |
| S5 | `mediatracker-ui/src/widgets/media-detail/RelinkSourceModal.svelte` | `tsundoku-flutter/lib/widgets/media-detail/relink_source_modal.dart` | В очереди |  |  |
| S5 | `mediatracker-ui/src/widgets/media-detail/panels/RelatedPanel.svelte` | `tsundoku-flutter/lib/widgets/media-detail/panels/related_panel.dart` | В очереди |  |  |
| S5 | `mediatracker-ui/src/widgets/media-detail/panels/RelatedPreviewModal.svelte` | `tsundoku-flutter/lib/widgets/media-detail/panels/related_preview_modal.dart` | В очереди |  |  |
| S5 | `mediatracker-ui/src/widgets/media-detail/sections/ProgressCard.svelte` | `tsundoku-flutter/lib/widgets/media-detail/sections/progress_card.dart` | В очереди |  |  |
| S5 | `mediatracker-ui/src/widgets/media-detail/sections/PeopleSizeToggle.svelte` | `tsundoku-flutter/lib/widgets/media-detail/sections/people_size_toggle.dart` | В очереди |  |  |
| S5 | `mediatracker-ui/src/widgets/media-detail/sections/BookProgressSection.svelte` | `tsundoku-flutter/lib/widgets/media-detail/sections/book_progress_section.dart` | В очереди |  |  |
| S5 | `mediatracker-ui/src/widgets/media-detail/sections/BookEditionSection.svelte` | `tsundoku-flutter/lib/widgets/media-detail/sections/book_edition_section.dart` | В очереди |  |  |
| S5 | `mediatracker-ui/src/widgets/media-detail/sections/CastSection.svelte` | `tsundoku-flutter/lib/widgets/media-detail/sections/cast_section.dart` | В очереди |  |  |
| S5 | `mediatracker-ui/src/widgets/media-detail/sections/CreatorSection.svelte` | `tsundoku-flutter/lib/widgets/media-detail/sections/creator_section.dart` | В очереди |  |  |
| S5 | `mediatracker-ui/src/widgets/media-detail/sections/GameDetailSection.svelte` | `tsundoku-flutter/lib/widgets/media-detail/sections/game_detail_section.dart` | В очереди |  |  |
| S5 | `mediatracker-ui/src/widgets/media-detail/sections/LinkedSourcesSection.svelte` | `tsundoku-flutter/lib/widgets/media-detail/sections/linked_sources_section.dart` | В очереди |  |  |
| S5 | `mediatracker-ui/src/widgets/media-detail/sections/MangaProgressSection.svelte` | `tsundoku-flutter/lib/widgets/media-detail/sections/manga_progress_section.dart` | В очереди |  |  |
| S5 | `mediatracker-ui/src/widgets/media-detail/sections/MediaFilesSection.svelte` | `tsundoku-flutter/lib/widgets/media-detail/sections/media_files_section.dart` | В очереди |  |  |
| S5 | `mediatracker-ui/src/widgets/media-detail/sections/MovieStatusSection.svelte` | `tsundoku-flutter/lib/widgets/media-detail/sections/movie_status_section.dart` | В очереди |  |  |
| S5 | `mediatracker-ui/src/widgets/media-detail/sections/NotesSection.svelte` | `tsundoku-flutter/lib/widgets/media-detail/sections/notes_section.dart` | В очереди |  |  |
| S5 | `mediatracker-ui/src/widgets/media-detail/sections/QuickFactsSection.svelte` | `tsundoku-flutter/lib/widgets/media-detail/sections/quick_facts_section.dart` | В очереди |  |  |
| S5 | `mediatracker-ui/src/widgets/media-detail/sections/QuotesSection.svelte` | `tsundoku-flutter/lib/widgets/media-detail/sections/quotes_section.dart` | В очереди |  |  |
| S5 | `mediatracker-ui/src/widgets/media-detail/sections/TrailerSection.svelte` | `tsundoku-flutter/lib/widgets/media-detail/sections/trailer_section.dart` | В очереди |  |  |
| S5 | `mediatracker-ui/src/widgets/media-detail/sections/TvShowProgressSection.svelte` | `tsundoku-flutter/lib/widgets/media-detail/sections/tv_show_progress_section.dart` | В очереди |  |  |
| S5 | `mediatracker-ui/src/widgets/media-detail/tabs/OverviewTab.svelte` | `tsundoku-flutter/lib/widgets/media-detail/tabs/overview_tab.dart` | В очереди |  |  |
| S5 | `mediatracker-ui/src/widgets/media-detail/tabs/EpisodesTab.svelte` | `tsundoku-flutter/lib/widgets/media-detail/tabs/episodes_tab.dart` | В очереди |  |  |
| S5 | `mediatracker-ui/src/widgets/media-detail/tabs/GalleryTab.svelte` | `tsundoku-flutter/lib/widgets/media-detail/tabs/gallery_tab.dart` | В очереди |  |  |
| S5 | `mediatracker-ui/src/widgets/media-detail/tabs/RecommendationsTab.svelte` | `tsundoku-flutter/lib/widgets/media-detail/tabs/recommendations_tab.dart` | В очереди |  |  |
| S5 | `mediatracker-ui/src/widgets/media-detail/tabs/RelatedTab.svelte` | `tsundoku-flutter/lib/widgets/media-detail/tabs/related_tab.dart` | В очереди |  |  |
| S5 | `mediatracker-ui/src/widgets/goals/GoalCard.svelte` | `tsundoku-flutter/lib/widgets/goals/goal_card.dart` | В очереди |  |  |
| S5 | `mediatracker-ui/src/widgets/stats/StatsHeroBanner.svelte` | `tsundoku-flutter/lib/widgets/stats/stats_hero_banner.dart` | В очереди |  |  |
| S5 | `mediatracker-ui/src/widgets/stats/ActivityHeatmap.svelte` | `tsundoku-flutter/lib/widgets/stats/activity_heatmap.dart` | В очереди |  |  |
| S5 | `mediatracker-ui/src/widgets/stats/MonthlyActivityChart.svelte` | `tsundoku-flutter/lib/widgets/stats/monthly_activity_chart.dart` | В очереди |  |  |
| S5 | `mediatracker-ui/src/widgets/stats/RatingPsychology.svelte` | `tsundoku-flutter/lib/widgets/stats/rating_psychology.dart` | В очереди |  |  |
| S5 | `mediatracker-ui/src/widgets/stats/TimeDistributionDonut.svelte` | `tsundoku-flutter/lib/widgets/stats/time_distribution_donut.dart` | В очереди |  |  |
| S5 | `mediatracker-ui/src/widgets/stats/TopGenresBar.svelte` | `tsundoku-flutter/lib/widgets/stats/top_genres_bar.dart` | В очереди |  |  |
| S5 | `mediatracker-ui/src/widgets/stats/TrackerBadges.svelte` | `tsundoku-flutter/lib/widgets/stats/tracker_badges.dart` | В очереди |  |  |
| S5 | `mediatracker-ui/src/widgets/stats/BacklogHealth.svelte` | `tsundoku-flutter/lib/widgets/stats/backlog_health.dart` | В очереди |  |  |
| S5 | `mediatracker-ui/src/widgets/stats/taste-profile/GenreRadarChart.svelte` | `tsundoku-flutter/lib/widgets/stats/taste-profile/genre_radar_chart.dart` | В очереди |  |  |
| S5 | `mediatracker-ui/src/widgets/stats/taste-profile/EraAffinityCard.svelte` | `tsundoku-flutter/lib/widgets/stats/taste-profile/era_affinity_card.dart` | В очереди |  |  |
| S5 | `mediatracker-ui/src/widgets/stats/taste-profile/GenreParadoxCard.svelte` | `tsundoku-flutter/lib/widgets/stats/taste-profile/genre_paradox_card.dart` | В очереди |  |  |
| S5 | `mediatracker-ui/src/widgets/stats/taste-profile/CriticalDivergenceCard.svelte` | `tsundoku-flutter/lib/widgets/stats/taste-profile/critical_divergence_card.dart` | В очереди |  |  |
| S5 | `mediatracker-ui/src/widgets/stats/taste-profile/DropAnalyticsCard.svelte` | `tsundoku-flutter/lib/widgets/stats/taste-profile/drop_analytics_card.dart` | В очереди |  |  |
| S5 | `mediatracker-ui/src/widgets/stats/taste-profile/SunkCostCard.svelte` | `tsundoku-flutter/lib/widgets/stats/taste-profile/sunk_cost_card.dart` | В очереди |  |  |
| S5 | `mediatracker-ui/src/widgets/stats/taste-profile/TastePersonaCard.svelte` | `tsundoku-flutter/lib/widgets/stats/taste-profile/taste_persona_card.dart` | В очереди |  |  |
| S6 | `mediatracker-ui/src/app/App.svelte` | `tsundoku-flutter/lib/app/app.dart` | В очереди |  |  |
| S6 | `mediatracker-ui/src/views/HomeView.svelte` | `tsundoku-flutter/lib/views/home_view.dart` | В очереди |  |  |
| S6 | `mediatracker-ui/src/views/CategoryView.svelte` | `tsundoku-flutter/lib/views/category_view.dart` | В очереди |  |  |
| S6 | `mediatracker-ui/src/views/MediaDetailView.svelte` | `tsundoku-flutter/lib/views/media_detail_view.dart` | В очереди |  |  |
| S6 | `mediatracker-ui/src/views/ShowSeasonsView.svelte` | `tsundoku-flutter/lib/views/show_seasons_view.dart` | В очереди |  |  |
| S6 | `mediatracker-ui/src/views/StatsView.svelte` | `tsundoku-flutter/lib/views/stats_view.dart` | В очереди |  |  |
| S6 | `mediatracker-ui/src/views/ListsView.svelte` | `tsundoku-flutter/lib/views/lists_view.dart` | В очереди |  |  |
| S6 | `mediatracker-ui/src/views/HistoryView.svelte` | `tsundoku-flutter/lib/views/history_view.dart` | В очереди |  |  |
| S6 | `mediatracker-ui/src/views/CalendarView.svelte` | `tsundoku-flutter/lib/views/calendar_view.dart` | В очереди |  |  |
| S6 | `mediatracker-ui/src/views/GoalsView.svelte` | `tsundoku-flutter/lib/views/goals_view.dart` | В очереди |  |  |
| S6 | `mediatracker-ui/src/views/SettingsView.svelte` | `tsundoku-flutter/lib/views/settings_view.dart` | В очереди |  |  |
