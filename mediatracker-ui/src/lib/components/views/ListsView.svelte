<script lang="ts">
  import BookOpen from 'lucide-svelte/icons/book-open'
  import Film from 'lucide-svelte/icons/film'
  import Gamepad2 from 'lucide-svelte/icons/gamepad-2'
  import Library from 'lucide-svelte/icons/library'
  import List from 'lucide-svelte/icons/list'
  import RefreshCw from 'lucide-svelte/icons/refresh-cw'
  import Tv from 'lucide-svelte/icons/tv'
  import { errorMessage, getMedia } from '$lib/api'
  import { i18n } from '$lib/i18n/index.svelte'
  import type { MediaItem } from '$lib/types'

  let items = $state<MediaItem[]>([])
  let loading = $state(true)
  let loadError = $state<unknown>(null)
  let requestSequence = 0

  $effect(() => {
    void loadItems(++requestSequence)
  })

  async function loadItems(sequence: number) {
    loading = true
    loadError = null
    try {
      const found = await getMedia()
      if (sequence === requestSequence) items = found
    } catch (error) {
      if (sequence === requestSequence) loadError = error
    } finally {
      if (sequence === requestSequence) loading = false
    }
  }

  function retry() {
    void loadItems(++requestSequence)
  }

  interface CategoryCount {
    key: string
    icon: typeof Film
    count: number
    label: string
  }

  let categoryCounts = $derived.by((): CategoryCount[] => {
    const counts: Record<string, number> = {}
    for (const item of items) {
      if (item.type === 'tvshow' && item.isAnime) {
        counts['anime'] = (counts['anime'] ?? 0) + 1
      } else {
        counts[item.type] = (counts[item.type] ?? 0) + 1
      }
    }

    const entries: CategoryCount[] = []
    if (counts['tvshow']) entries.push({ key: 'tvshow', icon: Tv, count: counts['tvshow'], label: i18n.t.navigation.tvshow })
    if (counts['movie']) entries.push({ key: 'movie', icon: Film, count: counts['movie'], label: i18n.t.navigation.movie })
    if (counts['anime']) entries.push({ key: 'anime', icon: Tv, count: counts['anime'], label: i18n.t.navigation.anime })
    if (counts['manga']) entries.push({ key: 'manga', icon: Library, count: counts['manga'], label: i18n.t.navigation.manga })
    if (counts['game']) entries.push({ key: 'game', icon: Gamepad2, count: counts['game'], label: i18n.t.navigation.game })
    if (counts['book']) entries.push({ key: 'book', icon: BookOpen, count: counts['book'], label: i18n.t.navigation.book })
    return entries
  })
</script>

<div class="mx-auto max-w-3xl space-y-6">
  <div>
    <p class="text-xs font-semibold uppercase tracking-[0.18em] text-accent-soft">{i18n.t.library.collectionLabel}</p>
    <h2 class="mt-1 text-2xl font-bold tracking-tight text-ink">{i18n.t.views.listsTitle}</h2>
  </div>

  {#if loading}
    <div class="space-y-3" aria-hidden="true">
      {#each Array(4) as _, index (index)}
        <div class="h-16 animate-pulse rounded-lg bg-card"></div>
      {/each}
    </div>
    <p class="sr-only" role="status">{i18n.t.common.loading}</p>
  {:else if loadError}
    <div class="flex min-h-72 flex-col items-center justify-center gap-3 rounded-lg bg-rose-400/5 p-6 text-center">
      <p class="text-sm text-rose-200" role="alert">{errorMessage(loadError)}</p>
      <button type="button" class="inline-flex items-center gap-2 rounded-md bg-accent px-4 py-2 text-sm font-medium text-white transition hover:bg-accent-hover" onclick={retry}><RefreshCw size={15} aria-hidden="true" />{i18n.t.common.retry}</button>
    </div>
  {:else if items.length === 0}
    <div class="flex min-h-[40vh] flex-col items-center justify-center rounded-lg bg-surface p-8 text-center">
      <div class="grid h-14 w-14 place-items-center rounded-lg bg-card text-accent-soft"><List size={24} aria-hidden="true" /></div>
      <p class="mt-5 text-sm text-muted">{i18n.t.library.emptyHint}</p>
    </div>
  {:else}
    <div class="rounded-lg bg-surface p-4">
      <div class="flex items-center gap-3 border-b border-border pb-3 mb-3">
        <Library size={18} class="text-accent-soft" aria-hidden="true" />
        <span class="text-lg font-bold text-ink">{items.length}</span>
        <span class="text-sm text-muted">{i18n.t.stats.totalItems}</span>
      </div>

      <div class="space-y-2">
        {#each categoryCounts as cat (cat.key)}
          <div class="flex items-center gap-3 rounded-md bg-card px-4 py-3">
            <cat.icon size={18} class="text-accent-soft" aria-hidden="true" />
            <span class="text-lg font-bold tabular-nums text-ink">{cat.count}</span>
            <span class="text-sm text-muted">{cat.label}</span>
          </div>
        {/each}
      </div>
    </div>

    <div class="flex min-h-[20vh] flex-col items-center justify-center rounded-lg bg-surface p-8 text-center">
      <div class="grid h-14 w-14 place-items-center rounded-lg bg-card text-accent-soft"><List size={24} aria-hidden="true" /></div>
      <p class="mt-5 text-xs font-semibold uppercase tracking-[0.18em] text-accent-soft">{i18n.t.common.comingSoon}</p>
      <p class="mt-3 max-w-md text-sm leading-6 text-muted">{i18n.t.views.listsHint}</p>
    </div>
  {/if}
</div>
