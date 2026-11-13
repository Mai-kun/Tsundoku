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
  import { markStart, markEnd } from "$shared/utils/perfMarks";
  import { deleteMedia, getMediaWithCount, setProgress } from "$shared/api/api";
  import { jobsClient } from "$shared/api/jobsClient.svelte";
  import { showToast } from "$shared/ui/toast.svelte";
  import { LoaderCircle } from "$shared/ui/Icons";
  import { i18n } from "$shared/i18n/index.svelte";
  import { MEDIA_STATUS, SYNC_STATUS, type MediaItem } from "$shared/types";
  import FilterBar from "$features/filter-and-sort/FilterBar.svelte";
  import MediaGrid from "$widgets/media-grid/MediaGrid.svelte";
  import SectionRow from "$widgets/media-grid/SectionRow.svelte";
  import { uiSettings } from "$shared/utils/uiSettings.svelte";
  import { reconcileListProgress } from "$features/update-progress/optimisticProgress.svelte";
  import {
    buildStatusGroups,
    categoryFilters,
    filterByStatus,
    type Category,
  } from "./categoryModel";

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
  let allItems = $state.raw<MediaItem[]>(initialItems);
  // True DB-side total for the current category+search, from X-Total-Count.
  let totalCount = $state(initialItems.length);
  let loading = $state(initialItems.length === 0);
  /** Background refetch in flight: the grid stays mounted, dimmed, with a top-bar spinner. */
  let refreshing = $state(false);
  let loadError = $state<unknown>(null);
  let requestSequence = 0;

  let prevCategory: Category | null = null;
  // $effect.pre, not $effect: a plain effect runs *after* the DOM update, so switching category
  // painted one frame of the previous category's media before this reset ran. pre runs before,
  // so the stale list is never rendered.
  $effect.pre(() => {
    if (prevCategory !== null && category !== prevCategory) {
      markStart("tsundoku:category:switch");
    }
    prevCategory = category;
    const saved = savedCategoryState[category];
    status = saved?.status ?? (uiSettings.statusFilter as StatusFilter);
    sort = saved?.sort ?? (uiSettings.sortOption as LibrarySort);
    groupBy = saved?.groupBy ?? "status";
    search = saved?.search ?? "";
    const cached = categoryCache.peek(category);
    if (cached) {
      allItems = cached;
      loading = false;
    } else if (prevCategory !== null) {
      // Live category switch with nothing cached: keep loading false so no gray
      // placeholder or spinner ever flashes — the fade container below waits
      // quietly until loadItems fills the list, then the content fades in.
      // (On mount, prevCategory is null and the initial `loading` state stands:
      // it suppresses the "empty library" message while the first fetch runs.)
      loading = false;
    }
  });

  $effect(() => {
    void category;
    markEnd("tsundoku:category:switch");
  });

  let filteredItems = $derived(filterByStatus(allItems, status));
  // Section virtualizers share the app scroller; on a big library franchise
  // grouping still collapses into one grid past this size (dozens of groups
  // fighting over the same scroller). Status grouping is exempt: status
  // sections are capped at five, each virtually rendered, and their headers
  // must always show — planned (0) and completed (2) included.
  const SECTION_ROW_LIMIT = 40;
  let useSingleGrid = $derived(filteredItems.length > SECTION_ROW_LIMIT && groupBy === "franchise");
  let statusCounts = $derived(countStatuses(allItems));

  const statusSections = $derived([
    { status: MEDIA_STATUS.inProgress, title: i18n.t.status.inProgress },
    { status: MEDIA_STATUS.planned, title: i18n.t.status.planned },
    { status: MEDIA_STATUS.completed, title: i18n.t.status.completed },
    { status: MEDIA_STATUS.onHold, title: i18n.t.status.paused },
    { status: MEDIA_STATUS.dropped, title: i18n.t.status.dropped },
  ]);

  let statusGroups = $derived(buildStatusGroups(filteredItems, status, statusSections));

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
                other.title.trim().toLowerCase().startsWith(prefix.toLowerCase()),
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

    const groups: FranchiseGroup[] = Array.from(map.entries()).map(([name, list]) => ({
      name,
      items: list,
    }));

    if (noFranchise.length > 0) {
      groups.push({
        name: i18n.t.grouping.noFranchise,
        items: noFranchise,
      });
    }

    return groups;
  });

  // refreshKey бампается при любом изменении медиа (в т.ч. после фоновой задачи),
  // а смена категории ремоунтит вью с модульным кэшем, пережившим ремоунт:
  // в обоих случаях инвалидируем SWR-кэш, иначе loadItems выходит раньше времени
  // и список остаётся с устаревшими обложками/счётчиками до F5.
  let lastLoadedCategory: Category | null = null;
  let prevRefreshKey: number | null = null;
  $effect(() => {
    void search;
    void sort;
    const categoryChanged = lastLoadedCategory !== category;
    const revisionChanged = prevRefreshKey !== null && refreshKey !== prevRefreshKey;
    if (categoryChanged || revisionChanged) {
      categoryCache.invalidate(category);
    }
    lastLoadedCategory = category;
    prevRefreshKey = refreshKey;
    const sequence = ++requestSequence;
    const delay = search.trim() ? 500 : 0;
    const timer = setTimeout(() => void loadItems(sequence), delay);

    return () => {
      clearTimeout(timer);
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

  async function loadItems(sequence: number) {
    markStart("tsundoku:category:load");

    // Cached data already rendered by the pre-effect: don't flash a loader or
    // refetch when the view already shows exactly that cached list. Reference
    // equality matters: search results replace allItems without entering the
    // cache, so clearing the search never bails here and always refetches.
    const cached = categoryCache.peek(category);
    if (search.trim() === "" && cached && cached.length > 0 && allItems === cached) {
      loading = false;
      markEnd("tsundoku:category:load");
      return;
    }

    if (allItems.length === 0) {
      loading = true;
    } else {
      // Data is on screen: keep the grid mounted, just show the subtle spinner.
      refreshing = true;
    }
    loadError = null;

    try {
      const page = await getMediaWithCount({
        ...categoryFilters(category, search, sort),
        limit: 500,
      });
      const found = page.items;
      if (sequence === requestSequence) {
        loading = false;
        refreshing = false;
        totalCount = page.totalCount;
        // O(1) snapshot check instead of found.every() across 500+ items:
        // same length + same first/last updatedAt means nothing meaningful changed.
        const sameSnapshot =
          allItems.length === found.length &&
          allItems[0]?.updatedAt === found[0]?.updatedAt &&
          allItems[allItems.length - 1]?.updatedAt === found[found.length - 1]?.updatedAt;
        if (sameSnapshot) return;
        // Anti-stale overwrite: a step whose debounce/PUT has not fully landed must
        // survive the list replacement, so pending optimistic values are stamped onto
        // the incoming items (and into the cache below) instead of rolling back.
        reconcileListProgress(found);
        allItems = found;
        // Search-filtered results must not poison the category cache, otherwise
        // clearing the search would be blocked by the cache fast-path above.
        if (search.trim() === "") {
          categoryCache.set(category, found);
        }
      }
    } catch (error) {
      if (sequence === requestSequence) {
        loadError = error;
        loading = false;
        refreshing = false;
      }
    } finally {
      markEnd("tsundoku:category:load");
    }
  }

  function refresh() {
    categoryCache.invalidate(category);
    void loadItems(++requestSequence);
  }

  async function updateProgress(id: string, currentProgress: number) {
    allItems = allItems.map((item) => {
      if (item.id !== id) return item;
      if (item.type === "game") return { ...item, hoursPlayed: currentProgress };
      if (item.type === "book") {
        const isNovel = item.format === "light_novel" || item.format === "web_novel";
        return isNovel
          ? { ...item, currentChapter: currentProgress }
          : { ...item, currentPage: currentProgress };
      }
      if (item.type === "manga") return { ...item, currentChapter: currentProgress };
      return item;
    });
    categoryCache.set(category, allItems);
    await setProgress(id, currentProgress);
  }

  function countStatuses(list: MediaItem[]): Partial<Record<StatusFilter, number>> {
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

  function stepEpisode(item: MediaItem, newWatched: number) {
    if (item.type !== "tvshow") return;
    // The series controller owns the optimistic value and the debounced PUT
    // (one grouped request per burst) and hands us the absolute post-step
    // count. Mirror it onto the grid's own proxy object without recomputing
    // from item.totalEpisodesWatched (already up to date) — adding a delta
    // here double-counted every click. The controller rolls the same field
    // back on error.
    item.totalEpisodesWatched = newWatched;
  }

  function handleItemStatusChange(item: MediaItem, newStatus: import("$shared/types").MediaStatus) {
    allItems = allItems.map((x) => (x.id === item.id ? { ...x, status: newStatus } : x));
    categoryCache.set(category, allItems);
  }
</script>

{#snippet mediaGrid(gridItems: MediaItem[])}
  <MediaGrid
    items={gridItems}
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
{/snippet}

<div class="space-y-4">
  {#if active}
    <FilterBar
      {status}
      {sort}
      {groupBy}
      {search}
      counts={statusCounts}
      {totalCount}
      shownCount={filteredItems.length}
      onStatusChange={updateStatus}
      onSortChange={updateSort}
      onGroupByChange={updateGroupBy}
      onSearchChange={updateSearch}
    />
  {/if}

  <div>
    {#if loadError && allItems.length === 0}
      {@render mediaGrid([])}
    {:else if useSingleGrid}
      {@render mediaGrid(filteredItems)}
    {:else if groupBy === "status"}
      {#if statusGroups.length === 0 && !loading}
        {@render mediaGrid([])}
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
        {@render mediaGrid([])}
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
      {@render mediaGrid(filteredItems)}
    {/if}
  </div>
</div>
