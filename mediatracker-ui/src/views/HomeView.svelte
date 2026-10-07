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
    import { Layers } from "$shared/ui/Icons.svelte";
    import {
        deleteMedia,
        getMedia,
        getMediaItem,
        setProgress,
        setSeasonProgress,
    } from "$shared/api/api";
    import { showToast } from "$shared/ui/toast.svelte";
    import { i18n } from "$shared/i18n/index.svelte";
    import {
        MEDIA_STATUS,
        isTvShowDetail,
        type MediaItem,
        type MediaStatus,
    } from "$shared/types";
    import MediaGrid from "$widgets/media-grid/MediaGrid.svelte";
    import PopoverMenu from "$shared/ui/PopoverMenu.svelte";
    import { nextSeriesEpisodeStep } from "$entities/media/model/seriesStep";
    import { SORT_ICONS } from "$features/filter-and-sort/FilterBar.svelte";
    import { uiSettings } from "$shared/utils/uiSettings.svelte";

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
    let requestSequence = 0;
    let hasLoaded = homeCache.peek(HOME_KEY) !== undefined;
    let skeletonTimer: ReturnType<typeof setTimeout> | null = null;

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

    let displayInProgress = $derived(sortItems(inProgress, groupByType, sort));
    let displayUpNext = $derived(sortItems(upNext, groupByType, sort));
    let displayRecentlyCompleted = $derived(
        sortItems(recentlyCompleted, groupByType, sort),
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

{#snippet section(items: MediaItem[], title: string)}
    <section class="space-y-4">
        <h2 class="text-[25px] font-bold tracking-wide text-white">
            {title}
        </h2>
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
    <header class="flex flex-wrap items-end justify-between gap-4">
        <p
            class="text-xs font-semibold uppercase tracking-[0.18em] text-accent-soft"
        >
            {i18n.t.library.collectionLabel}
        </p>
        {#if !loading && !loadError}
            <div class="flex flex-wrap items-center gap-2">
                <button
                    type="button"
                    role="switch"
                    aria-checked={groupByType}
                    class={`tap grid h-12 w-12 shrink-0 place-items-center rounded-lg border transition cursor-pointer ${
                        groupByType
                            ? "border-accent/40 bg-accent/15 text-accent-soft"
                            : "border-white/10 bg-field text-muted hover:text-ink"
                    }`}
                    onclick={() => { groupByType = !groupByType; uiSettings.setGroupByType(groupByType); }}
                    title={i18n.t.views.groupByType}
                    aria-label={i18n.t.views.groupByType}
                >
                    <Layers size={22} stroke-width={2} aria-hidden="true" />
                </button>

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
                    {#snippet trigger({ popoverTargetId, anchorName })}
                        {@const SortIcon = SORT_ICONS[sort]}
                        <button
                            type="button"
                            popovertarget={popoverTargetId}
                            popovertargetaction="toggle"
                            style="anchor-name: {anchorName}"
                            class="tap grid h-12 w-12 shrink-0 place-items-center rounded-lg border border-white/10 bg-field text-muted transition hover:border-white/20 hover:text-ink has-[:popover-open]:ring-2 has-[:popover-open]:ring-indigo-500/40"
                            title={i18n.t.sort.label}
                            aria-label={i18n.t.sort.label}
                        >
                            <SortIcon
                                size={22}
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
        {/if}
    </header>

    {#if loading}
        <MediaGrid items={[]} {loading} />
    {:else if loadError}
        <MediaGrid items={[]} error={loadError} onRetry={refresh} />
    {:else if totalItems === 0}
        <MediaGrid items={[]} />
    {:else}
        {#if displayInProgress.length > 0}
            {@render section(displayInProgress, i18n.t.views.inProgress)}
        {/if}
        {#if displayUpNext.length > 0}
            {@render section(displayUpNext, i18n.t.views.upNext)}
        {/if}
        {#if displayRecentlyCompleted.length > 0}
            {@render section(
                displayRecentlyCompleted,
                i18n.t.views.recentlyCompleted,
            )}
        {/if}
    {/if}
</div>
