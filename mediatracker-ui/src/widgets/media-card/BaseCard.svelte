<script lang="ts">
  import type { Snippet } from "svelte";
  import { Trash2 } from "$shared/ui/Icons";
  import { errorMessage } from "$shared/api/api";
  import { i18n } from "$shared/i18n/index.svelte";
  import type { MediaItem, MediaStatus } from "$shared/types";
  import { SYNC_STATUS } from "$shared/types";
  import { schedulePrefetchMediaDetail } from "$features/prefetch-details/mediaDetailPrefetch";
  import MediaPoster from "$entities/media/ui/MediaPoster.svelte";
  import MediaScoreBadge from "$entities/media/ui/MediaScoreBadge.svelte";
  import MediaStatusBadge from "$entities/media/ui/MediaStatusBadge.svelte";
  import { createCardStatus } from "$features/change-status/statusController.svelte";
  import type { CardTimeHint } from "./cardTypes";

  interface Props {
    item: MediaItem;
    timeHint?: CardTimeHint | null;
    onOpen?: (item: MediaItem) => void;
    onStatusChange?: (item: MediaItem, newStatus: MediaStatus) => void;
    onProgressCommitted?: () => void;
    onDelete?: (item: MediaItem) => Promise<void>;
    /** Rendered below the poster: title, progress, type-specific controls. */
    children: Snippet;
  }

  let {
    item,
    timeHint,
    onOpen = () => {},
    onStatusChange,
    onProgressCommitted = () => {},
    onDelete,
    children,
  }: Props = $props();

  let deleteError = $state<unknown>(null);

  const status = createCardStatus({
    getItem: () => item,
    getOnStatusChange: () => onStatusChange,
    getOnProgressCommitted: () => onProgressCommitted,
  });

  function handleKeydown(event: KeyboardEvent) {
    if (event.target !== event.currentTarget) return;
    if (event.key === "Enter" || event.key === " ") {
      event.preventDefault();
      onOpen(item);
    }
  }

  async function removeItem() {
    if (!onDelete || !window.confirm(i18n.t.card.confirmDelete(item.title))) return;

    deleteError = null;
    try {
      await onDelete(item);
    } catch (error) {
      deleteError = error;
    }
  }
</script>

<!-- svelte-ignore a11y_click_events_have_key_events -->
<!-- svelte-ignore a11y_no_noninteractive_element_interactions -->
<article
  class="media-card group bg-card hover:bg-card-hover relative cursor-pointer rounded-xl border border-white/[0.05] p-2.5 shadow-lg focus-within:ring-2 focus-within:ring-indigo-500/30 hover:border-white/[0.1]"
  onclick={(event) => {
    if ((event.target as HTMLElement).closest("button, a, input, select")) return;
    onOpen(item);
  }}
  onpointerenter={() => schedulePrefetchMediaDetail(item.id)}
  onfocus={() => schedulePrefetchMediaDetail(item.id)}
>
  <MediaPoster
    src={item.coverUrl}
    alt={item.title}
    syncing={item.syncStatus === SYNC_STATUS.syncing}
    needsReview={item.syncStatus === SYNC_STATUS.needsReview}
  >
    {#snippet badges()}
      <MediaStatusBadge
        id={`status-${item.id}`}
        status={item.status}
        onSelect={(next) => void status.changeStatus(next)}
      />
      <MediaScoreBadge score={item.score} />
    {/snippet}

    {#if onDelete}
      {#snippet actions()}
        <button
          type="button"
          class="tap grid h-7 w-7 cursor-pointer place-items-center rounded-full border border-white/[0.06] bg-black/80 text-white/70 opacity-0 shadow-md transition group-hover:opacity-100 hover:border-rose-500/40 hover:bg-rose-600 hover:text-white focus:opacity-100"
          aria-label={i18n.t.card.deleteAria(item.title)}
          onclick={(event) => {
            event.stopPropagation();
            void removeItem();
          }}
        >
          <Trash2 size={14} aria-hidden="true" />
        </button>
      {/snippet}
    {/if}
  </MediaPoster>

  <div class="relative z-10 min-w-0 space-y-2.5 px-0.5 pt-3 pb-1">
    {#if timeHint}
      <div class="flex items-center">
        <span
          class={`inline-flex max-w-full items-center gap-1 truncate rounded-md border px-2 py-0.5 text-[11px] ${
            timeHint.canFinishNow
              ? "border border-emerald-400/40 bg-emerald-500/20 font-semibold text-emerald-300"
              : "bg-accent/20 border-accent/30 text-accent-soft border font-medium"
          }`}
          title={timeHint.label}
        >
          {timeHint.label}
        </span>
      </div>
    {/if}

    {@render children()}

    {#if deleteError}
      <p class="text-xs leading-4 text-rose-300" role="alert">
        {errorMessage(deleteError)}
      </p>
    {/if}
  </div>
</article>
