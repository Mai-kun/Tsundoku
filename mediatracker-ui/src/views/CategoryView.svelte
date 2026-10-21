<script module lang="ts">
    import type { StatusFilter } from "$shared/types";
    import type { GroupBy, LibrarySort } from "$features/filter-and-sort/FilterBar.svelte";
    import { createSwrCache } from "$shared/utils/swrCache";

    interface SavedCategoryState {
        status: StatusFilter;
        sort: LibrarySort;
        groupBy: GroupBy;
        search: string;
    }

    const savedCategoryState: Partial<Record<string, SavedCategoryState>> = {};
    const categoryCache = createSwrCache<MediaItem[]>();
</script>

<script lang="ts">
    import { untrack } from "svelte";
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
        isTvShowDetail,
        MEDIA_STATUS,
        SYNC_STATUS,
        type MediaFilters,
        type MediaItem,
    } from "$shared/types";
    import FilterBar from "$features/filter-and-sort/FilterBar.svelte";
    import MediaGrid from "$widgets/media-grid/MediaGrid.svelte";
    import SectionRow from "$widgets/media-grid/SectionRow.svelte";
    import { nextSeriesEpisodeStep } from "$entities/media/model/seriesStep";
    import { uiSettings } from "$shared/utils/uiSettings.svelte";

    export type Category =
        | "tvshow"
        | "movie"
        | "anime"
        | "manga"
        | "game"
        | "book";

    interface Props {
        category: Category;
        active?: boolean;
        refreshKey: number;
        onOpen: (item: MediaItem) => void;
        onMediaChanged: () => void;
        onEdit?: (item: MediaItem) => void;
    }

    let {
        category,
        active = true,
        refreshKey,
        onOpen,
        onMediaChanged,
        onEdit = () => {},
    }: Props = $props();

    let status = $state<StatusFilter>("all");
    let sort = $state<LibrarySort>("newest");
    let groupBy = $state<GroupBy>("status");
    let search = $state("");
    const initialItems = untrack(() => categoryCache.peek(category) ?? []);
    let allItems = $state<MediaItem[]>(initialItems);
    let loading = $state(initialItems.length === 0);
    let loadError = $state<unknown>(null);
    let requestSequence = 0;
    let skeletonTimer: ReturnType<typeof setTimeout> | null = null;

    // $effect.pre, not $effect: a plain effect runs *after* the DOM update, so switching category
    // painted one frame of the previous category's media before this reset ran. pre runs before,
    // so the stale list is never rendered.
    $effect.pre(() => {
        const saved = savedCategoryState[category];
        status = saved?.status ?? (uiSettings.statusFilter as StatusFilter);
        sort = saved?.sort ?? (uiSettings.sortOption as LibrarySort);
        groupBy = saved?.groupBy ?? "status";
        search = saved?.search ?? "";
        const cached = categoryCache.peek(category);
        if (cached) {
            allItems = cached;
            loading = false;
        } else {
            allItems = [];
            loading = true;
        }
    });

    let filteredItems = $derived(
        status === "all"
            ? allItems
            : allItems.filter((item) => item.status === status),
    );
    let statusCounts = $derived(countStatuses(allItems));

    const statusSections = $derived([
        { status: MEDIA_STATUS.inProgress, title: i18n.t.status.inProgress },
        { status: MEDIA_STATUS.planned, title: i18n.t.status.planned },
        { status: MEDIA_STATUS.completed, title: i18n.t.status.completed },
        { status: MEDIA_STATUS.onHold, title: i18n.t.status.paused },
        { status: MEDIA_STATUS.dropped, title: i18n.t.status.dropped },
    ]);

    let statusGroups = $derived.by(() => {
        return statusSections
            .map((sec) => ({
                status: sec.status,
                title: sec.title,
                items: filteredItems.filter(
                    (item) => item.status === sec.status,
                ),
            }))
            .filter((sec) =>
                status === "all" ? sec.items.length > 0 : sec.status === status,
            );
    });

    interface FranchiseGroup {
        name: string;
        items: MediaItem[];
    }

    let franchiseGroups = $derived.by<FranchiseGroup[]>(() => {
        if (groupBy !== "franchise") return [];

        const map = new Map<string, MediaItem[]>();
        const noFranchise: MediaItem[] = [];

        for (const item of filteredItems) {
            let name = item.franchiseName?.trim();
            if (!name) {
                const title = item.title.trim();
                const colonIdx = title.search(/[:\-\/]/);
                if (colonIdx > 2) {
                    const prefix = title.substring(0, colonIdx).trim();
                    if (prefix.length >= 3) {
                        const hasMatch = filteredItems.some(
                            (other) =>
                                other.id !== item.id &&
                                other.title
                                    .trim()
                                    .toLowerCase()
                                    .startsWith(prefix.toLowerCase()),
                        );
                        if (hasMatch) {
                            name = prefix;
                        }
                    }
                } else if (title.length >= 3) {
                    const hasPrefixedSibling = filteredItems.some(
                        (other) =>
                            other.id !== item.id &&
                            other.title
                                .trim()
                                .toLowerCase()
                                .startsWith(title.toLowerCase() + ":"),
                    );
                    if (hasPrefixedSibling) {
                        name = title;
                    }
                }
            }

            if (name) {
                if (!map.has(name)) map.set(name, []);
                map.get(name)!.push(item);
            } else {
                noFranchise.push(item);
            }
        }

        const groups: FranchiseGroup[] = Array.from(map.entries()).map(
            ([name, list]) => ({
                name,
                items: list,
            }),
        );

        if (noFranchise.length > 0) {
            groups.push({
                name: i18n.t.grouping.noFranchise,
                items: noFranchise,
            });
        }

        return groups;
    });

    $effect(() => {
        void refreshKey;
        void category;
        void search;
        void sort;
        const sequence = ++requestSequence;
        const delay = search.trim() ? 500 : 0;
        const timer = setTimeout(() => void loadItems(sequence), delay);

        return () => {
            clearTimeout(timer);
            if (skeletonTimer) clearTimeout(skeletonTimer);
        };
    });

    // Страховка: карточка ещё под оверлеем «Синхронизация», но ни одной активной
    // фоновой задачи нет — сигнал о завершении был потерян (упавший джоб, отрицший
    // SSE). Перезагружаем список один раз, чтобы спиннер не застревал до F5.
    let stuckReloadKey = 0;
    $effect(() => {
        if (jobsClient.activeCount > 0) return;
        if (!allItems.some((item) => item.syncStatus === SYNC_STATUS.syncing)) return;
        if (stuckReloadKey === refreshKey) return;
        stuckReloadKey = refreshKey;
        refresh();
    });

    function categoryFilters(): MediaFilters {
        const filters: MediaFilters = {
            search: search.trim() || undefined,
            ...sortFilters(sort),
        };

        switch (category) {
            case "anime":
                return { ...filters, isAnime: true };
            case "tvshow":
                return { ...filters, type: "tvshow", isAnime: false };
            case "movie":
                return { ...filters, type: "movie", isAnime: false };
            default:
                return { ...filters, type: category };
        }
    }

    function sortFilters(
        value: LibrarySort,
    ): Pick<MediaFilters, "sortBy" | "sortOrder"> {
        switch (value) {
            case "oldest":
                return { sortBy: "createdAt", sortOrder: "asc" };
            case "rating":
                return { sortBy: "score", sortOrder: "desc" };
            case "title":
                return { sortBy: "title", sortOrder: "asc" };
            default:
                return { sortBy: "createdAt", sortOrder: "desc" };
        }
    }

    async function loadItems(sequence: number) {
        if (skeletonTimer) clearTimeout(skeletonTimer);
        if (allItems.length === 0) {
            loading = true;
        } else {
            skeletonTimer = setTimeout(() => {
                if (sequence === requestSequence) {
                    loading = true;
                }
            }, 120);
        }
        loadError = null;

        try {
            const found = await getMedia(categoryFilters());
            if (sequence === requestSequence) {
                if (skeletonTimer) clearTimeout(skeletonTimer);
                loading = false;
                // Пропускаем холостую мутацию стейта, если данные не изменились:
                // после возврата из деталки фоновая перезагрузка перезаписывала
                // allItems новым объектом и пересобирала сетку прямо во время
                // восстановленного скролла (микрофриз). Сравниваем отпечаток элемента,
                // а не только id: при завершении фоновой синхронизации состав совпадает,
                // но меняются syncStatus, обложка и updatedAt — сетка обязана обновиться.
                const sameSnapshot =
                    allItems.length === found.length &&
                    found.every(
                        (item, index) =>
                            item.id === allItems[index]?.id &&
                            item.syncStatus === allItems[index]?.syncStatus &&
                            item.updatedAt === allItems[index]?.updatedAt &&
                            item.status === allItems[index]?.status &&
                            item.score === allItems[index]?.score &&
                            item.coverUrl === allItems[index]?.coverUrl,
                    );
                if (sameSnapshot) return;
                allItems = found;
                categoryCache.set(category, found);
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
        void loadItems(++requestSequence);
    }

    async function updateProgress(id: string, currentProgress: number) {
        allItems = allItems.map((item) => {
            if (item.id !== id) return item;
            if (item.type === "game")
                return { ...item, hoursPlayed: currentProgress };
            if (item.type === "book")
                return { ...item, currentPage: currentProgress };
            if (item.type === "manga")
                return { ...item, currentChapter: currentProgress };
            return item;
        });
        categoryCache.set(category, allItems);
        await setProgress(id, currentProgress);
    }

    function countStatuses(
        list: MediaItem[],
    ): Partial<Record<StatusFilter, number>> {
        const counts: Partial<Record<StatusFilter, number>> = {
            all: list.length,
        };

        for (const value of [
            MEDIA_STATUS.planned,
            MEDIA_STATUS.inProgress,
            MEDIA_STATUS.completed,
            MEDIA_STATUS.onHold,
            MEDIA_STATUS.dropped,
        ]) {
            counts[value] = list.filter((item) => item.status === value).length;
        }

        return counts;
    }

    async function removeItem(item: MediaItem): Promise<void> {
        const main = document.querySelector("main");
        const currentScroll = main?.scrollTop ?? 0;

        const prevItems = allItems;
        allItems = allItems.filter((i) => i.id !== item.id);
        categoryCache.set(category, allItems);

        try {
            await deleteMedia(item.id);
            onMediaChanged();
        } catch {
            allItems = prevItems;
            categoryCache.set(category, prevItems);
            showToast(i18n.t.errors.unexpected, "error");
        }

        setTimeout(() => {
            if (main && Math.abs(main.scrollTop - currentScroll) > 5) {
                main.scrollTop = currentScroll;
            }
        }, 20);
    }

    function updateStatus(value: StatusFilter) {
        status = value;
        uiSettings.setStatusFilter(value);
        savedCategoryState[category] = { status: value, sort, groupBy, search };
    }

    function updateSort(value: LibrarySort) {
        sort = value;
        uiSettings.setSortOption(value);
        savedCategoryState[category] = { status, sort: value, groupBy, search };
    }

    function updateGroupBy(value: GroupBy) {
        groupBy = value;
        savedCategoryState[category] = { status, sort, groupBy: value, search };
    }

    function updateSearch(value: string) {
        search = value;
        savedCategoryState[category] = { status, sort, groupBy, search: value };
    }

    async function stepEpisode(item: MediaItem, delta: number) {
        if (item.type !== "tvshow") return;
        const prevWatched = item.totalEpisodesWatched ?? 0;
        const nextWatched = Math.max(0, prevWatched + delta);
        item.totalEpisodesWatched = nextWatched;
        allItems = [...allItems];

        try {
            const detail = await getMediaItem(item.id);
            if (!isTvShowDetail(detail) || !detail.seasons?.length) return;

            const step = nextSeriesEpisodeStep(detail.seasons, delta);
            if (!step) return;

            await setSeasonProgress(step.seasonId, step.currentEpisode);
            onMediaChanged();
        } catch {
            item.totalEpisodesWatched = prevWatched;
            allItems = [...allItems];
            showToast(i18n.t.errors.unexpected, "error");
        }
    }

    function handleItemStatusChange(
        item: MediaItem,
        newStatus: import("$shared/types").MediaStatus,
    ) {
        allItems = allItems.map((x) =>
            x.id === item.id ? { ...x, status: newStatus } : x,
        );
        categoryCache.set(category, allItems);
    }
</script>

<div class="space-y-6">
    {#if active}
        <FilterBar
            {status}
            {sort}
            {groupBy}
            {search}
            counts={statusCounts}
            onStatusChange={updateStatus}
            onSortChange={updateSort}
            onGroupByChange={updateGroupBy}
            onSearchChange={updateSearch}
        />
    {/if}

    <p class="text-xs font-medium text-muted">
        {i18n.t.library.resultCount(filteredItems.length)}
    </p>

    {#if loading && allItems.length === 0}
        <MediaGrid
            items={[]}
            loading={true}
            error={null}
            onRetry={refresh}
            {onOpen}
            onProgress={updateProgress}
            onProgressCommitted={onMediaChanged}
            onStatusChange={handleItemStatusChange}
            onEpisodeStep={stepEpisode}
            onDelete={removeItem}
            {onEdit}
        />
    {:else if groupBy === "status"}
        {#if statusGroups.length === 0 && !loading}
            <MediaGrid
                items={[]}
                {loading}
                error={loadError}
                onRetry={refresh}
                {onOpen}
                onProgress={updateProgress}
                onProgressCommitted={onMediaChanged}
                onStatusChange={handleItemStatusChange}
                onEpisodeStep={stepEpisode}
                onDelete={removeItem}
                {onEdit}
            />
        {:else}
            <div class="space-y-8">
                {#each statusGroups as group (group.status)}
                    <SectionRow
                        title={group.title}
                        items={group.items}
                        onRetry={refresh}
                        {onOpen}
                        onProgress={updateProgress}
                        onProgressCommitted={onMediaChanged}
                        onStatusChange={handleItemStatusChange}
                        onEpisodeStep={stepEpisode}
                        onDelete={removeItem}
                        {onEdit}
                    />
                {/each}
            </div>
        {/if}
    {:else if groupBy === "franchise"}
        {#if franchiseGroups.length === 0 && !loading}
            <MediaGrid
                items={[]}
                {loading}
                error={loadError}
                onRetry={refresh}
                {onOpen}
                onProgress={updateProgress}
                onProgressCommitted={onMediaChanged}
                onStatusChange={handleItemStatusChange}
                onEpisodeStep={stepEpisode}
                onDelete={removeItem}
                {onEdit}
            />
        {:else}
            <div class="space-y-8">
                {#each franchiseGroups as group (group.name)}
                    <SectionRow
                        title={group.name}
                        items={group.items}
                        onRetry={refresh}
                        {onOpen}
                        onProgress={updateProgress}
                        onProgressCommitted={onMediaChanged}
                        onStatusChange={handleItemStatusChange}
                        onEpisodeStep={stepEpisode}
                        onDelete={removeItem}
                        {onEdit}
                    />
                {/each}
            </div>
        {/if}
    {:else}
        <MediaGrid
            items={filteredItems}
            {loading}
            error={loadError}
            onRetry={refresh}
            {onOpen}
            onProgress={updateProgress}
            onProgressCommitted={onMediaChanged}
            onStatusChange={handleItemStatusChange}
            onEpisodeStep={stepEpisode}
            onDelete={removeItem}
            {onEdit}
        />
    {/if}
</div>
