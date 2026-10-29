<script lang="ts">
  import { History, LoaderCircle, RefreshCw, X, Trash2 } from "$shared/ui/Icons";
  import Modal from "$shared/ui/Modal.svelte";
  import { deleteHistoryEvent, errorMessage, getHistoryEvents } from "$shared/api/api";
  import { showToast } from "$shared/ui/toast.svelte";
  import { i18n } from "$shared/i18n/index.svelte";
  import type { HistoryEvent } from "$shared/types";
  import {
    formatHistoryDate,
    formatHistoryEventLabel,
    formatHistoryTime,
    HISTORY_EVENT_ICONS,
  } from "$shared/utils/historyFormatters";

  interface Props {
    isOpen: boolean;
    mediaId: string;
    title: string;
    onClose: () => void;
  }

  let { isOpen, mediaId, title, onClose }: Props = $props();

  let selectedDate = $state("");
  let events = $state.raw<HistoryEvent[]>([]);
  let loading = $state(false);
  let loadError = $state<unknown>(null);
  let deletingId = $state<string | null>(null);
  let requestSequence = 0;

  $effect(() => {
    if (!isOpen || !mediaId) {
      return;
    }
    void loadEvents(++requestSequence);
  });

  async function loadEvents(sequence: number) {
    loading = true;
    loadError = null;

    try {
      const nextEvents = await getHistoryEvents({
        mediaId,
        date: selectedDate || undefined,
      });
      if (sequence === requestSequence) {
        events = nextEvents;
      }
    } catch (error) {
      if (sequence === requestSequence) {
        loadError = error;
      }
    } finally {
      if (sequence === requestSequence) {
        loading = false;
      }
    }
  }

  function retry() {
    void loadEvents(++requestSequence);
  }

  async function handleDeleteEvent(event: HistoryEvent) {
    if (deletingId !== null) return;
    if (!window.confirm(i18n.t.views.confirmDeleteHistoryEntry)) return;

    deletingId = event.id;
    const prevEvents = events;
    events = events.filter((x) => x.id !== event.id);

    try {
      await deleteHistoryEvent(event.id);
      showToast(i18n.t.views.historyEntryDeleted, "success");
    } catch (err) {
      events = prevEvents;
      showToast(errorMessage(err), "error");
    } finally {
      deletingId = null;
    }
  }
</script>

<Modal {isOpen} {onClose} labelledBy="media-activity-title">
  <div class="flex max-h-[75vh] flex-col">
    <header class="flex shrink-0 items-center gap-3 border-b border-white/[0.08] px-5 py-4">
      <History size={18} class="shrink-0 text-[var(--color-accent-soft)]" aria-hidden="true" />
      <div class="min-w-0 flex-1">
        <h2 id="media-activity-title" class="text-sm font-bold text-white">
          {i18n.t.views.historyTitle}
        </h2>
        <p class="text-muted truncate text-xs">
          {title}
        </p>
      </div>
      <button
        type="button"
        class="text-muted ml-auto shrink-0 cursor-pointer rounded-md p-1.5 transition hover:bg-white/5 hover:text-white"
        aria-label={i18n.t.common.close}
        onclick={onClose}
      >
        <X size={16} aria-hidden="true" />
      </button>
    </header>

    <!-- Date filter bar -->
    <div
      class="bg-surface/30 flex shrink-0 flex-wrap items-center justify-between gap-3 border-b border-white/[0.08] px-5 py-3"
    >
      <div class="flex items-center gap-2">
        <span class="text-muted text-xs font-medium">{i18n.t.views.filterByDate}:</span>
        <input
          type="date"
          bind:value={selectedDate}
          class="bg-field focus:border-accent focus:ring-accent cursor-pointer rounded-lg border border-white/10 px-3 py-1.5 text-xs text-white transition outline-none focus:ring-1"
        />
        {#if selectedDate}
          <button
            type="button"
            class="bg-field text-muted cursor-pointer rounded-lg border border-white/10 px-2.5 py-1.5 text-xs transition hover:text-white"
            onclick={() => (selectedDate = "")}
          >
            {i18n.t.views.resetDate}
          </button>
        {/if}
      </div>
    </div>

    <!-- Activity list -->
    <div class="min-h-[220px] flex-1 overflow-y-auto p-5">
      {#if loading}
        <div class="space-y-3" aria-hidden="true">
          {#each Array(3) as _, index (index)}
            <div class="bg-card h-14 animate-pulse rounded-lg"></div>
          {/each}
        </div>
        <p class="sr-only" role="status">{i18n.t.common.loading}</p>
      {:else if loadError}
        <div
          class="flex min-h-48 flex-col items-center justify-center gap-3 rounded-lg bg-rose-400/5 p-6 text-center"
        >
          <p class="text-sm text-rose-200" role="alert">
            {errorMessage(loadError)}
          </p>
          <button
            type="button"
            class="bg-accent hover:bg-accent-hover inline-flex cursor-pointer items-center gap-2 rounded-md px-4 py-2 text-xs font-medium text-white transition"
            onclick={retry}
          >
            <RefreshCw size={14} aria-hidden="true" />
            {i18n.t.common.retry}
          </button>
        </div>
      {:else if events.length === 0}
        <div
          class="bg-surface/50 flex min-h-48 flex-col items-center justify-center gap-3 rounded-lg p-6 text-center"
        >
          <div class="bg-card text-muted grid h-10 w-10 place-items-center rounded-lg">
            <History size={20} aria-hidden="true" />
          </div>
          <p class="text-muted text-xs">
            {selectedDate ? i18n.t.views.noActivityForDate : i18n.t.views.noActivity}
          </p>
        </div>
      {:else}
        <ol class="space-y-2.5">
          {#each events as event (event.id)}
            {@const Icon = HISTORY_EVENT_ICONS[event.type] ?? History}
            <li
              class="group/item bg-card/60 hover:bg-card flex items-center gap-3.5 rounded-lg border border-white/5 p-3 transition"
            >
              <div
                class="bg-accent/15 text-accent-soft grid h-9 w-9 shrink-0 place-items-center rounded-md"
              >
                <Icon size={16} aria-hidden="true" />
              </div>
              <div class="min-w-0 flex-1">
                <p class="text-ink text-xs font-semibold">
                  {formatHistoryEventLabel(event)}
                </p>
                <p class="text-muted mt-0.5 flex items-center gap-1.5 text-[11px]">
                  <span class="font-medium text-white/80 tabular-nums"
                    >{formatHistoryTime(event.createdAt)}</span
                  >
                  <span>·</span>
                  <span>{formatHistoryDate(event.createdAt)}</span>
                </p>
              </div>
              <button
                type="button"
                class="text-muted grid h-7 w-7 shrink-0 cursor-pointer place-items-center rounded-md opacity-0 transition group-hover/item:opacity-100 hover:bg-rose-500/10 hover:text-rose-400 focus-visible:opacity-100 disabled:opacity-40"
                disabled={deletingId !== null}
                aria-label={i18n.t.views.confirmDeleteHistoryEntry}
                title={i18n.t.views.confirmDeleteHistoryEntry}
                onclick={() => void handleDeleteEvent(event)}
              >
                {#if deletingId === event.id}
                  <LoaderCircle size={13} class="animate-spin" aria-hidden="true" />
                {:else}
                  <Trash2 size={13} aria-hidden="true" />
                {/if}
              </button>
            </li>
          {/each}
        </ol>
      {/if}
    </div>
  </div>
</Modal>
