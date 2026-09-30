<script lang="ts">
  import BookOpen from 'lucide-svelte/icons/book-open'
  import CheckCircle2 from 'lucide-svelte/icons/check-circle-2'
  import Clock3 from 'lucide-svelte/icons/clock-3'
  import Film from 'lucide-svelte/icons/film'
  import Gamepad2 from 'lucide-svelte/icons/gamepad-2'
  import Library from 'lucide-svelte/icons/library'
  import RefreshCw from 'lucide-svelte/icons/refresh-cw'
  import Tv from 'lucide-svelte/icons/tv'
  import { errorMessage, getStats } from '$lib/api'
  import { i18n } from '$lib/i18n/index.svelte'
  import type { MediaStats } from '$lib/types'

  interface Props {
    refreshKey: number
  }

  let { refreshKey }: Props = $props()

  let stats = $state<MediaStats | null>(null)
  let loading = $state(true)
  let loadError = $state<unknown>(null)
  let requestSequence = 0

  $effect(() => {
    void refreshKey
    void loadStats(++requestSequence)
  })

  async function loadStats(sequence: number) {
    loading = true
    loadError = null

    try {
      const nextStats = await getStats()
      if (sequence === requestSequence) {
        stats = nextStats
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
    void loadStats(++requestSequence)
  }

  function format(value: number): string {
    return new Intl.NumberFormat(i18n.current).format(value)
  }
</script>

<div class="mx-auto max-w-6xl space-y-6">
  <div>
    <p class="text-xs font-semibold uppercase tracking-[0.18em] text-accent-soft">{i18n.t.library.collectionLabel}</p>
    <h2 class="mt-1 text-2xl font-bold tracking-tight text-ink">{i18n.t.stats.title}</h2>
  </div>

  {#if loading}
    <div class="grid gap-4 sm:grid-cols-2 xl:grid-cols-4" aria-hidden="true">
      {#each Array(8) as _, index (index)}
        <div class="h-28 animate-pulse rounded-lg bg-card"></div>
      {/each}
    </div>
    <p class="sr-only" role="status">{i18n.t.common.loading}</p>
  {:else if loadError}
    <div class="flex min-h-72 flex-col items-center justify-center gap-3 rounded-lg bg-rose-400/5 p-6 text-center">
      <p class="text-sm text-rose-200" role="alert">{errorMessage(loadError)}</p>
      <button type="button" class="inline-flex items-center gap-2 rounded-md bg-accent px-4 py-2 text-sm font-medium text-white transition hover:bg-accent-hover" onclick={retry}><RefreshCw size={15} aria-hidden="true" />{i18n.t.common.retry}</button>
    </div>
  {:else if stats}
    <div class="grid gap-4 sm:grid-cols-2 xl:grid-cols-4">
      <article class="rounded-lg bg-card p-5"><Library size={19} class="text-accent-soft" aria-hidden="true" /><p class="mt-6 text-2xl font-bold text-ink">{format(stats.totalItems)}</p><p class="mt-1 text-sm text-muted">{i18n.t.stats.totalItems}</p></article>
      <article class="rounded-lg bg-card p-5"><CheckCircle2 size={19} class="text-accent-soft" aria-hidden="true" /><p class="mt-6 text-2xl font-bold text-ink">{format(stats.completedItems)}</p><p class="mt-1 text-sm text-muted">{i18n.t.stats.completedItems}</p></article>
      <article class="rounded-lg bg-card p-5"><Clock3 size={19} class="text-star" aria-hidden="true" /><p class="mt-6 text-2xl font-bold text-ink">{format(stats.inProgressItems)}</p><p class="mt-1 text-sm text-muted">{i18n.t.stats.inProgressItems}</p></article>
      <article class="rounded-lg bg-card p-5"><Library size={19} class="text-muted" aria-hidden="true" /><p class="mt-6 text-2xl font-bold text-ink">{format(stats.plannedItems)}</p><p class="mt-1 text-sm text-muted">{i18n.t.stats.plannedItems}</p></article>
      <article class="rounded-lg bg-card p-5"><Gamepad2 size={19} class="text-star" aria-hidden="true" /><p class="mt-6 text-2xl font-bold text-ink">{format(stats.totalHoursPlayed)}</p><p class="mt-1 text-sm text-muted">{i18n.t.stats.hours}</p></article>
      <article class="rounded-lg bg-card p-5"><BookOpen size={19} class="text-star" aria-hidden="true" /><p class="mt-6 text-2xl font-bold text-ink">{format(stats.totalPagesRead)}</p><p class="mt-1 text-sm text-muted">{i18n.t.stats.pages}</p></article>
      <article class="rounded-lg bg-card p-5"><BookOpen size={19} class="text-star" aria-hidden="true" /><p class="mt-6 text-2xl font-bold text-ink">{format(stats.totalChaptersRead)}</p><p class="mt-1 text-sm text-muted">{i18n.t.stats.chapters}</p></article>
      <article class="rounded-lg bg-card p-5"><Tv size={19} class="text-star" aria-hidden="true" /><p class="mt-6 text-2xl font-bold text-ink">{format(stats.totalEpisodesWatched)}</p><p class="mt-1 text-sm text-muted">{i18n.t.stats.episodes}</p></article>
      <article class="rounded-lg bg-card p-5"><Gamepad2 size={19} class="text-accent-soft" aria-hidden="true" /><p class="mt-6 text-2xl font-bold text-ink">{format(stats.completedGamesCount)}</p><p class="mt-1 text-sm text-muted">{i18n.t.stats.gamesCompleted}</p></article>
      <article class="rounded-lg bg-card p-5"><BookOpen size={19} class="text-accent-soft" aria-hidden="true" /><p class="mt-6 text-2xl font-bold text-ink">{format(stats.completedBooksCount)}</p><p class="mt-1 text-sm text-muted">{i18n.t.stats.booksCompleted}</p></article>
      <article class="rounded-lg bg-card p-5"><Film size={19} class="text-accent-soft" aria-hidden="true" /><p class="mt-6 text-2xl font-bold text-ink">{format(stats.completedMoviesCount)}</p><p class="mt-1 text-sm text-muted">{i18n.t.stats.moviesCompleted}</p></article>
    </div>
  {/if}
</div>
