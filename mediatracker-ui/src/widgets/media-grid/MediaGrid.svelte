<script lang="ts">
  import { onDestroy, untrack } from "svelte";
  import { markStart, markEnd } from "$shared/utils/perfMarks";
  import { createVirtualizer } from "@tanstack/svelte-virtual";
  import type { SvelteVirtualizer } from "@tanstack/svelte-virtual";
  import { Inbox, RefreshCw, X } from "$shared/ui/Icons.svelte";
  import { errorMessage } from "$shared/api/api";
  import { i18n } from "$shared/i18n/index.svelte";
  import type { MediaItem } from "$shared/types";
  import MediaCard from "$widgets/media-card/MediaCard.svelte";
  import type { CardTimeHint } from "$widgets/media-card/cardTypes";
  import { evaluateTimeFit, type TimeBudgetMinutes } from "$entities/media/model/timeBudget";
  import { uiSettings } from "$shared/utils/uiSettings.svelte";
  import { bumpGridLayout, gridLayoutVersion } from "./gridLayout.svelte";
  import { chunkIntoRows, columnsForWidth, estimateRowHeight } from "./virtualGrid";

  interface Props {
    items: MediaItem[];
    timeBudget?: TimeBudgetMinutes;
    getTimeHint?: (item: MediaItem) => CardTimeHint | null;
    showProgress?: boolean;
    loading?: boolean;
    isInitialLoading?: boolean;
    error?: unknown;
    onRetry?: () => void;
    onOpen?: (item: MediaItem) => void;
    onProgress?: (id: string, currentProgress: number) => Promise<void>;
    onProgressCommitted?: () => void;
    onStatusChange?: (item: MediaItem, newStatus: import("$shared/types").MediaStatus) => void;
    onDelete?: (item: MediaItem) => Promise<void>;
    onEdit?: (item: MediaItem) => void;
    onEpisodeStep?: (item: MediaItem, delta: number) => Promise<void>;
    onRemoveFromList?: (item: MediaItem) => Promise<void>;
  }

  let {
    items,
    timeBudget,
    getTimeHint,
    showProgress = true,
    loading = false,
    isInitialLoading = false,
    error = null,
    onRetry = () => {},
    onOpen = () => {},
    onProgress,
    onProgressCommitted = () => {},
    onStatusChange,
    onDelete,
    onEdit = () => {},
    onEpisodeStep,
    onRemoveFromList,
  }: Props = $props();

  // Below this many cards the flat grid is cheaper than the virtualizer machinery.
  const FLAT_LIMIT = 15;
  const ROW_GAP = 16; // matches gap-4

  // Column count must come from the viewport, not the container: the Tailwind
  // classes below respond to viewport breakpoints, and row chunking has to
  // agree with them or rows render with empty slots.
  let viewportWidth = $state(typeof window === "undefined" ? 1280 : window.innerWidth);
  $effect(() => {
    const onResize = () => (viewportWidth = window.innerWidth);
    window.addEventListener("resize", onResize);
    return () => window.removeEventListener("resize", onResize);
  });

  let columnsCount = $derived(columnsForWidth(viewportWidth));
  let rowCount = $derived(Math.ceil(items.length / columnsCount));
  let shouldVirtualize = $derived(items.length >= FLAT_LIMIT);

  // Rows are positioned from a single height per breakpoint instead of
  // measuring every row: measureElement's per-row ResizeObserver caused
  // layout thrash on scroll in WebView2. The breakpoint table seeds the
  // first paint; the effect below corrects the seed asynchronously (after
  // layout, never during mount) from the first rendered row — rows are
  // uniform within one breakpoint.
  let rowHeight = $state(untrack(() => estimateRowHeight(viewportWidth)));

  // The scroller is the app shell's #main-scroll, shared by every grid on the
  // page. setOptions always re-emits the store, so it must never be called
  // from an effect that reads $virtualizer - hence the imperative handle.
  // count is a deliberate initial snapshot; $effect.pre below keeps it synced.
  const virtualizer = createVirtualizer<HTMLElement, HTMLDivElement>({
    count: untrack(() => rowCount),
    getScrollElement: () => document.getElementById("main-scroll"),
    estimateSize: () => rowHeight,
    gap: ROW_GAP,
    overscan: 8,
    initialOffset: () => document.getElementById("main-scroll")?.scrollTop ?? 0,
    scrollMargin: 0,
  });
  let virtualizerInstance: SvelteVirtualizer<HTMLElement, HTMLDivElement> | null = null;
  const unsubscribeVirtualizer = virtualizer.subscribe((instance) => {
    virtualizerInstance = instance;
  });
  onDestroy(unsubscribeVirtualizer);

  // Several grids share one scroller (sectioned pages), so the virtualizer
  // needs this grid's offset from the scroller's content top to translate
  // scroll positions into visible rows.
  let containerEl: HTMLDivElement | null = $state(null);
  let scrollMargin = $state(0);

  // scrollMargin is the grid's offset from the scroller's content top. It is
  // computed on mount (one offset read, as TanStack's own docs prescribe) and
  // after layout-shifting changes: breakpoint swaps, row-height corrections
  // and any sibling grid changing its footprint (via gridLayoutVersion).
  // Never through a ResizeObserver on the virtual container or the page
  // content: their heights depend on the virtualizer, and observing them fed
  // layout changes back into it — the "ResizeObserver loop limit exceeded"
  // freeze.
  $effect(() => {
    const el = containerEl;
    if (!el || el.offsetParent === null || el.getClientRects().length === 0) return;
    columnsCount;
    gridLayoutVersion();
    const scroller = document.getElementById("main-scroll");
    if (!scroller) return;
    const margin = Math.max(
      0,
      Math.round(
        el.getBoundingClientRect().top - scroller.getBoundingClientRect().top + scroller.scrollTop,
      ),
    );
    if (margin !== untrack(() => scrollMargin)) {
      scrollMargin = margin;
    } else {
      virtualizerInstance?.setOptions({
        count: rows.length,
        scrollMargin: margin,
      });
    }
  });

  // A grid's footprint on the page (row count, corrected row height) shifts
  // every grid below it, so its own recompute is not enough: bump the shared
  // version and let sibling margins recompute. Also runs on unmount via
  // onDestroy below.
  $effect(() => {
    rowCount;
    rowHeight;
    bumpGridLayout();
  });

  onDestroy(() => bumpGridLayout());

  // $effect.pre: setOptions forces a store emit, so running it pre-render
  // keeps virtual items and `rows` consistent within a single flush.
  $effect.pre(() => {
    virtualizerInstance?.setOptions({
      count: rowCount,
      scrollMargin,
    });
  });

  // Row-height correction, once per breakpoint: the table seed paints the
  // first frame, then a ResizeObserver on the first rendered row replaces it
  // with the real height. The first row's height depends only on its card
  // content — never on the virtualizer — so this cannot loop; the callback
  // runs after layout, so there is no forced synchronous reflow and no
  // virtualizer.measure() anywhere on the mount path.
  $effect(() => {
    const el = containerEl;
    if (!el) return;
    columnsCount;
    rowCount;
    const firstRow = el.querySelector<HTMLDivElement>(":scope > div");
    if (!firstRow) return;
    const correctRowHeight = () => {
      const height = firstRow.getBoundingClientRect().height;
      if (height > 0 && Math.abs(height - rowHeight) > 0.5) {
        rowHeight = height;
        virtualizerInstance?.measure();
      }
    };
    const ro = new ResizeObserver(correctRowHeight);
    ro.observe(firstRow);
    return () => ro.disconnect();
  });
