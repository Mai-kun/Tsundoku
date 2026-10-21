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
    import { Clock3, Layers } from "$shared/ui/Icons.svelte";
    import {
        deleteMedia,
        getMedia,
        getMediaItem,
        setProgress,
        setSeasonProgress,
    } from "$shared/api/api";
    import { jobsClient } from "$shared/api/jobsClient.svelte";
    import { showToast } from "$shared/ui/toast.svelte";
    import { i18n } from "$shared/i18n/index.svelte";
    import {
        MEDIA_STATUS,
        SYNC_STATUS,
        isTvShowDetail,
        type MediaItem,
        type MediaStatus,
    } from "$shared/types";
    import MediaGrid from "$widgets/media-grid/MediaGrid.svelte";
    import PopoverMenu from "$shared/ui/PopoverMenu.svelte";
    import { nextSeriesEpisodeStep } from "$entities/media/model/seriesStep";
    import { SORT_ICONS } from "$features/filter-and-sort/FilterBar.svelte";
    import {
        evaluateTimeFit,
        formatTimeBudgetChip,
        type TimeBudgetMinutes,
        type TimeFitResult,
    } from "$entities/media/model/timeBudget";
    import { uiSettings } from "$shared/utils/uiSettings.svelte";
    import { isStaleInProgress } from "$entities/media/model/staleTriage";
    import StaleBacklogModal from "$features/stale-triage/StaleBacklogModal.svelte";

    const timeBudgetOptions = $derived<
        { value: TimeBudgetMinutes; label: string }[]
    >([
        { value: null, label: i18n.t.timeBudget.options.all },
        { value: 15, label: i18n.t.timeBudget.options.m15 },
        { value: 30, label: i18n.t.timeBudget.options.m30 },
        { value: 45, label: i18n.t.timeBudget.options.m45 },
        { value: 60, label: i18n.t.timeBudget.options.h1 },
        { value: 90, label: i18n.t.timeBudget.options.h1_5 },
        { value: 120, label: i18n.t.timeBudget.options.h2_plus },
    ]);

    const sortOptions = $derived<
        { value: LibrarySort; label: string }[]
    >([
        { value: "newest", label: i18n.t.sort.newest },
        { value: "oldest", label: i18n.t.sort.oldest },
        { value: "rating", label: i18n.t.sort.rating },
        { value: "title", label: i18n.t.sort.title },
    ]);

    interface Props {
        refreshKey: number;
        onOpen: (item: MediaItem) => void;
        onMediaChanged: () => void;
        onEdit?: (item: MediaItem) => void;
    }

    let {
        refreshKey,
        onOpen,
        onMediaChanged,
        onEdit = () => {},
    }: Props = $props();

    let inProgress = $state<MediaItem[]>(homeCache.peek(HOME_KEY)?.inProgress ?? []);
    let upNext = $state<MediaItem[]>(homeCache.peek(HOME_KEY)?.upNext ?? []);
    let recentlyCompleted = $state<MediaItem[]>(
        homeCache.peek(HOME_KEY)?.recentlyCompleted ?? [],
    );
    let loading = $state(homeCache.peek(HOME_KEY) === undefined);
    let loadError = $state<unknown>(null);
    let sort = $state<LibrarySort>(uiSettings.sortOption as LibrarySort);
    let groupByType = $state<boolean>(uiSettings.groupByType);
    let timeBudget = $state<TimeBudgetMinutes>(null);
    let showStaleModal = $state(false);
    const staleCount = $derived(
        inProgress.filter((item) => isStaleInProgress(item, 180)).length,
    );
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

    function sortItems(
        list: MediaItem[],
        byType: boolean,
        currentSort: LibrarySort,
    ): MediaItem[] {
        return [...list].sort((a, b) => {
            if (byType) {
                const typeA = TYPE_ORDER[a.type] ?? 99;
                const typeB = TYPE_ORDER[b.type] ?? 99;
                if (typeA !== typeB) return typeA - typeB;
            }
            if (currentSort === "rating") {
                return (b.score ?? 0) - (a.score ?? 0);
            }
            if (currentSort === "title") {
                return a.title.localeCompare(b.title);
            }
            if (currentSort === "oldest") {
                const aTime = a.finishedAt
                    ? Date.parse(a.finishedAt)
                    : Date.parse(a.createdAt);
                const bTime = b.finishedAt
                    ? Date.parse(b.finishedAt)
                    : Date.parse(b.createdAt);
                return aTime - bTime;
            }
            const aTime = a.finishedAt
                ? Date.parse(a.finishedAt)
                : Date.parse(a.createdAt);
            const bTime = b.finishedAt
                ? Date.parse(b.finishedAt)
                : Date.parse(b.createdAt);
            return bTime - aTime;
        });
    }

    function sortBudgetItems(
        list: MediaItem[],
        budget: number,
        byType: boolean,
        currentSort: LibrarySort,
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
            if (currentSort === "rating") {
                return (b.score ?? 0) - (a.score ?? 0);
            }
            if (currentSort === "title") {
                return a.title.localeCompare(b.title);
            }
            if (currentSort === "oldest") {
                const aTime = a.finishedAt
                    ? Date.parse(a.finishedAt)
                    : Date.parse(a.createdAt);
                const bTime = b.finishedAt
                    ? Date.parse(b.finishedAt)
                    : Date.parse(b.createdAt);
                return aTime - bTime;
            }
            const aTime = a.finishedAt
                ? Date.parse(a.finishedAt)
                : Date.parse(a.createdAt);
            const bTime = b.finishedAt
                ? Date.parse(b.finishedAt)
                : Date.parse(b.createdAt);
            return bTime - aTime;
        });
    }

    // Dashboard sections show a compact recent slice; the full lists live in
    // the category views. 14 gives 2 neat rows on 7-column screens while keeping
    // every section under the grid's FLAT_LIMIT (15), so Home mounts plain card
    // grids with no virtualizer machinery.
    const HOME_SECTION_LIMIT = 14;

    let inProgressFitting = $derived.by(() => {
        const budget = timeBudget;
        if (budget === null) return [];
        return inProgress.filter((item) => evaluateItem(item, budget).fits);
    });

    let upNextFitting = $derived.by(() => {
        const budget = timeBudget;
        if (budget === null) return [];
        return upNext.filter((item) => evaluateItem(item, budget).fits);
    });

    let totalFitting = $derived(
        inProgressFitting.length + upNextFitting.length,
    );

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
            typeof customTimeValue === "number"
                ? customTimeValue
                : parseFloat(String(customTimeValue));
        if (!isNaN(val) && val > 0) {
            timeBudget =
                customTimeUnit === "h"
                    ? Math.round(val * 60)
                    : Math.round(val);
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
        timeBudget !== null
            ? sortBudgetItems(inProgressFitting, timeBudget, groupByType, sort).slice(0, HOME_SECTION_LIMIT)
            : sortItems(inProgress, groupByType, sort).slice(0, HOME_SECTION_LIMIT),
    );
    let displayUpNext = $derived(
        timeBudget !== null
            ? sortBudgetItems(upNextFitting, timeBudget, groupByType, sort).slice(0, HOME_SECTION_LIMIT)
            : sortItems(upNext, groupByType, sort).slice(0, HOME_SECTION_LIMIT),
    );
    let displayRecentlyCompleted = $derived(
        timeBudget === null
            ? sortItems(recentlyCompleted, groupByType, sort).slice(
                  0,
                  HOME_SECTION_LIMIT,
              )
            : [],
    );

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
            .sort(
                (a, b) => (TYPE_ORDER[a.key] ?? 99) - (TYPE_ORDER[b.key] ?? 99),
            );
    }

    let totalItems = $derived(
        inProgress.length + upNext.length + recentlyCompleted.length,
    );

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

    $effect(() => {
        void refreshKey;
        void sort;
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

    function sortFilters(value: LibrarySort) {
        switch (value) {
            case "newest":
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
            const [active, planned, completed] = await Promise.all([
                getMedia({ status: MEDIA_STATUS.inProgress, ...sortParams }),
                getMedia({ status: MEDIA_STATUS.planned, ...sortParams }),
                getMedia({ status: MEDIA_STATUS.completed, ...sortParams }),
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
                    const leftTime = left.finishedAt
                        ? Date.parse(left.finishedAt)
                        : 0;
                    const rightTime = right.finishedAt
                        ? Date.parse(right.finishedAt)
                        : 0;
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
                if (item.type === "game")
                    return { ...item, hoursPlayed: currentProgress };
                if (item.type === "book")
                    return { ...item, currentPage: currentProgress };
                if (item.type === "manga")
                    return { ...item, currentChapter: currentProgress };
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

    // Bug 6: step episode for tvshow cards on Home screen optimistically
    async function stepEpisode(item: MediaItem, delta: number) {
        if (item.type !== "tvshow") return;
        const prevWatched = item.totalEpisodesWatched ?? 0;
        const nextWatched = Math.max(0, prevWatched + delta);
        item.totalEpisodesWatched = nextWatched;
        inProgress = [...inProgress];

        try {
            const detail = await getMediaItem(item.id);
            if (!isTvShowDetail(detail) || !detail.seasons?.length) return;

            const step = nextSeriesEpisodeStep(detail.seasons, delta);
            if (!step) return;

            await setSeasonProgress(step.seasonId, step.currentEpisode);
            onMediaChanged();
        } catch {
            item.totalEpisodesWatched = prevWatched;
            inProgress = [...inProgress];
            showToast(i18n.t.errors.unexpected, "error");
        }
    }
</script>

{#snippet section(items: MediaItem[], title: string, isProgressSection = false)}
    <section class="space-y-4">
        <div class="flex items-center gap-3 flex-wrap">
            <h2 class="text-[25px] font-bold tracking-wide text-white">
                {title}
            </h2>
            <span
                class="rounded-full bg-card-hover px-2.5 py-0.5 text-xs font-semibold tabular-nums text-muted"
            >
                {items.length}
            </span>
            {#if isProgressSection && staleCount > 0}
                <button
                    type="button"
                    class="inline-flex items-center gap-1.5 rounded-full border border-amber-500/30 bg-amber-500/10 px-2.5 py-1 text-xs font-medium text-amber-400 hover:bg-amber-500/20 hover:border-amber-500/50 transition cursor-pointer"
                    onclick={() => (showStaleModal = true)}
                >
                    <span>🕸</span>
                    <span>{staleCount} {i18n.t.staleTriage.staleBadge}</span>
                </button>
            {/if}
        </div>
        {#if groupByType}
            {#each groupByMediaType(items) as group (group.key)}
                <div class="space-y-3">
                    <div class="flex items-center gap-2">
                        <h3 class="text-sm font-semibold text-ink">
                            {group.label}
                        </h3>
                        <span
                            class="rounded-full bg-card-hover px-2 py-0.5 text-[11px] font-semibold tabular-nums text-muted"
                        >
                            {group.items.length}
                        </span>
                    </div>
                    <MediaGrid
                        items={group.items}
                        {timeBudget}
                        {onOpen}
                        onProgress={updateProgress}
                        onProgressCommitted={onMediaChanged}
                        onStatusChange={handleStatusChange}
                        onDelete={removeItem}
                        {onEdit}
                        onEpisodeStep={stepEpisode}
                    />
                </div>
            {/each}
        {:else}
            <MediaGrid
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
        {/if}
    </section>
{/snippet}

<div class="space-y-8">
    <!-- Обычный заголовок вверху страницы -->
    <div class="mb-2">
        <p
            class="text-xs font-semibold uppercase tracking-[0.18em] text-accent-soft"
        >
            {i18n.t.library.collectionLabel}
        </p>
    </div>

    <!-- Плавающий островок кнопок справа (только кнопки интерактивны) -->
    {#if !loading && !loadError}
        <div class="sticky top-2 z-30 pointer-events-none -mt-8 mb-4 flex justify-end">
            <div
                class="pointer-events-auto inline-flex items-center gap-2 rounded-xl border border-white/10 bg-[#12151c]/90 p-1.5 shadow-xl shadow-black/50 backdrop-blur-md"
            >
                <!-- Меню фильтра времени -->
                <PopoverMenu
                    id="home-time-budget"
                    options={timeBudgetOptions}
                    selected={timeBudget}
                    onSelect={(val) => (timeBudget = val as TimeBudgetMinutes)}
                    label={i18n.t.timeBudget.filterTitle}
                    placement="bottom-end"
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
                                class="tap inline-flex h-9 items-center gap-1.5 rounded-lg border border-accent/40 bg-accent/15 px-2.5 text-xs font-semibold text-accent-soft transition hover:bg-accent/25 has-[:popover-open]:ring-2 has-[:popover-open]:ring-indigo-500/40 cursor-pointer"
                                title={i18n.t.timeBudget.filterTitle}
                                aria-label={i18n.t.timeBudget.filterTitle}
                            >
                                <Clock3 size={16} stroke-width={2} aria-hidden="true" />
                                <span>{formatTimeBudgetChip(timeBudget, i18n.current)}</span>
                            </button>
                        {:else}
                            <button
                                type="button"
                                popovertarget={popoverTargetId}
                                popovertargetaction="toggle"
                                style={isOpen ? `anchor-name: ${anchorName}` : undefined}
                                class="tap grid h-9 w-9 shrink-0 place-items-center rounded-lg border border-white/10 bg-field text-muted transition hover:border-white/20 hover:text-ink has-[:popover-open]:ring-2 has-[:popover-open]:ring-indigo-500/40 cursor-pointer"
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
                                placeholder={i18n.t.timeBudget.customTimePlaceholder}
                                bind:value={customTimeValue}
                                class="h-7 w-16 rounded bg-canvas border border-white/10 px-2 text-xs text-ink outline-none focus:border-accent"
                                onkeydown={(e) => {
                                    if (e.key === "Enter") {
                                        e.preventDefault();
                                        applyCustomTime(close);
                                    }
                                }}
                            />
                            <select
                                bind:value={customTimeUnit}
                                class="h-7 rounded bg-canvas border border-white/10 px-1 text-xs text-ink outline-none focus:border-accent cursor-pointer"
                            >
                                <option value="min">{i18n.t.timeBudget.unitMin}</option>
                                <option value="h">{i18n.t.timeBudget.unitHours}</option>
                            </select>
                            <button
                                type="submit"
                                class="tap h-7 rounded bg-accent px-2 text-xs font-medium text-white transition hover:bg-accent-hover cursor-pointer"
                                title={i18n.t.timeBudget.applyCustomTime}
                            >
                                OK
                            </button>
                        </form>
                    {/snippet}
                </PopoverMenu>

                <!-- Кнопка группировки -->
                <button
                    type="button"
                    role="switch"
                    aria-checked={groupByType}
                    class={`tap grid h-9 w-9 shrink-0 place-items-center rounded-lg border transition cursor-pointer ${
                        groupByType
                            ? "border-accent/40 bg-accent/15 text-accent-soft"
                            : "border-white/10 bg-field text-muted hover:text-ink"
                    }`}
                    onclick={() => { groupByType = !groupByType; uiSettings.setGroupByType(groupByType); }}
                    title={i18n.t.views.groupByType}
                    aria-label={i18n.t.views.groupByType}
                >
                    <Layers size={18} stroke-width={2} aria-hidden="true" />
                </button>

                <!-- Меню сортировки -->
                <PopoverMenu
                    id="home-sort"
                    options={sortOptions}
                    selected={sort}
                    onSelect={(value) => { sort = value as LibrarySort; uiSettings.setSortOption(sort); }}
                    label={i18n.t.sort.label}
                    placement="bottom-end"
                    openOnHover
                    closeDelay={220}
                >
                    {#snippet trigger({ popoverTargetId, anchorName, isOpen })}
                        {@const SortIcon = SORT_ICONS[sort]}
                        <button
                            type="button"
                            popovertarget={popoverTargetId}
                            popovertargetaction="toggle"
                            style={isOpen ? `anchor-name: ${anchorName}` : undefined}
                            class="tap grid h-9 w-9 shrink-0 place-items-center rounded-lg border border-white/10 bg-field text-muted transition hover:border-white/20 hover:text-ink has-[:popover-open]:ring-2 has-[:popover-open]:ring-indigo-500/40"
                            title={i18n.t.sort.label}
                            aria-label={i18n.t.sort.label}
                        >
                            <SortIcon
                                size={18}
                                stroke-width={2}
                                aria-hidden="true"
                            />
                        </button>
                    {/snippet}
                    {#snippet renderOption({ option })}
                        {@const SortIcon =
                            SORT_ICONS[option.value as LibrarySort]}
                        <span class="flex items-center gap-2">
                            <SortIcon
                                size={16}
                                stroke-width={2}
                                aria-hidden="true"
                            />
                            <span class="truncate">{option.label}</span>
                        </span>
                    {/snippet}
                </PopoverMenu>
            </div>
        </div>
    {/if}

    <!-- Сводка при активном фильтре времени -->
    {#if !loading && !loadError && timeBudget !== null && totalFitting > 0}
        <div
            class="flex items-center justify-between gap-3 rounded-xl border border-accent/30 bg-accent/10 px-4 py-2.5 text-xs text-ink shadow-sm backdrop-blur-xs"
        >
            <div class="flex items-center gap-2 min-w-0">
                <span class="grid h-6 w-6 shrink-0 place-items-center rounded-lg bg-accent/20 text-accent-soft">
                    <Clock3 size={14} aria-hidden="true" />
                </span>
                <span class="font-medium truncate">
                    {i18n.t.timeBudget.summary(totalFitting, totalFinishable)}
                </span>
            </div>
            <button
                type="button"
                class="tap text-xs text-muted hover:text-white transition cursor-pointer shrink-0 font-medium underline underline-offset-2"
                onclick={() => (timeBudget = null)}
            >
                {i18n.t.timeBudget.reset}
            </button>
        </div>
    {/if}

    {#if loading}
        <MediaGrid items={[]} {loading} />
    {:else if loadError}
        <MediaGrid items={[]} error={loadError} onRetry={refresh} />
    {:else if totalItems === 0}
        <MediaGrid items={[]} />
    {:else if timeBudget !== null && totalFitting === 0}
        <div
            class="flex min-h-60 flex-col items-center justify-center gap-3 rounded-xl border border-white/5 bg-surface/60 p-8 text-center"
        >
            <div class="grid h-12 w-12 place-items-center rounded-xl bg-card text-muted">
                <Clock3 size={24} class="text-accent-soft" aria-hidden="true" />
            </div>
            <div>
                <p class="font-semibold text-ink">{i18n.t.timeBudget.emptyTitle}</p>
                <p class="mt-1 max-w-sm text-sm text-muted">
                    {i18n.t.timeBudget.emptyHint(activeBudgetLabel)}
                </p>
            </div>
            <button
                type="button"
                class="mt-2 inline-flex items-center gap-1.5 rounded-lg bg-accent px-4 py-1.5 text-xs font-semibold text-white transition hover:bg-accent-hover cursor-pointer"
                onclick={() => (timeBudget = null)}
            >
                {i18n.t.timeBudget.reset}
            </button>
        </div>
    {:else}
        {#if displayInProgress.length > 0}
            {@render section(displayInProgress, i18n.t.views.inProgress, true)}
        {/if}
        {#if displayUpNext.length > 0}
            {@render section(displayUpNext, i18n.t.views.upNext, false)}
        {/if}
        {#if timeBudget === null && displayRecentlyCompleted.length > 0}
            {@render section(
                displayRecentlyCompleted,
                i18n.t.views.recentlyCompleted,
                false,
            )}
        {/if}
    {/if}

    <StaleBacklogModal
        isOpen={showStaleModal}
        onClose={() => (showStaleModal = false)}
        items={inProgress}
        onMediaChanged={() => {
            refresh();
            onMediaChanged();
        }}
    />
</div>
