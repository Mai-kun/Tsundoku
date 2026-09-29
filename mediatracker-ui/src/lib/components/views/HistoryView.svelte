<script lang="ts">
  import { Flag, History, RefreshCw } from 'lucide-svelte'
  import { errorMessage, getMedia } from '$lib/api'
  import { i18n } from '$lib/i18n/index.svelte'

  interface HistoryEvent {
    key: string
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
          ...(item.startedAt ? [{ key: `${item.id}:started`, title: item.title, date: item.startedAt, kind: 'started' as const }] : []),
          ...(item.finishedAt ? [{ key: `${item.id}:finished`, title: item.title, date: item.finishedAt, kind: 'finished' as const }] : []),
        ])
        .sort((left, right) => Date.parse(right.date) - Date.parse(left.date))

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
</script>

<div class="mx-auto max-w-4xl space-y-6">
  <div>
    <p class="text-xs font-semibold uppercase tracking-[0.18em] text-accent-soft">{i18n.t.library.collectionLabel}</p>
    <h2 class="mt-1 text-2xl font-bold tracking-tight text-ink">{i18n.t.views.historyTitle}</h2>
    <p class="mt-2 text-sm text-muted">{i18n.t.views.historyHint}</p>
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
        <li class="flex items-center gap-4 rounded-lg bg-card p-4"><div class={`grid h-10 w-10 shrink-0 place-items-center rounded-md ${event.kind === 'finished' ? 'bg-accent/15 text-accent-soft' : 'bg-star/15 text-star'}`}><Flag size={17} aria-hidden="true" /></div><div class="min-w-0 flex-1"><p class="truncate text-sm font-semibold text-ink">{event.title}</p><p class="mt-1 text-xs text-muted">{formatDate(event.date)}</p></div><span class="text-xs font-semibold text-muted">{event.kind === 'started' ? i18n.t.status.inProgress : i18n.t.status.completed}</span></li>
      {/each}
    </ol>
  {/if}
</div>
