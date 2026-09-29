<script lang="ts">
  import {
    Bookmark,
    Check,
    ChevronDown,
    Image as ImageIcon,
    Minus,
    Pause,
    Play,
    Plus,
    Trash2,
    X,
  } from "lucide-svelte";
  import { untrack } from "svelte";
  import { errorMessage, updateStatus } from "$lib/api";
  import { i18n } from "$lib/i18n/index.svelte";
  import {
    clampProgress,
    MEDIA_STATUS,
    type MediaItem,
    type MediaStatus,
  } from "$lib/types";
  import { createProgressDebounce } from "$lib/utils/progressDebounce";

  interface Props {
    item: MediaItem;
    onOpen?: (item: MediaItem) => void;
    onProgress?: (id: string, currentProgress: number) => Promise<void>;
    onProgressCommitted?: () => void;
    onStatusChange?: (item: MediaItem, newStatus: MediaStatus) => void;
    onDelete?: (item: MediaItem) => Promise<void>;
    onEdit?: (item: MediaItem) => void;
    onEpisodeStep?: (item: MediaItem, delta: number) => Promise<void>;
  }

  let {
    item,
    onOpen = () => {},
    onProgress,
    onProgressCommitted = () => {},
    onStatusChange,
    onDelete,
    onEdit = () => {},
    onEpisodeStep,
  }: Props = $props();

  let trackedItem: MediaItem | null = null;
  let currentProgress = $state(untrack(() => readProgress(item)));
  let committedProgress = $state(untrack(() => currentProgress));
  let pendingSnapshot = $state<number | null>(null);

  let progressError = $state<unknown>(null);
  let deleteError = $state<unknown>(null);

  let statusMenuOpen = $state(false);

  const statusOptions: readonly MediaStatus[] = [
    MEDIA_STATUS.planned,
    MEDIA_STATUS.inProgress,
    MEDIA_STATUS.completed,
    MEDIA_STATUS.onHold,
    MEDIA_STATUS.dropped,
  ];

  async function changeStatus(newStatus: MediaStatus) {
    statusMenuOpen = false;
    const prevStatus = item.status;
    item.status = newStatus;
    if (onStatusChange) {
      onStatusChange(item, newStatus);
    }
    try {
      await updateStatus(item.id, newStatus);
      onProgressCommitted();
    } catch (e) {
      item.status = prevStatus;
      if (onStatusChange) {
        onStatusChange(item, prevStatus);
      }
      console.error(e);
    }
  }

  function handleWindowPointerDown(event: PointerEvent) {
    if (!statusMenuOpen) return;
    const target = event.target as HTMLElement;
    if (!target.closest("[data-status-menu]")) {
      statusMenuOpen = false;
    }
  }
  const progressDebounce = createProgressDebounce({
    send: (id, value) => (onProgress ?? (async () => {}))(id, value),
    buildRequest: (id, value) => ({
      url: `/api/media/${id}/progress`,
      body: { currentProgress: value },
    }),
    onCommitted: (value) => {
      committedProgress = value;
      if (currentProgress === value) onProgressCommitted();
    },
    onError: (error) => {
      currentProgress = pendingSnapshot ?? committedProgress;
      committedProgress = currentProgress;
      pendingSnapshot = null;
      progressError = error;
    },
  });

  $effect(() => {
    if (item !== trackedItem) {
      trackedItem = item;
      currentProgress = readProgress(item);
      committedProgress = currentProgress;
      pendingSnapshot = null;
    }
  });

  $effect(() => {
    return () => void progressDebounce.flush(true);
  });

  function readProgress(media: MediaItem): number {
    switch (media.type) {
      case "game":
        return media.hoursPlayed ?? 0;
      case "book":
        return media.currentPage;
      case "manga":
        return media.currentChapter;
      default:
        return 0;
    }
  }

  function totalForProgress(media: MediaItem): number | null {
    switch (media.type) {
      case "book":
        return media.totalPages;
      case "manga":
        return media.totalChapters;
      default:
        return null;
    }
  }

  function statusLabel(status: MediaStatus): string {
    switch (status) {
      case 0:
        return i18n.t.status.planned;
      case 1:
        return i18n.t.status.inProgress;
      case 2:
        return i18n.t.status.completed;
      case 3:
        return i18n.t.status.paused;
      case 4:
        return i18n.t.status.dropped;
    }
  }

  function statusBadgeClasses(status: MediaStatus): string {
    switch (status) {
      case 2: // Completed (Green circle with lighter green ring like in the image)
        return "bg-[#22c55e] text-white border-2 border-[#86efac]/80 ring-2 ring-[#86efac]/30";
      case 1: // In progress (Blue)
        return "bg-[#2563eb] text-white border-2 border-[#93c5fd]/80 ring-2 ring-[#93c5fd]/30";
      case 3: // On hold (Amber)
        return "bg-[#d97706] text-white border-2 border-amber-300/80 ring-2 ring-amber-300/30";
      case 4: // Dropped (Rose)
        return "bg-[#dc2626] text-white border-2 border-rose-300/80 ring-2 ring-rose-300/30";
      default: // Planned (Slate)
        return "bg-[#334155] text-slate-100 border-2 border-slate-400/70 ring-2 ring-slate-400/20";
    }
  }

  function format(value: number): string {
    return new Intl.NumberFormat(i18n.current).format(value);
  }

  function cardTypeLabel(media: MediaItem): string {
    if (media.type === "tvshow" && media.isAnime) {
      return i18n.t.navigation.anime;
    }

    return i18n.t.types[media.type];
  }

  function progressLabel(media: MediaItem): string | null {
    switch (media.type) {
      case "game":
        return i18n.t.card.hours(currentProgress);
      case "book":
        return i18n.t.card.pages(currentProgress, media.totalPages);
      case "manga":
        return i18n.t.card.chapters(currentProgress, media.totalChapters);
      case "movie":
        return i18n.t.card.movie(media.durationMinutes);
      case "tvshow":
        return i18n.t.card.episodes(
          media.totalEpisodesWatched,
          media.totalEpisodesCount,
        );
    }
  }

  function progressRatio(media: MediaItem): number | null {
    const total =
      media.type === "tvshow"
        ? media.totalEpisodesCount
        : totalForProgress(media);
    const current =
      media.type === "tvshow" ? media.totalEpisodesWatched : currentProgress;

    return total !== null && total > 0 ? Math.min(current / total, 1) : null;
  }

  function scheduleProgress(delta: number) {
    if (!onProgress || !supportsStepper(item)) return;

    const next = clampProgress(currentProgress + delta, totalForProgress(item));
    if (next === currentProgress) return;

    if (pendingSnapshot === null) {
      pendingSnapshot = committedProgress;
    }

    currentProgress = next;
    progressError = null;
    progressDebounce.schedule(item.id, next);
  }

  function handleCardKeydown(event: KeyboardEvent) {
    if (event.target !== event.currentTarget) return;

    if (event.key === "Enter" || event.key === " ") {
      event.preventDefault();
      onOpen(item);
    }
  }

  function supportsStepper(media: MediaItem): boolean {
    if (media.status !== MEDIA_STATUS.inProgress) return false;
    return (
      media.type === "game" || media.type === "book" || media.type === "manga"
    );
  }

  async function stepEpisode(delta: number) {
    if (!onEpisodeStep || item.type !== "tvshow") return;
    await onEpisodeStep(item, delta);
  }

  async function removeItem() {
    if (!onDelete || !window.confirm(i18n.t.card.confirmDelete(item.title)))
      return;

    deleteError = null;

    try {
      await onDelete(item);
    } catch (error) {
      deleteError = error;
    }
  }