</script>

{#snippet card(item: MediaItem)}
  {@const timeHint = getTimeHint
    ? getTimeHint(item)
    : timeBudget
      ? (() => {
          const res = evaluateTimeFit(
            item,
            timeBudget,
            uiSettings.bookPageMinutes,
            uiSettings.mangaChapterMinutes,
            i18n.current,
          );
          return {
            label: res.sessionLabel,
            canFinishNow: res.canFinishNow,
          };
        })()
      : null}
  <div class="group relative min-w-0">
    <MediaCard
      {item}
      {timeHint}
      {showProgress}
      {onOpen}
      {onProgress}
      {onProgressCommitted}
      {onStatusChange}
      {onDelete}
      {onEdit}
      {onEpisodeStep}
    />
    {#if onRemoveFromList}
      <button
        type="button"
        class="absolute top-2 right-2 z-10 grid h-8 w-8 place-items-center rounded-lg border border-white/10 bg-black/75 text-white opacity-100 transition hover:bg-rose-500 sm:opacity-0 sm:group-hover:opacity-100"
        title={i18n.t.views.listRemoveItem}
        aria-label={i18n.t.views.listRemoveItem}
        onclick={(event) => {
          event.stopPropagation();
          void onRemoveFromList?.(item);
        }}
      >
        <X size={15} aria-hidden="true" />
      </button>
    {/if}
  </div>
{/snippet}

{#if loading || isInitialLoading}
  <div
    class="grid grid-cols-2 gap-4 sm:grid-cols-3 lg:grid-cols-4 xl:grid-cols-5 2xl:grid-cols-7"
    aria-hidden="true"
  >
    {#each Array(7) as _, index (index)}
      <div class="bg-card overflow-hidden rounded-lg">
        <div class="bg-card-hover aspect-[3/4] animate-pulse"></div>
        <div class="space-y-2 p-3.5">
          <div class="bg-canvas h-4 w-3/4 animate-pulse rounded"></div>
          <div class="bg-canvas h-3 w-1/2 animate-pulse rounded"></div>
        </div>
      </div>
    {/each}
  </div>
  <p class="sr-only" role="status">{i18n.t.common.loading}</p>
{:else if error}
  <div
    class="flex min-h-72 flex-col items-center justify-center gap-3 rounded-lg bg-rose-400/5 p-6 text-center"
  >
    <p class="text-sm text-rose-200" role="alert">{errorMessage(error)}</p>
    <button
      type="button"
      class="bg-accent hover:bg-accent-hover inline-flex items-center gap-2 rounded-md px-4 py-2 text-sm font-medium text-white transition"
      onclick={onRetry}><RefreshCw size={15} aria-hidden="true" />{i18n.t.common.retry}</button
    >
  </div>
{:else if items.length === 0 && !loading && !isInitialLoading}
  <div
    class="bg-surface flex min-h-72 flex-col items-center justify-center gap-3 rounded-lg p-6 text-center"
  >
    <div class="bg-card text-muted grid h-12 w-12 place-items-center rounded-lg">
      <Inbox size={22} aria-hidden="true" />
    </div>
    <div>
      <p class="text-ink font-semibold">{i18n.t.library.emptyTitle}</p>
      <p class="text-muted mt-1 max-w-sm text-sm">
        {i18n.t.library.emptyHint}
      </p>
    </div>
  </div>
{:else if shouldVirtualize}
  <div
    bind:this={containerEl}
    data-virtual-grid
    style="position: relative; height: {$virtualizer.getTotalSize()}px; width: 100%;"
  >
    {#each $virtualizer.getVirtualItems() as virtualRow (virtualRow.index)}
      {@const startIdx = virtualRow.index * columnsCount}
      <div
        style="position: absolute; top: 0; left: 0; width: 100%; transform: translateY({virtualRow.start -
          $virtualizer.options.scrollMargin}px); will-change: transform; contain: layout paint; contain: layout;"
        class="grid grid-cols-2 gap-4 sm:grid-cols-3 lg:grid-cols-4 xl:grid-cols-5 2xl:grid-cols-7"
      >
        {#each items.slice(startIdx, startIdx + columnsCount) as item (item.id)}
          {@render card(item)}
        {/each}
      </div>
    {/each}
  </div>
{:else}
  <div class="grid grid-cols-2 gap-4 sm:grid-cols-3 lg:grid-cols-4 xl:grid-cols-5 2xl:grid-cols-7">
    {#each items as item (item.id)}
      {@render card(item)}
    {/each}
  </div>
{/if}
