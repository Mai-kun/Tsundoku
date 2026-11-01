<script module lang="ts">
  import type { LibrarySort } from "$features/filter-and-sort/FilterBar.svelte";
  import { createSwrCache } from "$shared/utils/swrCache";

  interface HomePayload {
    inProgress: MediaItem[];
    upNext: MediaItem[];
    recentlyCompleted: MediaItem[];
  }

  const HOME_KEY = "home";
  const homeCache = createSwrCache<HomePayload>();
</script>

<script lang="ts">
  import {
    ArrowUp,
    CalendarDays,
    ChevronDown,
    Clock3,
    Dices,
    History,
    Layers,
    LayoutGrid,
    ListChecks,
    Search,
    SlidersHorizontal,
    Star,
    Type,
  } from "$shared/ui/Icons";
  import { deleteMedia, getMedia, setProgress } from "$shared/api/api";
  import { jobsClient } from "$shared/api/jobsClient.svelte";
  import { showToast } from "$shared/ui/toast.svelte";
  import Select from "$shared/ui/Select.svelte";
  import { i18n } from "$shared/i18n/index.svelte";
  import { MEDIA_STATUS, SYNC_STATUS, type MediaItem, type MediaStatus } from "$shared/types";
  import MediaGrid from "$widgets/media-grid/MediaGrid.svelte";
  import PopoverMenu from "$shared/ui/PopoverMenu.svelte";
  import {
    evaluateTimeFit,
    formatTimeBudgetChip,
    type TimeBudgetMinutes,
    type TimeFitResult,
  } from "$entities/media/model/timeBudget";
  import { uiSettings } from "$shared/utils/uiSettings.svelte";
  import { isStaleInProgress } from "$entities/media/model/staleTriage";

  const timeBudgetOptions = $derived<{ value: TimeBudgetMinutes; label: string }[]>([
    { value: null, label: i18n.t.timeBudget.options.all },
    { value: 15, label: i18n.t.timeBudget.options.m15 },
    { value: 30, label: i18n.t.timeBudget.options.m30 },
    { value: 45, label: i18n.t.timeBudget.options.m45 },
    { value: 60, label: i18n.t.timeBudget.options.h1 },
    { value: 90, label: i18n.t.timeBudget.options.h1_5 },
    { value: 120, label: i18n.t.timeBudget.options.h2_plus },
  ]);

  /** Home-local sort: `updated` leads with last activity; `created` by date added. */
  type HomeSort = "updated" | "created" | "oldest" | "rating" | "title";
  type CategoryFilter = "all" | "game" | "anime" | "manga" | "movie" | "tvshow" | "book";
  type GroupingMode = "status" | "type" | "none";

  const HOME_SORT_ICONS: Record<HomeSort, typeof Star> = {
    updated: History,
    created: CalendarDays,
    oldest: ArrowUp,
    rating: Star,
    title: Type,
  };

  const GROUP_MODE_ICONS: Record<GroupingMode, typeof Layers> = {
    status: ListChecks,
    type: Layers,
    none: LayoutGrid,
  };

  const sortOptions = $derived<{ value: HomeSort; label: string }[]>([
    { value: "updated", label: i18n.t.sort.updated },
    { value: "created", label: i18n.t.sort.created },
    { value: "oldest", label: i18n.t.sort.oldest },
    { value: "rating", label: i18n.t.sort.rating },
    { value: "title", label: i18n.t.sort.title },
  ]);

  const categoryOptions = $derived<{ value: CategoryFilter; label: string }[]>([
    { value: "all", label: i18n.t.home.allCategories },
    { value: "anime", label: i18n.t.navigation.anime },
    { value: "manga", label: i18n.t.navigation.manga },
    { value: "game", label: i18n.t.navigation.game },
    { value: "movie", label: i18n.t.navigation.movie },
    { value: "tvshow", label: i18n.t.navigation.tvshow },
    { value: "book", label: i18n.t.navigation.book },
  ]);

  const groupingOptions = $derived<{ value: GroupingMode; label: string }[]>([
    { value: "status", label: i18n.t.home.groupByStatus },
    { value: "type", label: i18n.t.home.groupByType },
    { value: "none", label: i18n.t.home.groupNone },
  ]);

  interface Props {
    refreshKey: number;
    onOpen: (item: MediaItem) => void;
    onMediaChanged: () => void;
    onEdit?: (item: MediaItem) => void;
  }

  let { refreshKey, onOpen, onMediaChanged, onEdit = () => {} }: Props = $props();

  let inProgress = $state.raw<MediaItem[]>(homeCache.peek(HOME_KEY)?.inProgress ?? []);
  let upNext = $state.raw<MediaItem[]>(homeCache.peek(HOME_KEY)?.upNext ?? []);
  let recentlyCompleted = $state.raw<MediaItem[]>(
    homeCache.peek(HOME_KEY)?.recentlyCompleted ?? [],
  );
  let loading = $state(homeCache.peek(HOME_KEY) === undefined);
  let loadError = $state<unknown>(null);
  // The persisted library value "newest" maps to home's "updated" (both newest-first).
  let sort = $state<HomeSort>(
    uiSettings.sortOption === "newest" ? "updated" : (uiSettings.sortOption as HomeSort),
  );
  let groupByMode = $state<GroupingMode>(uiSettings.groupByType ? "type" : "status");
  let timeBudget = $state<TimeBudgetMinutes>(null);
  let showAll = $state(false);
  let searchQuery = $state("");
  let debouncedSearch = $state("");
  let selectedCategory = $state<CategoryFilter>("all");
  let showStaleModal = $state(false);
  const staleCount = $derived(inProgress.filter((item) => isStaleInProgress(item, 180)).length);
  let requestSequence = 0;
  let hasLoaded = homeCache.peek(HOME_KEY) !== undefined;
  let skeletonTimer: ReturnType<typeof setTimeout> | null = null;

  function evaluateItem(item: MediaItem, budget: number): TimeFitResult {
    return evaluateTimeFit(
      item,
      budget,
      uiSettings.bookPageMinutes,
      uiSettings.mangaChapterMinutes,
      i18n.current,
    );
  }
  const TYPE_ORDER: Record<string, number> = {
    game: 1,
    anime: 2,
    manga: 3,
    movie: 4,
    tvshow: 5,
    book: 6,
  };

  function compareItems(a: MediaItem, b: MediaItem, currentSort: HomeSort): number {
    if (currentSort === "rating") {
      return (b.score ?? 0) - (a.score ?? 0);
    }
    if (currentSort === "title") {
      return a.title.localeCompare(b.title);
    }
    if (currentSort === "created") {
      return Date.parse(b.createdAt) - Date.parse(a.createdAt);
    }
    if (currentSort === "oldest") {
      return Date.parse(a.createdAt) - Date.parse(b.createdAt);
    }
    // updated = "по недавней активности": the newest known touch wins.
    const aTime = Date.parse(a.lastActivityAt || a.updatedAt || a.createdAt);
    const bTime = Date.parse(b.lastActivityAt || b.updatedAt || b.createdAt);
    return bTime - aTime;
  }

  function sortItems(list: MediaItem[], byType: boolean, currentSort: HomeSort): MediaItem[] {
    return [...list].sort((a, b) => {
      if (byType) {
        const typeA = TYPE_ORDER[a.type] ?? 99;
        const typeB = TYPE_ORDER[b.type] ?? 99;
        if (typeA !== typeB) return typeA - typeB;
      }
      return compareItems(a, b, currentSort);
    });
  }

  function sortBudgetItems(
    list: MediaItem[],
    budget: number,
    byType: boolean,
    currentSort: HomeSort,
  ): MediaItem[] {
    return [...list].sort((a, b) => {
      const finishA = evaluateItem(a, budget).canFinishNow ? 1 : 0;
      const finishB = evaluateItem(b, budget).canFinishNow ? 1 : 0;
      if (finishA !== finishB) {
        return finishB - finishA;
      }
      if (byType) {
        const typeA = TYPE_ORDER[a.type] ?? 99;
        const typeB = TYPE_ORDER[b.type] ?? 99;
        if (typeA !== typeB) return typeA - typeB;
      }
      return compareItems(a, b, currentSort);
    });
  }

  // Default keeps a compact per-section slice; "Show all" removes the cap entirely.
  // Compact mode shows 21 = three full rows on the 7-column grid; "All" lifts the cap.
  const HOME_SECTION_LIMIT = 21;

  // 200ms debounce so typing doesn't refilter the whole library on every keystroke.
  $effect(() => {
    const query = searchQuery;
    const timer = setTimeout(() => (debouncedSearch = query), 200);
    return () => clearTimeout(timer);
  });

  function matchesSearch(item: MediaItem, query: string): boolean {
    const needle = query.trim().toLowerCase();
    if (!needle) return true;
    const romaji = "romajiTitle" in item ? (item.romajiTitle ?? "") : "";
    const original = (item as { originalTitle?: string | null }).originalTitle ?? "";
    return [item.title, romaji, original].some((value) => value.toLowerCase().includes(needle));
  }

  function matchesCategory(item: MediaItem): boolean {
    if (selectedCategory === "all") return true;
    // "anime" spans both animated kinds: TvShow and Movie rows carrying the flag.
    if (selectedCategory === "anime") return typeKey(item) === "anime";
    return item.type === selectedCategory;
  }

  let filteredInProgress = $derived(
    inProgress.filter((item) => matchesSearch(item, debouncedSearch) && matchesCategory(item)),
  );
  let filteredUpNext = $derived(
    upNext.filter((item) => matchesSearch(item, debouncedSearch) && matchesCategory(item)),
  );
  let filteredRecentlyCompleted = $derived(
    recentlyCompleted.filter(
      (item) => matchesSearch(item, debouncedSearch) && matchesCategory(item),
    ),
  );
  let filteredTotal = $derived(
    filteredInProgress.length + filteredUpNext.length + filteredRecentlyCompleted.length,
  );

  let hasActiveFilters = $derived(
    debouncedSearch.trim() !== "" || selectedCategory !== "all" || timeBudget !== null,
  );

  function categoryLabel(value: string): string {
    return categoryOptions.find((option) => option.value === value)?.label ?? value;
  }

  function resetAllFilters() {
    searchQuery = "";
    selectedCategory = "all";
    timeBudget = null;
  }

  let inProgressFitting = $derived.by(() => {
    const budget = timeBudget;
    if (budget === null) return [];
    return filteredInProgress.filter((item) => evaluateItem(item, budget).fits);
  });

  let upNextFitting = $derived.by(() => {
    const budget = timeBudget;
    if (budget === null) return [];
    return filteredUpNext.filter((item) => evaluateItem(item, budget).fits);
  });

  let totalFitting = $derived(inProgressFitting.length + upNextFitting.length);

  let totalFinishable = $derived.by(() => {
    const budget = timeBudget;
    if (budget === null) return 0;
    let count = 0;
    for (const item of inProgressFitting) {
      if (evaluateItem(item, budget).canFinishNow) count++;
    }
    for (const item of upNextFitting) {
      if (evaluateItem(item, budget).canFinishNow) count++;
    }
    return count;
  });

  let customTimeValue = $state<number | string>("");
  let customTimeUnit = $state<"min" | "h">("min");

  function applyCustomTime(close?: () => void) {
    const val =
      typeof customTimeValue === "number" ? customTimeValue : parseFloat(String(customTimeValue));
    if (!isNaN(val) && val > 0) {
      timeBudget = customTimeUnit === "h" ? Math.round(val * 60) : Math.round(val);
      customTimeValue = "";
      close?.();
    }
  }

  const activeBudgetLabel = $derived.by(() => {
    if (timeBudget === null) return "";
    const opt = timeBudgetOptions.find((o) => o.value === timeBudget);
    return opt ? opt.label : formatTimeBudgetChip(timeBudget, i18n.current);
  });

  let displayInProgress = $derived(
    (timeBudget !== null
      ? sortBudgetItems(inProgressFitting, timeBudget, false, sort)
      : sortItems(filteredInProgress, false, sort)
    ).slice(0, showAll ? Number.POSITIVE_INFINITY : HOME_SECTION_LIMIT),
  );
  let displayUpNext = $derived(
    (timeBudget !== null
      ? sortBudgetItems(upNextFitting, timeBudget, false, sort)
      : sortItems(filteredUpNext, false, sort)
    ).slice(0, showAll ? Number.POSITIVE_INFINITY : HOME_SECTION_LIMIT),
  );
  let displayRecentlyCompleted = $derived(
    timeBudget === null
      ? sortItems(filteredRecentlyCompleted, false, sort).slice(
          0,
          showAll ? Number.POSITIVE_INFINITY : HOME_SECTION_LIMIT,
        )
      : [],
  );

  // "type" mode: one section per media kind across all matching items.
  let typeGroups = $derived.by(() => {
    if (groupByMode !== "type") return [];
    const pool =
      timeBudget !== null
        ? [...inProgressFitting, ...upNextFitting]
        : [...filteredInProgress, ...filteredUpNext, ...filteredRecentlyCompleted];
    const limit = showAll ? Number.POSITIVE_INFINITY : HOME_SECTION_LIMIT;
    return groupByMediaType(sortItems(pool, false, sort)).map((group) => ({
      ...group,
      items: group.items.slice(0, limit),
    }));
  });

  // "none" mode: a single unified stream without section headers.
  let unifiedList = $derived.by(() => {
    if (groupByMode !== "none") return [];
    const pool =
      timeBudget !== null
        ? [...inProgressFitting, ...upNextFitting]
        : [...filteredInProgress, ...filteredUpNext, ...filteredRecentlyCompleted];
    return sortItems(pool, false, sort).slice(
      0,
      showAll ? Number.POSITIVE_INFINITY : HOME_SECTION_LIMIT,
    );
  });

  /** 🎲 "Что выбрать?": random pick from what is actually on screen. */
  function pickRandomTitle() {
    const pool = [...displayInProgress, ...displayUpNext];
    const source = pool.length > 0 ? pool : displayRecentlyCompleted;
    if (source.length === 0) {
      showToast(i18n.t.home.randomEmpty, "warning");
      return;
    }
    const pick = source[Math.floor(Math.random() * source.length)];
    showToast(i18n.t.home.randomPickToast(pick.title), "success");
    onOpen(pick);
  }

  function typeKey(media: MediaItem): string {
    return media.type === "tvshow" && media.isAnime ? "anime" : media.type;
  }

  function typeLabel(key: string): string {
    switch (key) {
      case "game":
        return i18n.t.navigation.game;
      case "anime":
        return i18n.t.navigation.anime;
      case "manga":
        return i18n.t.navigation.manga;
      case "movie":
        return i18n.t.navigation.movie;
      case "tvshow":
        return i18n.t.navigation.tvshow;
      default:
        return i18n.t.navigation.book;
    }
  }

  function groupByMediaType(
    list: MediaItem[],
  ): { key: string; label: string; items: MediaItem[] }[] {
    const buckets = new Map<string, MediaItem[]>();
    for (const item of list) {
      const key = typeKey(item);
      const bucket = buckets.get(key);
      if (bucket) bucket.push(item);
      else buckets.set(key, [item]);
    }
    return [...buckets.entries()]
      .map(([key, items]) => ({ key, label: typeLabel(key), items }))
      .sort((a, b) => (TYPE_ORDER[a.key] ?? 99) - (TYPE_ORDER[b.key] ?? 99));
  }

  function handleStatusChange(item: MediaItem, newStatus: MediaStatus) {
    inProgress = inProgress.filter((x) => x.id !== item.id);
    upNext = upNext.filter((x) => x.id !== item.id);
    recentlyCompleted = recentlyCompleted.filter((x) => x.id !== item.id);

    const updated = { ...item, status: newStatus };
    if (newStatus === MEDIA_STATUS.inProgress) {
      inProgress = [updated, ...inProgress];
    } else if (newStatus === MEDIA_STATUS.planned) {
      upNext = [updated, ...upNext];
    } else if (newStatus === MEDIA_STATUS.completed) {
      recentlyCompleted = [updated, ...recentlyCompleted];
    }
    homeCache.set(HOME_KEY, { inProgress, upNext, recentlyCompleted });
  }

  // refreshKey бампается при любом изменении медиа (в т.ч. после фоновой задачи):
  // инвалидируем кэш, чтобы секции дома сразу перезапросились и показали новые
  // обложки, счётчики серий и статусы без F5.
  let prevRefreshKey: number | null = null;
  $effect(() => {
    void sort;
    void showAll;
    if (prevRefreshKey !== null && refreshKey !== prevRefreshKey) {
      homeCache.invalidate(HOME_KEY);
    }
    prevRefreshKey = refreshKey;
    const isInitial = !hasLoaded;
    void loadSections(++requestSequence, isInitial);

    return () => {
      if (skeletonTimer) clearTimeout(skeletonTimer);
    };
  });

  // Страховка: карточка ещё под оверлеем «Синхронизация», но ни одной активной
  // фоновой задачи нет — сигнал о завершении был потерян. Перезагружаем списки
  // один раз, чтобы спиннер не застревал до F5.
  let stuckReloadKey = 0;
  $effect(() => {
    if (jobsClient.activeCount > 0) return;
    const hasStuck = [inProgress, upNext, recentlyCompleted].some((list) =>
      list.some((item) => item.syncStatus === SYNC_STATUS.syncing),
    );
    if (!hasStuck) return;
    if (stuckReloadKey === refreshKey) return;
    stuckReloadKey = refreshKey;
    refresh();
  });

  function sortFilters(value: HomeSort) {
    switch (value) {
      case "updated":
      case "created":
        // The server only knows flat columns; the client re-sorts anyway,
        // so the initial fetch simply uses the same newest-first shape.
        return {
          sortBy: "createdAt" as const,
          sortOrder: "desc" as const,
        };
      case "oldest":
        return {
          sortBy: "createdAt" as const,
          sortOrder: "asc" as const,
        };
      case "rating":
        return { sortBy: "score" as const, sortOrder: "desc" as const };
      case "title":
        return { sortBy: "title" as const, sortOrder: "asc" as const };
    }
  }

  async function loadSections(sequence: number, showLoading = true) {
    if (skeletonTimer) clearTimeout(skeletonTimer);
    if (showLoading && !homeCache.peek(HOME_KEY)) {
      skeletonTimer = setTimeout(() => {
        if (sequence === requestSequence && !homeCache.peek(HOME_KEY)) {
          loading = true;
        }
      }, 120);
    }
    loadError = null;

    try {
      const sortParams = sortFilters(sort);
      // Compact mode fetches just over the 21-item slice; "All" pulls up to the
      // server cap so every matching title reaches the section.
      const fetchLimit = showAll ? 500 : HOME_SECTION_LIMIT;
      const [active, planned, completed] = await Promise.all([
        getMedia({ status: MEDIA_STATUS.inProgress, limit: fetchLimit, ...sortParams }),
        getMedia({ status: MEDIA_STATUS.planned, limit: fetchLimit, ...sortParams }),
        getMedia({ status: MEDIA_STATUS.completed, limit: fetchLimit, ...sortParams }),
      ]);

      if (sequence === requestSequence) {
        if (skeletonTimer) clearTimeout(skeletonTimer);
        hasLoaded = true;
        inProgress = active;
        upNext = planned;
        recentlyCompleted = completed.toSorted((left, right) => {
          if (sort === "rating") {
            return (right.score ?? 0) - (left.score ?? 0);
          }
          if (sort === "title") {
            return left.title.localeCompare(right.title);
          }
          if (sort === "oldest") {
            const leftTime = left.finishedAt
              ? Date.parse(left.finishedAt)
              : Date.parse(left.createdAt);
            const rightTime = right.finishedAt
              ? Date.parse(right.finishedAt)
              : Date.parse(right.createdAt);
            return leftTime - rightTime;
          }
          const leftTime = left.finishedAt ? Date.parse(left.finishedAt) : 0;
          const rightTime = right.finishedAt ? Date.parse(right.finishedAt) : 0;
          return rightTime - leftTime;
        });
        homeCache.set(HOME_KEY, { inProgress, upNext, recentlyCompleted });
        loading = false;
      }
    } catch (error) {
      if (sequence === requestSequence) {
        if (skeletonTimer) clearTimeout(skeletonTimer);
        loadError = error;
        loading = false;
      }
    }
  }

  function refresh() {
    void loadSections(++requestSequence, false);
  }

  async function updateProgress(id: string, currentProgress: number) {
    const updateInList = (list: MediaItem[]) =>
      list.map((item) => {
        if (item.id !== id) return item;
        if (item.type === "game") return { ...item, hoursPlayed: currentProgress };
        if (item.type === "book") return { ...item, currentPage: currentProgress };
        if (item.type === "manga") return { ...item, currentChapter: currentProgress };
        return item;
      });
    inProgress = updateInList(inProgress);
    upNext = updateInList(upNext);
    recentlyCompleted = updateInList(recentlyCompleted);
    homeCache.set(HOME_KEY, { inProgress, upNext, recentlyCompleted });
    await setProgress(id, currentProgress);
  }

  async function removeItem(item: MediaItem): Promise<void> {
    const main = document.querySelector("main");
    const currentScroll = main?.scrollTop ?? 0;

    const prevInProgress = inProgress;
    const prevUpNext = upNext;
    const prevCompleted = recentlyCompleted;

    inProgress = inProgress.filter((i) => i.id !== item.id);
    upNext = upNext.filter((i) => i.id !== item.id);
    recentlyCompleted = recentlyCompleted.filter((i) => i.id !== item.id);
    homeCache.set(HOME_KEY, { inProgress, upNext, recentlyCompleted });

    try {
      await deleteMedia(item.id);
      onMediaChanged();
    } catch {
      inProgress = prevInProgress;
      upNext = prevUpNext;
      recentlyCompleted = prevCompleted;
      homeCache.set(HOME_KEY, { inProgress, upNext, recentlyCompleted });
      showToast(i18n.t.errors.unexpected, "error");
    }

    setTimeout(() => {
      if (main && Math.abs(main.scrollTop - currentScroll) > 5) {
        main.scrollTop = currentScroll;
      }
    }, 20);
  }

  // Step episode for tvshow cards on Home screen. The series controller
  // (driven by the card) owns the optimistic store and the debounced PUT and
  // hands us the absolute post-step count; mirroring a delta on top of the
  // already-updated item double-counted every click. Only refresh section
  // identity so sections derived from the array re-render.
  function stepEpisode(item: MediaItem, newWatched: number) {
    if (item.type !== "tvshow") return;
    item.totalEpisodesWatched = newWatched;
    inProgress = [...inProgress];
  }