</script>

<svelte:window onpointerdown={handleWindowPointerDown} />

<!-- svelte-ignore a11y_no_noninteractive_element_to_interactive_role -->
<article
  class="group relative cursor-pointer overflow-hidden rounded-lg bg-card transition hover:bg-card-hover"
  style="content-visibility: auto; contain-intrinsic-size: auto none;"
  role="button"
  tabindex="0"
  aria-label={i18n.t.card.openDetails(item.title)}
  onclick={() => onOpen(item)}
  onkeydown={handleCardKeydown}
>
  <div class="aspect-[3/4] overflow-hidden bg-canvas">
    {#if item.coverUrl}
      <img
        src={item.coverUrl}
        alt={item.title}
        class="h-full w-full object-cover transition duration-500 group-hover:scale-[1.03]"
        loading="lazy"
      />
    {:else}
      <div
        class="flex h-full items-center justify-center bg-gradient-to-br from-panel to-elevated text-muted"
      >
        <ImageIcon size={38} stroke-width={1.25} aria-hidden="true" />
      </div>
    {/if}

    <div
      class="absolute inset-x-0 top-0 flex items-start justify-between gap-2 p-3"
    >
      <div class="relative flex items-center" data-status-menu>
        <!-- Status Button (Left, z-10) -->
        <button
          type="button"
          class={`relative z-10 flex h-8 w-8 items-center justify-center rounded-full shadow-lg backdrop-blur transition hover:scale-105 active:scale-95 cursor-pointer ${statusBadgeClasses(item.status)}`}
          onclick={(e) => {
            e.stopPropagation();
            statusMenuOpen = !statusMenuOpen;
          }}
          title={statusLabel(item.status)}
          aria-label={statusLabel(item.status)}
        >
          {#if item.status === 0}
            <Bookmark size={14} stroke-width={2.2} />
          {:else if item.status === 1}
            <Play size={13} fill="currentColor" class="translate-x-0.5" />
          {:else if item.status === 2}
            <Check size={16} stroke-width={3} />
          {:else if item.status === 3}
            <Pause size={13} stroke-width={2.5} />
          {:else if item.status === 4}
            <X size={14} stroke-width={2.5} />
          {/if}
        </button>

        <!-- Rating Circle (Right, overlaid on top with z-20 and -ml-2.5) -->
        {#if item.score !== null && item.score > 0}
          <div
            class="relative z-20 -ml-2.5 flex h-8 w-8 items-center justify-center rounded-full bg-[#2a3cb8] text-white shadow-lg border-2 border-[#7786ee]/80 ring-2 ring-[#7786ee]/30 font-black text-xs sm:text-sm tracking-tight select-none"
            title={`${i18n.t.createModal.fields.score}: ${item.score}`}
          >
            {format(item.score)}
          </div>
        {/if}

        {#if statusMenuOpen}
          <!-- svelte-ignore a11y_no_static_element_interactions a11y_interactive_supports_focus a11y_click_events_have_key_events -->
          <div
            class="absolute left-0 top-full mt-2 w-36 overflow-hidden rounded-md border border-white/10 bg-[#222634] py-1 shadow-xl z-30"
            role="listbox"
            tabindex="-1"
            onclick={(e) => e.stopPropagation()}
            onpointerdown={(e) => e.stopPropagation()}
            onkeydown={(e) => e.stopPropagation()}
          >
            {#each statusOptions as option}
              <button
                type="button"
                class={`flex w-full items-center justify-between px-3 py-2 text-left text-sm transition hover:bg-white/5 cursor-pointer ${option === item.status ? "text-accent-soft" : "text-muted"}`}
                onclick={(e) => {
                  e.stopPropagation();
                  changeStatus(option);
                }}
              >
                {statusLabel(option)}
                {#if option === item.status}
                  <Check size={14} class="text-accent-soft" />
                {/if}
              </button>
            {/each}
          </div>
        {/if}
      </div>

      <div class="flex gap-1">
        <button
          type="button"
          class="flex h-8 w-8 items-center justify-center rounded-md bg-black/60 backdrop-blur-md text-white/70 opacity-0 shadow-md transition hover:bg-rose-600 hover:text-white hover:scale-105 focus:opacity-100 group-hover:opacity-100 cursor-pointer"
          aria-label={i18n.t.card.deleteAria(item.title)}
          onclick={(event) => {
            event.stopPropagation();
            void removeItem();
          }}
        >
          <Trash2 size={15} aria-hidden="true" />
        </button>
      </div>
    </div>
  </div>

  <div class="relative z-10 min-w-0 space-y-3 p-3.5">
    <div class="min-w-0">
      <h2
        class="truncate break-words text-sm font-semibold text-ink"
        title={item.title.length > 100
          ? item.title.slice(0, 97) + "..."
          : item.title}
      >
        {item.title}
      </h2>
      <p class="mt-1 truncate text-xs text-muted">
        {cardTypeLabel(item)}
        {#if item.type === "game" && item.platform}
          · {item.platform}
        {:else if item.type === "book" && item.author}
          · {item.author}
        {:else if item.type === "tvshow" && item.seasonsCount > 0}
          · {item.seasonsCount}
        {/if}
      </p>
    </div>

    {#if progressLabel(item)}
      <div class="space-y-1.5">
        <div class="flex items-center justify-between gap-2 text-xs text-muted">
          <span>{progressLabel(item)}</span>
        </div>
        {#if progressRatio(item) !== null}
          <div class="h-1.5 overflow-hidden rounded-full bg-canvas">
            <div
              class="h-full rounded-full bg-accent transition-[width] duration-200"
              style={`width: ${progressRatio(item)! * 100}%`}
            ></div>
          </div>
        {:else if supportsStepper(item)}
          <div class="h-1.5" aria-hidden="true"></div>
        {/if}
      </div>
    {/if}

    {#if supportsStepper(item)}
      <div class="flex h-8 items-center rounded-md bg-canvas">
        <button
          type="button"
          class="grid h-full w-8 place-items-center rounded-l-md text-muted transition hover:bg-panel hover:text-ink"
          aria-label={i18n.t.card.decrement}
          onclick={(event) => {
            event.stopPropagation();
            scheduleProgress(-1);
          }}><Minus size={14} aria-hidden="true" /></button
        >
        <span
          class="flex-1 text-center text-xs font-semibold tabular-nums text-ink"
          >{format(currentProgress)}</span
        >
        <button
          type="button"
          class="grid h-full w-8 place-items-center rounded-r-md text-muted transition hover:bg-panel hover:text-ink"
          aria-label={i18n.t.card.increment}
          onclick={(event) => {
            event.stopPropagation();
            scheduleProgress(1);
          }}><Plus size={14} aria-hidden="true" /></button
        >
      </div>
    {/if}

    {#if item.type === "tvshow" && onEpisodeStep && item.status === MEDIA_STATUS.inProgress && item.totalEpisodesCount !== 1}
      <div class="flex h-8 items-center rounded-md bg-canvas">
        <button
          type="button"
          class="grid h-full w-8 place-items-center rounded-l-md text-muted transition hover:bg-panel hover:text-ink disabled:opacity-40"
          aria-label={i18n.t.card.decrement}
          disabled={item.totalEpisodesWatched <= 0}
          onclick={(event) => {
            event.stopPropagation();
            void stepEpisode(-1);
          }}><Minus size={14} aria-hidden="true" /></button
        >
        <span class="flex-1 text-center text-xs font-semibold tabular-nums text-ink">
          {item.totalEpisodesWatched}{item.totalEpisodesCount > 0 ? ` / ${item.totalEpisodesCount}` : ''}
        </span>
        <button
          type="button"
          class="grid h-full w-8 place-items-center rounded-r-md text-muted transition hover:bg-panel hover:text-ink disabled:opacity-40"
          aria-label={i18n.t.card.increment}
          disabled={item.totalEpisodesCount > 0 && item.totalEpisodesWatched >= item.totalEpisodesCount}
          onclick={(event) => {
            event.stopPropagation();
            void stepEpisode(1);
          }}><Plus size={14} aria-hidden="true" /></button
        >
      </div>
    {/if}

    {#if progressError}
      <p class="text-xs leading-4 text-rose-300" role="alert">
        {errorMessage(progressError)}
      </p>
    {/if}
    {#if deleteError}
      <p class="text-xs leading-4 text-rose-300" role="alert">
        {errorMessage(deleteError)}
      </p>
    {/if}
  </div>
</article>
