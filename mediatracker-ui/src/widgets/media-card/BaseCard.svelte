<script lang="ts">
  import type { Snippet } from "svelte";
  import { Trash2 } from "$shared/ui/Icons";
  import { errorMessage } from "$shared/api/api";
  import { showToast } from "$shared/ui/toast.svelte";
  import { i18n } from "$shared/i18n/index.svelte";
  import type { MediaItem, MediaStatus } from "$shared/types";
  import { SYNC_STATUS } from "$shared/types";
  import { schedulePrefetchMediaDetail } from "$features/prefetch-details/mediaDetailPrefetch";
  import type { MenuItem } from "$shared/ui/contextMenu.svelte";
  import { openContextMenu, openListPicker } from "$shared/ui/contextMenu.svelte";
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
    onEdit?: (item: MediaItem) => void;
    /** Rendered below the poster: title, progress, type-specific controls. */
    children: Snippet;
    /** Hover layer swapped in over `children` (stepper / quick actions). */
    hover?: Snippet;
  }

  let {
    item,
    timeHint,
    onOpen = () => {},
    onStatusChange,
    onProgressCommitted = () => {},
    onDelete,
    onEdit,
    children,
    hover,
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

  function buildCardMenuItems(item: MediaItem): MenuItem[] {
    const statusLabel = (status: MediaStatus): string => {
      const map: Record<MediaStatus, keyof typeof i18n.t.status> = {
        0: 'planned',
        1: 'inProgress',
        2: 'completed',
        3: 'paused',
        4: 'dropped',
      };
      return i18n.t.status[map[status]];
    };

    return [
      {
        id: 'edit',
        label: i18n.t.detailModal.edit,
        icon: 'edit',
        kind: 'default',
        action: () => (onEdit ? onEdit(item) : onOpen?.(item)),
      },
      {
        id: 'status',
        label: i18n.t.status.label,
        icon: 'status',
        kind: 'default',
        children: [
          { id: 'status-planned', label: statusLabel(0), kind: 'default', action: () => onStatusChange?.(item, 0) },
          { id: 'status-inProgress', label: statusLabel(1), kind: 'default', action: () => onStatusChange?.(item, 1) },
          { id: 'status-completed', label: statusLabel(2), kind: 'default', action: () => onStatusChange?.(item, 2) },
          { id: 'status-dropped', label: statusLabel(4), kind: 'default', action: () => onStatusChange?.(item, 4) },
        ],
      },
      {
        id: 'add-to-list',
        label: i18n.t.views.listAddTo,
        icon: 'list',
        kind: 'default',
        action: () => openListPicker(item.id),
      },
      {
        id: 'copy-title',
        label: i18n.t.contextMenu.copyTitle ?? i18n.t.common.copy,
        icon: 'copy',
        kind: 'default',
        action: () => {
          navigator.clipboard.writeText(item.title).catch(() => {});
          showToast(i18n.t.common.copied);
        },
      },
      { id: 'separator1', kind: 'separator' },
      {
        id: 'delete',
        label: i18n.t.detailModal.delete,
        icon: 'delete',
        kind: 'danger',
        action: async () => {
          if (!onDelete) return;
          if (!window.confirm(i18n.t.card.confirmDelete(item.title))) return;
          await onDelete(item);
        },
      },
    ];
  }
</script>

<!-- svelte-ignore a11y_click_events_have_key_events -->
<!-- svelte-ignore a11y_no_noninteractive_element_interactions -->
<article
  class="media-card group bg-card hover:bg-card-hover relative cursor-pointer rounded-xl border border-white/[0.05] p-2.5 shadow-lg focus-within:ring-2 focus-within:ring-indigo-500/30 hover:border-white/[0.1]"
  data-id={item.id}
  onclick={(event) => {
    if ((event.target as HTMLElement).closest("button, a, input, select")) return;
    onOpen(item);
  }}
  oncontextmenu={(event) => {
    const selection = window.getSelection()?.toString()?.trim();
    if (selection) return;
    event.preventDefault();
    event.stopPropagation();
    const items = buildCardMenuItems(item);
    openContextMenu(event.clientX, event.clientY, items);
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

  <div class="relative z-10 min-w-0 px-0.5 pt-2.5">
    {#if timeHint}
      <div class="flex items-center pb-2">
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

    <!-- Fixed-height info section: two swapped layers keep every card the
         exact same height regardless of status or content length. -->
    <div class="relative h-[70px] min-w-0">
      <!-- Layer A: default info, fades out on hover. invisible + pointer-events
           make sure it can never bleed under the hover controls. The
           focus-within swap mirrors Layer B exactly: the two layers are
           strictly exclusive, so neither can end up hidden while the other
           is not showing. -->
      <div
        class="pointer-events-auto h-full space-y-1.5 opacity-100 transition-opacity duration-150 group-focus-within:pointer-events-none group-focus-within:invisible group-focus-within:opacity-0 group-hover:pointer-events-none group-hover:invisible group-hover:opacity-0"
      >
        {@render children()}
      </div>

      <!-- Layer B: hover actions, fade in on hover or keyboard focus -->
      {#if hover}
        <div
          class="pointer-events-none absolute inset-0 flex items-center justify-between opacity-0 transition-opacity duration-150 group-focus-within:pointer-events-auto group-focus-within:opacity-100 group-hover:pointer-events-auto group-hover:opacity-100"
        >
          {@render hover()}
        </div>
      {/if}
    </div>

    {#if deleteError}
      <p class="text-xs leading-4 text-rose-300" role="alert">
        {errorMessage(deleteError)}
      </p>
    {/if}
  </div>
</article>