</script>

{#snippet section(items: MediaItem[], title: string, isProgressSection = false)}
  <section class="space-y-4">
    <div class="flex flex-wrap items-center gap-3">
      <h2 class="text-[25px] font-bold tracking-wide text-white">
        {title}
      </h2>
      <span
        class="bg-card-hover text-muted rounded-full px-2.5 py-0.5 text-xs font-semibold tabular-nums"
      >
        {items.length}
      </span>
      {#if isProgressSection && staleCount > 0}
        <button
          type="button"
          class="inline-flex cursor-pointer items-center gap-1.5 rounded-full border border-amber-500/30 bg-amber-500/10 px-2.5 py-1 text-xs font-medium text-amber-400 transition hover:border-amber-500/50 hover:bg-amber-500/20"
          onclick={() => (showStaleModal = true)}
        >
          <span>🕸</span>
          <span>{staleCount} {i18n.t.staleTriage.staleBadge}</span>
        </button>
      {/if}
    </div>
    <MediaGrid
      forceFlat={showAll}
      {items}
      {timeBudget}
      {onOpen}
      onProgress={updateProgress}
      onProgressCommitted={onMediaChanged}
      onStatusChange={handleStatusChange}
      onDelete={removeItem}
      {onEdit}
      onEpisodeStep={stepEpisode}
    />
  </section>
{/snippet}

<div class="space-y-8">
  <!-- Полноразмерная панель управления (точная копия FilterBar категорий) -->
  {#if !loading && !loadError}
    <section
      class="bg-surface mb-6 space-y-3 rounded-lg p-3 sm:p-4"
      aria-label="Панель управления главной"
    >
      <div class="flex flex-col justify-between gap-3 lg:flex-row lg:items-center">
        <!-- Левый кластер: группировка, категория, время, рандомайзер -->
        <div class="flex min-w-0 flex-1 items-center gap-2">
          <SlidersHorizontal size={16} class="text-muted shrink-0" aria-hidden="true" />
          <!-- Режим группировки -->
          <PopoverMenu
            id="home-grouping"
            options={groupingOptions}
            selected={groupByMode}
            onSelect={(value) => {
              groupByMode = value as GroupingMode;
              uiSettings.setGroupByType(groupByMode === "type");
            }}
            label={i18n.t.home.grouping}
            placement="bottom-start"
            openOnHover
            closeDelay={220}
          >
            {#snippet trigger({ popoverTargetId, anchorName, isOpen })}
              {@const GroupIcon = GROUP_MODE_ICONS[groupByMode]}
              <button
                type="button"
                popovertarget={popoverTargetId}
                popovertargetaction="toggle"
                style={isOpen ? `anchor-name: ${anchorName}` : undefined}
                class="tap bg-field text-muted hover:text-ink grid h-10 w-10 shrink-0 place-items-center rounded-lg border border-white/10 transition hover:border-white/20 has-[:popover-open]:ring-2 has-[:popover-open]:ring-indigo-500/40"
                title={i18n.t.home.grouping}
                aria-label={i18n.t.home.grouping}
              >
                <GroupIcon size={18} stroke-width={2} aria-hidden="true" />
              </button>
            {/snippet}
            {#snippet renderOption({ option })}
              {@const GroupIcon = GROUP_MODE_ICONS[option.value as GroupingMode]}
              <span class="flex items-center gap-2">
                <GroupIcon size={16} stroke-width={2} aria-hidden="true" />
                <span class="truncate">{option.label}</span>
              </span>
            {/snippet}
          </PopoverMenu>

          <!-- Категории -->
          <PopoverMenu
            id="home-category"
            options={categoryOptions}
            selected={selectedCategory}
            onSelect={(value) => (selectedCategory = value as CategoryFilter)}
            label={i18n.t.home.categories}
            placement="bottom-start"
            openOnHover
            closeDelay={220}
          >
            {#snippet trigger({ popoverTargetId, anchorName, isOpen })}
              <button
                type="button"
                popovertarget={popoverTargetId}
                popovertargetaction="toggle"
                style={isOpen ? `anchor-name: ${anchorName}` : undefined}
                class="tap bg-field text-ink flex h-10 shrink-0 items-center gap-2 rounded-lg border border-white/10 px-3 text-xs font-semibold transition hover:border-white/20 has-[:popover-open]:ring-2 has-[:popover-open]:ring-indigo-500/40"
                title={i18n.t.home.categories}
              >
                <span class="truncate">{categoryLabel(selectedCategory)}</span>
                <ChevronDown size={14} class="text-muted shrink-0" aria-hidden="true" />
              </button>
            {/snippet}
          </PopoverMenu>

          <!-- Меню фильтра времени -->
          <PopoverMenu
            id="home-time-budget"
            options={timeBudgetOptions}
            selected={timeBudget}
            onSelect={(val) => (timeBudget = val as TimeBudgetMinutes)}
            label={i18n.t.timeBudget.filterTitle}
            placement="bottom-start"
            openOnHover
            closeDelay={220}
          >
            {#snippet trigger({ popoverTargetId, anchorName, isOpen })}
              {#if timeBudget !== null}
                <button
                  type="button"
                  popovertarget={popoverTargetId}
                  popovertargetaction="toggle"
                  style={isOpen ? `anchor-name: ${anchorName}` : undefined}
                  class="tap bg-field text-ink flex h-10 shrink-0 items-center gap-2 rounded-lg border border-white/10 px-3 text-xs font-semibold transition hover:border-white/20 has-[:popover-open]:ring-2 has-[:popover-open]:ring-indigo-500/40"
                  title={i18n.t.timeBudget.filterTitle}
                >
                  <Clock3 size={16} stroke-width={2} aria-hidden="true" />
                  <span>{formatTimeBudgetChip(timeBudget, i18n.current)}</span>
                  <ChevronDown size={14} class="text-muted shrink-0" aria-hidden="true" />
                </button>
              {:else}
                <button
                  type="button"
                  popovertarget={popoverTargetId}
                  popovertargetaction="toggle"
                  style={isOpen ? `anchor-name: ${anchorName}` : undefined}
                  class="tap bg-field text-muted hover:text-ink grid h-10 w-10 shrink-0 place-items-center rounded-lg border border-white/10 transition hover:border-white/20 has-[:popover-open]:ring-2 has-[:popover-open]:ring-indigo-500/40"
                  title={i18n.t.timeBudget.filterTitle}
                  aria-label={i18n.t.timeBudget.filterTitle}
                >
                  <Clock3 size={18} stroke-width={2} aria-hidden="true" />
                </button>
              {/if}
            {/snippet}

            {#snippet footer({ close })}
              <form
                class="flex items-center gap-1.5"
                onsubmit={(e) => {
                  e.preventDefault();
                  applyCustomTime(close);
                }}
              >
                <input
                  type="number"
                  min="1"
                  max="999"
                  step="any"
                  aria-label={i18n.t.timeBudget.customTimePlaceholder}
                  title={i18n.t.timeBudget.customTimePlaceholder}
                  bind:value={customTimeValue}
                  class="bg-field h-8 w-18 rounded-lg border border-white/10 px-2.5 text-xs text-white tabular-nums outline-none focus:border-indigo-500/60 [&::-webkit-inner-spin-button]:appearance-none"
                  onkeydown={(e) => {
                    if (e.key === "Enter") {
                      e.preventDefault();
                      applyCustomTime(close);
                    }
                  }}
                />
                <Select
                  id="custom-time-unit"
                  options={[
                    { value: "min", label: i18n.t.timeBudget.unitMin },
                    { value: "h", label: i18n.t.timeBudget.unitHours },
                  ] as { value: "min" | "h"; label: string }[]}
                  value={customTimeUnit}
                  onChange={(next) => (customTimeUnit = next)}
                  class="h-8 rounded-lg px-2 text-xs"
                />
                <button
                  type="submit"
                  class="h-8 cursor-pointer rounded-lg bg-indigo-600 px-3 text-xs font-bold text-white shadow-sm transition hover:bg-indigo-500"
                  title={i18n.t.timeBudget.applyCustomTime}
                >
                  OK
                </button>
              </form>
            {/snippet}
          </PopoverMenu>

          <!-- 🎲 Случайный тайтл -->
          <button
            type="button"
            class="tap bg-field text-muted hover:text-ink grid h-10 w-10 shrink-0 place-items-center rounded-lg border border-white/10 transition hover:border-white/20"
            onclick={pickRandomTitle}
            title={i18n.t.home.randomPick}
            aria-label={i18n.t.home.randomPick}
          >
            <Dices size={18} stroke-width={2} aria-hidden="true" />
          </button>
        </div>

        <!-- Правый кластер: поиск, лимит, сортировка -->
        <div class="flex items-center gap-2">
          <label class="relative min-w-0 flex-1 lg:w-56 lg:flex-none">
            <span class="sr-only">{i18n.t.home.searchPlaceholder}</span>
            <Search
              size={18}
              class="text-muted pointer-events-none absolute top-1/2 left-3 -translate-y-1/2"
              aria-hidden="true"
            />
            <input
              type="search"
              bind:value={searchQuery}
              placeholder={i18n.t.home.searchPlaceholder}
              class="bg-field text-ink placeholder:text-muted h-10 w-full rounded-lg border border-white/10 pr-2.5 pl-9 text-sm outline-none focus:border-indigo-500/60 focus:ring-1 focus:ring-indigo-500/30"
            />
          </label>

          <!-- Лимит секций: 21 / Все -->
          <button
            type="button"
            role="switch"
            aria-checked={showAll}
            class={`tap flex h-10 shrink-0 items-center gap-1.5 rounded-lg border px-3 text-xs font-semibold transition ${
              showAll
                ? "border-indigo-500/60 bg-indigo-500/20 text-indigo-300"
                : "bg-field text-ink border-white/10 hover:border-white/20"
            }`}
            onclick={() => (showAll = !showAll)}
            title={i18n.t.home.limitTooltip}
          >
            <span>{showAll ? i18n.t.home.limitAll : i18n.t.home.limitCompact}</span>
          </button>

          <!-- Меню сортировки -->
          <PopoverMenu
            id="home-sort"
            options={sortOptions}
            selected={sort}
            onSelect={(value) => {
              sort = value as HomeSort;
              // `created`/`updated` are home-local; persist the sorts the library views share.
              if (sort === "oldest" || sort === "rating" || sort === "title") {
                uiSettings.setSortOption(sort as LibrarySort);
              }
            }}
            label={i18n.t.sort.label}
            placement="bottom-end"
            openOnHover
            closeDelay={220}
          >
            {#snippet trigger({ popoverTargetId, anchorName, isOpen })}
              {@const SortIcon = HOME_SORT_ICONS[sort]}
              <button
                type="button"
                popovertarget={popoverTargetId}
                popovertargetaction="toggle"
                style={isOpen ? `anchor-name: ${anchorName}` : undefined}
                class="tap bg-field text-muted hover:text-ink grid h-10 w-10 shrink-0 place-items-center rounded-lg border border-white/10 transition hover:border-white/20 has-[:popover-open]:ring-2 has-[:popover-open]:ring-indigo-500/40"
                title={i18n.t.sort.label}
                aria-label={i18n.t.sort.label}
              >
                <SortIcon size={18} stroke-width={2} aria-hidden="true" />
              </button>
            {/snippet}
            {#snippet renderOption({ option })}
              {@const SortIcon = HOME_SORT_ICONS[option.value as HomeSort]}
              <span class="flex items-center gap-2">
                <SortIcon size={16} stroke-width={2} aria-hidden="true" />
                <span class="truncate">{option.label}</span>
              </span>
            {/snippet}
          </PopoverMenu>
        </div>
      </div>

      <!-- Чипы активных фильтров -->
      {#if hasActiveFilters}
        <div
          class="flex flex-wrap items-center gap-2 border-t border-white/5 pt-2 text-xs text-slate-300"
        >
          {#if debouncedSearch}
            <span
              class="inline-flex items-center gap-1 rounded-md border border-white/10 bg-white/5 px-2.5 py-1"
            >
              <Search size={12} aria-hidden="true" />
              <span>"{debouncedSearch}"</span>
              <button type="button" class="hover:text-rose-400" onclick={() => (searchQuery = "")}
                >✕</button
              >
            </span>
          {/if}
          {#if selectedCategory !== "all"}
            <span
              class="border-accent/30 bg-accent/15 text-accent-soft inline-flex items-center gap-1 rounded-md border px-2.5 py-1"
            >
              <span>{categoryLabel(selectedCategory)}</span>
              <button
                type="button"
                class="hover:text-rose-400"
                onclick={() => (selectedCategory = "all")}>✕</button
              >
            </span>
          {/if}
          {#if timeBudget !== null}
            <span
              class="inline-flex items-center gap-1 rounded-md border border-indigo-500/30 bg-indigo-500/15 px-2.5 py-1 text-indigo-300"
            >
              <span>⏱ {formatTimeBudgetChip(timeBudget, i18n.current)}</span>
              <button type="button" class="hover:text-rose-400" onclick={() => (timeBudget = null)}
                >✕</button
              >
            </span>
          {/if}
          <button
            type="button"
            class="text-muted ml-auto text-xs underline hover:text-white"
            onclick={resetAllFilters}
          >
            {i18n.t.home.resetFilters}
          </button>
        </div>
      {/if}
    </section>
  {/if}

  <!-- Сводка при активном фильтре времени -->
  {#if !loading && !loadError && timeBudget !== null && totalFitting > 0}
    <div
      class="border-accent/30 bg-accent/10 text-ink flex items-center justify-between gap-3 rounded-xl border px-4 py-2.5 text-xs shadow-sm backdrop-blur-xs"
    >
      <div class="flex min-w-0 items-center gap-2">
        <span
          class="bg-accent/20 text-accent-soft grid h-6 w-6 shrink-0 place-items-center rounded-lg"
        >
          <Clock3 size={14} aria-hidden="true" />
        </span>
        <span class="truncate font-medium">
          {i18n.t.timeBudget.summary(totalFitting, totalFinishable)}
        </span>
      </div>
      <button
        type="button"
        class="tap text-muted shrink-0 cursor-pointer text-xs font-medium underline underline-offset-2 transition hover:text-white"
        onclick={() => (timeBudget = null)}
      >
        {i18n.t.timeBudget.reset}
      </button>
    </div>
  {/if}

  {#if loading}
    <MediaGrid forceFlat={showAll} items={[]} {loading} />
  {:else if loadError}
    <MediaGrid forceFlat={showAll} items={[]} error={loadError} onRetry={refresh} />
  {:else if filteredTotal === 0}
    <MediaGrid forceFlat={showAll} items={[]} />
  {:else if timeBudget !== null && totalFitting === 0}
    <div
      class="bg-surface/60 flex min-h-60 flex-col items-center justify-center gap-3 rounded-xl border border-white/5 p-8 text-center"
    >
      <div class="bg-card text-muted grid h-12 w-12 place-items-center rounded-xl">
        <Clock3 size={24} class="text-accent-soft" aria-hidden="true" />
      </div>
      <div>
        <p class="text-ink font-semibold">{i18n.t.timeBudget.emptyTitle}</p>
        <p class="text-muted mt-1 max-w-sm text-sm">
          {i18n.t.timeBudget.emptyHint(activeBudgetLabel)}
        </p>
      </div>
      <button
        type="button"
        class="bg-accent hover:bg-accent-hover mt-2 inline-flex cursor-pointer items-center gap-1.5 rounded-lg px-4 py-1.5 text-xs font-semibold text-white transition"
        onclick={() => (timeBudget = null)}
      >
        {i18n.t.timeBudget.reset}
      </button>
    </div>
  {:else if groupByMode === "type"}
    {#each typeGroups as group (group.key)}
      {@render section(group.items, group.label)}
    {/each}
  {:else if groupByMode === "none"}
    <MediaGrid
      forceFlat={showAll}
      items={unifiedList}
      {timeBudget}
      {onOpen}
      onProgress={updateProgress}
      onProgressCommitted={onMediaChanged}
      onStatusChange={handleStatusChange}
      onDelete={removeItem}
      {onEdit}
      onEpisodeStep={stepEpisode}
    />
  {:else}
    {#if displayInProgress.length > 0}
      {@render section(displayInProgress, i18n.t.views.inProgress, true)}
    {/if}
    {#if displayUpNext.length > 0}
      {@render section(displayUpNext, i18n.t.views.upNext, false)}
    {/if}
    {#if timeBudget === null && displayRecentlyCompleted.length > 0}
      {@render section(displayRecentlyCompleted, i18n.t.views.recentlyCompleted, false)}
    {/if}
  {/if}

  {#if showStaleModal}
    {#await import("$features/stale-triage/StaleBacklogModal.svelte") then { default: StaleBacklogModal }}
      <StaleBacklogModal
        isOpen={showStaleModal}
        onClose={() => (showStaleModal = false)}
        items={inProgress}
        onMediaChanged={() => {
          refresh();
          onMediaChanged();
        }}
      />
    {/await}
  {/if}
</div>
