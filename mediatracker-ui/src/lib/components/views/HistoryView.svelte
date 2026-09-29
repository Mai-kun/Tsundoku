<script lang="ts">
  import { Flag, History, RefreshCw, Trash2 } from 'lucide-svelte'
  import { clearAllHistory, deleteHistoryEntry, errorMessage, getMedia } from '$lib/api'
  import { showToast } from '$lib/stores/toast.svelte'
  import { i18n } from '$lib/i18n/index.svelte'

  interface HistoryEvent {
    key: string
    mediaId: string
    title: string
    date: string
    kind: 'started' | 'finished'
  }

  interface Props {
    refreshKey: number
  }

  let { refreshKey }: Props = $props()

  let events = $state<HistoryEvent[]>([])
  let loading = $state(true)
  let loadError = $state<unknown>(null)
  let clearing = $state(false)
  let requestSequence = 0

  $effect(() => {
    void refreshKey
    void loadEvents(++requestSequence)
  })

  async function loadEvents(sequence: number) {
    loading = true
    loadError = null

    try {
      const items = await getMedia()
      const nextEvents = items
        .flatMap((item): HistoryEvent[] => [
          ...(item.startedAt ? [{ key: `${item.id}:started`, mediaId: item.id, title: item.title, date: item.startedAt, kind: 'started' as const }] : []),
          ...(item.finishedAt ? [{ key: `${item.id}:finished`, mediaId: item.id, title: item.title, date: item.finishedAt, kind: 'finished' as const }] : []),
        ])
        .sort((left, right) => {
          const diff = Date.parse(right.date) - Date.parse(left.date)
          if (diff !== 0) return diff
          if (left.kind === 'finished' && right.kind === 'started') return -1
          if (left.kind === 'started' && right.kind === 'finished') return 1
          return 0
        })

      if (sequence === requestSequence) {
        events = nextEvents
      }
    } catch (error) {
      if (sequence === requestSequence) {
        loadError = error
      }
    } finally {
      if (sequence === requestSequence) {
        loading = false
      }
    }
  }

  function retry() {
    void loadEvents(++requestSequence)
  }

  function formatDate(value: string): string {
    return new Intl.DateTimeFormat(i18n.current, { dateStyle: 'medium' }).format(new Date(value))
  }

  async function removeEvent(event: HistoryEvent) {
    if (!window.confirm(i18n.t.views.confirmDeleteHistoryEntry)) return

    const prevEvents = events
    events = events.filter((e) => e.key !== event.key)

    try {
      await deleteHistoryEntry(event.mediaId, event.kind)
      showToast(i18n.t.views.historyEntryDeleted, 'success')
    } catch (err) {
      events = prevEvents
      showToast(errorMessage(err), 'error')
    }
  }

  async function handleClearAll() {
    if (events.length === 0) return
    if (!window.confirm(i18n.t.views.confirmClearHistory)) return

    clearing = true
    const prevEvents = events
    events = []

    try {
      await clearAllHistory()
      showToast(i18n.t.views.historyCleared, 'success')
    } catch (err) {
      events = prevEvents
      showToast(errorMessage(err), 'error')
    } finally {
      clearing = false
    }
  }
</script>

<div class="mx-auto max-w-4xl space-y-6">
  <div class="flex flex-wrap items-end justify-between gap-4">
    <div>
      <p class="text-xs font-semibold uppercase tracking-[0.18em] text-accent-soft">{i18n.t.library.collectionLabel}</p>
      <h2 class="mt-1 text-2xl font-bold tracking-tight text-ink">{i18n.t.views.historyTitle}</h2>
      <p class="mt-2 text-sm text-muted">{i18n.t.views.historyHint}</p>
    </div>

    {#if events.length > 0}
      <button
        type="button"
        class="inline-flex items-center gap-1.5 rounded-md border border-border bg-card px-3 py-1.5 text-xs font-semibold text-rose-400 transition hover:bg-rose-500/10 hover:border-rose-500/40 cursor-pointer disabled:opacity-50"
        disabled={clearing}
        onclick={handleClearAll}
      >
        <Trash2 size={13} />
        <span>{i18n.t.views.clearHistory}</span>
      </button>
    {/if}
  </div>

  {#if loading}
    <div class="space-y-3" aria-hidden="true">{#each Array(4) as _, index (index)}<div class="h-16 animate-pulse rounded-lg bg-card"></div>{/each}</div>
    <p class="sr-only" role="status">{i18n.t.common.loading}</p>
  {:else if loadError}
    <div class="flex min-h-72 flex-col items-center justify-center gap-3 rounded-lg bg-rose-400/5 p-6 text-center"><p class="text-sm text-rose-200" role="alert">{errorMessage(loadError)}</p><button type="button" class="inline-flex items-center gap-2 rounded-md bg-accent px-4 py-2 text-sm font-medium text-white transition hover:bg-accent-hover" onclick={retry}><RefreshCw size={15} aria-hidden="true" />{i18n.t.common.retry}</button></div>
  {:else if events.length === 0}
    <div class="flex min-h-72 flex-col items-center justify-center gap-3 rounded-lg bg-surface p-6 text-center"><div class="grid h-12 w-12 place-items-center rounded-lg bg-card text-muted"><History size={22} aria-hidden="true" /></div><p class="text-sm text-muted">{i18n.t.common.noData}</p></div>
  {:else}
    <ol class="space-y-3">
      {#each events as event (event.key)}
        <li class="flex items-center gap-4 rounded-lg bg-card p-4 transition hover:bg-card/80">
          <div class={`grid h-10 w-10 shrink-0 place-items-center rounded-md ${event.kind === 'finished' ? 'bg-accent/15 text-accent-soft' : 'bg-star/15 text-star'}`}><Flag size={17} aria-hidden="true" /></div>
          <div class="min-w-0 flex-1">
            <p class="truncate text-sm font-semibold text-ink">{event.title}</p>
            <p class="mt-1 text-xs text-muted">{formatDate(event.date)}</p>
          </div>
          <span class="rounded bg-canvas px-2 py-0.5 text-xs font-semibold text-muted">{event.kind === 'started' ? i18n.t.status.inProgress : i18n.t.status.completed}</span>
          <button
            type="button"
            class="grid h-8 w-8 place-items-center rounded-md text-muted transition hover:bg-rose-500/15 hover:text-rose-400 cursor-pointer"
            title={i18n.t.common.delete}
            aria-label={i18n.t.common.delete}
            onclick={() => void removeEvent(event)}
          >
            <Trash2 size={15} />
          </button>
        </li>
      {/each}
    </ol>
  {/if}
</div>
