<script module lang="ts">
    import type { StatusFilter } from "$lib/types";
    import type { GroupBy, LibrarySort } from "../media/FilterBar.svelte";

    interface SavedCategoryState {
        status: StatusFilter;
        sort: LibrarySort;
        groupBy: GroupBy;
        search: string;
    }

    const savedCategoryState: Partial<Record<string, SavedCategoryState>> = {};
    const categoryCache: Partial<Record<string, MediaItem[]>> = {};
</script>

<script lang="ts">
    import { untrack } from "svelte";
    import {
        deleteMedia,
        getMedia,
        getMediaItem,
        setProgress,
        setSeasonProgress,
    } from "$lib/api";
    import { showToast } from "$lib/stores/toast.svelte";
    import { i18n } from "$lib/i18n/index.svelte";
    import {
        isTvShowDetail,
        MEDIA_STATUS,
        type MediaFilters,
        type MediaItem,
    } from "$lib/types";
    import FilterBar from "../media/FilterBar.svelte";
    import MediaGrid from "../media/MediaGrid.svelte";

    export type Category =
        | "tvshow"
        | "movie"
        | "anime"
        | "manga"
        | "game"
        | "book";

    interface Props {
        category: Category;
        refreshKey: number;
        onOpen: (item: MediaItem) => void;
        onMediaChanged: () => void;
        onEdit?: (item: MediaItem) => void;
    }

    let {
        category,
        refreshKey,
        onOpen,
        onMediaChanged,
        onEdit = () => {},
    }: Props = $props();

    let status = $state<StatusFilter>("all");
    let sort = $state<LibrarySort>("newest");
    let groupBy = $state<GroupBy>("status");
    let search = $state("");
    let allItems = $state<MediaItem[]>(
        untrack(() => categoryCache[category] ?? []),
    );
    let loading = $state(false);
    let loadError = $state<unknown>(null);
    let requestSequence = 0;
    let skeletonTimer: ReturnType<typeof setTimeout> | null = null;

    // $effect.pre, not $effect: a plain effect runs *after* the DOM update, so switching category
    // painted one frame of the previous category's media before this reset ran. pre runs before,
    // so the stale list is never rendered.
    $effect.pre(() => {
        const saved = savedCategoryState[category];
        status = saved?.status ?? "all";
        sort = saved?.sort ?? "newest";
        groupBy = saved?.groupBy ?? "status";
        search = saved?.search ?? "";
        const cached = categoryCache[category];
        if (cached) {
            allItems = cached;
            loading = false;
        } else {
            allItems = [];
            loading = false;
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
            skeletonTimer = setTimeout(() => {
                if (sequence === requestSequence && allItems.length === 0) {
                    loading = true;
                }
            }, 120);
        }
        loadError = null;

        try {
            const found = await getMedia(categoryFilters());
            if (sequence === requestSequence) {
                if (skeletonTimer) clearTimeout(skeletonTimer);
                allItems = found;
                categoryCache[category] = found;
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
        categoryCache[category] = allItems;
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
        const currentScroll = main
            ? main.scrollTop
            : typeof window !== "undefined"
              ? window.scrollY
              : 0;

        const prevItems = allItems;
        allItems = allItems.filter((i) => i.id !== item.id);
        categoryCache[category] = allItems;

        try {
            await deleteMedia(item.id);
            onMediaChanged();
        } catch {
            allItems = prevItems;
            categoryCache[category] = prevItems;
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
        savedCategoryState[category] = { status: value, sort, groupBy, search };
    }

    function updateSort(value: LibrarySort) {
        sort = value;
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

            const activeSeason =
                detail.seasons.find(
                    (s) => s.status === MEDIA_STATUS.inProgress,
                ) ??
                detail.seasons.find((s) => s.status === MEDIA_STATUS.planned) ??
                detail.seasons[detail.seasons.length - 1];

            if (!activeSeason) return;

            const next = Math.max(
                0,
                Math.min(
                    (activeSeason.currentEpisode ?? 0) + delta,
                    activeSeason.totalEpisodes > 0
                        ? activeSeason.totalEpisodes
                        : Infinity,
                ),
            );

            await setSeasonProgress(activeSeason.id, next);
            onMediaChanged();
        } catch {
            item.totalEpisodesWatched = prevWatched;
            allItems = [...allItems];
            showToast(i18n.t.errors.unexpected, "error");
        }
    }

    function handleItemStatusChange(
        item: MediaItem,
        newStatus: import("$lib/types").MediaStatus,
    ) {
        allItems = allItems.map((x) =>
            x.id === item.id ? { ...x, status: newStatus } : x,
        );
        categoryCache[category] = allItems;
    }
</script>

<div class="space-y-6">
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
                {#each statusGroups as group (`${category}:${group.status}`)}
                    <section class="space-y-3">
                        <div class="flex items-center gap-2">
                            <h2
                                class="text-[25px] font-bold tracking-wide text-white"
                            >
                                {group.title}
                            </h2>
                            <span
                                class="rounded-full bg-surface px-2.5 py-0.5 text-xs font-semibold text-muted"
                                >{group.items.length}</span
                            >
                        </div>
                        <MediaGrid
                            items={group.items}
                            loading={false}
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
                    </section>
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
                {#each franchiseGroups as group (`${category}:${group.name}`)}
                    <section class="space-y-3">
                        <div class="flex items-center gap-2">
                            <h2
                                class="text-[25px] font-bold tracking-wide text-white"
                            >
                                {group.name}
                            </h2>
                            <span
                                class="rounded-full bg-surface px-2.5 py-0.5 text-xs font-semibold text-muted"
                                >{group.items.length}</span
                            >
                        </div>
                        <MediaGrid
                            items={group.items}
                            loading={false}
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
                    </section>
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
