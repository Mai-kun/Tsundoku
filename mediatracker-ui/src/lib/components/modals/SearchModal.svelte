<script lang="ts">
  import { Check, ChevronRight, Image as ImageIcon, Plus, Search, Star, X } from 'lucide-svelte'
  import { untrack } from 'svelte'
  import { createMedia, errorMessage, getCategoryOrder, searchExternal } from '$lib/api'
  import { i18n } from '$lib/i18n/index.svelte'
  import { MEDIA_STATUS, type CreateMediaPayload, type ExternalMedia, type MediaItem, type SearchMediaType } from '$lib/types'

  const categories = ['all', 'anime', 'manga', 'movie', 'tvshow', 'game', 'book'] as const
  const minQueryLength = 2
  const debounceDelay = 300
  const fallbackPlatform = 'PC'

  type SearchCategory = (typeof categories)[number]

  interface Props {
    isOpen: boolean
    initialType?: SearchCategory
    onClose: () => void
    onMediaAdded: (media: MediaItem) => void
  }

  let { isOpen, initialType = 'all', onClose, onMediaAdded }: Props = $props()

  let query = $state('')
  let activeType = $state<SearchCategory>(untrack(() => initialType))
  let results = $state<ExternalMedia[]>([])
  let searching = $state(false)
  let searchError = $state<unknown>(null)
  let addError = $state<unknown>(null)
  let addingKey = $state('')
  let addedKeys = $state<Record<string, boolean>>({})
  let searchInput = $state<HTMLInputElement | null>(null)
  let previewItem = $state<ExternalMedia | null>(null)
  let categoryOrder = $state<string[]>(['anime', 'manga', 'movie', 'tvshow', 'game', 'book'])
  let requestSequence = 0

  let term = $derived(query.trim())
  let canSearch = $derived(term.length >= minQueryLength)

  interface GroupedResult {
    category: SearchMediaType
    title: string
    items: ExternalMedia[]
    totalInGroup: number
  }

  let groupedResults = $derived.by<GroupedResult[]>(() => {
    if (activeType !== 'all') return []
    const groups: GroupedResult[] = []

    for (const cat of categoryOrder) {
      const matching = results.filter((r) => r.type === cat)
      if (matching.length > 0) {
        groups.push({
          category: cat as SearchMediaType,
          title: labelForCategory(cat as SearchCategory),
          items: matching.slice(0, 5),
          totalInGroup: matching.length,
        })
      }
    }

    const handledTypes = new Set(categoryOrder)
    for (const r of results) {
      if (!handledTypes.has(r.type)) {
        handledTypes.add(r.type)
        const matching = results.filter((item) => item.type === r.type)
        if (matching.length > 0) {
          groups.push({
            category: r.type,
            title: labelForCategory(r.type as SearchCategory),
            items: matching.slice(0, 5),
            totalInGroup: matching.length,
          })
        }
      }
    }

    return groups
  })

  $effect(() => {
    if (!isOpen) return

    const pendingTerm = term
    const pendingType = activeType
    const sequence = ++requestSequence
    addError = null

    if (pendingTerm.length < minQueryLength) {
      results = []
      searching = false
      searchError = null
      return
    }

    searching = true
    searchError = null
    const delay = setTimeout(() => void loadResults(pendingType, pendingTerm, sequence), debounceDelay)
    return () => clearTimeout(delay)
  })

  $effect(() => {
    if (isOpen) {
      activeType = initialType
      previewItem = null
      searchInput?.focus()
      void getCategoryOrder()
        .then((order) => {
          if (order && order.length > 0) categoryOrder = order
        })
        .catch(() => {})
    }
  })

  async function loadResults(type: SearchCategory, pendingTerm: string, sequence: number) {
    try {
      const found = await searchExternal(type, pendingTerm)
      if (sequence === requestSequence) {
        results = found
      }
    } catch (error) {
      if (sequence === requestSequence) {
        results = []
        searchError = error
      }
    } finally {
      if (sequence === requestSequence) {
        searching = false
      }
    }
  }

  function labelForCategory(category: SearchCategory): string {
    if (category === 'all') return i18n.t.searchModal.allCategories
    return category === 'anime' ? i18n.t.navigation.anime : i18n.t.types[category]
  }

  function effectiveType(result: ExternalMedia): SearchMediaType {
    return activeType === 'all' ? result.type : activeType
  }

  function resultKey(result: ExternalMedia): string {
    return `${result.type}:${result.externalId || result.title}`
  }

  function metaLine(result: ExternalMedia): string {
    return [result.releaseYear, result.studio, result.author, result.platform].filter(Boolean).join(' · ')
  }

  function countLabel(result: ExternalMedia): string | null {
    if (result.totalCount === null || result.totalCount === undefined) return null

    const type = effectiveType(result)
    const unit =
      type === 'anime' || type === 'tvshow'
        ? i18n.t.searchModal.countUnits.tvshow
        : type === 'manga'
          ? i18n.t.searchModal.countUnits.manga
          : type === 'movie'
            ? i18n.t.searchModal.countUnits.movie
            : type === 'game'
              ? i18n.t.searchModal.countUnits.game
              : i18n.t.searchModal.countUnits.book

    return `${result.totalCount} ${unit}`
  }

  function buildPayload(result: ExternalMedia): CreateMediaPayload {
    const common = {
      title: result.title,
      coverUrl: result.coverUrl,
      notes: result.description,
      status: MEDIA_STATUS.planned,
      externalId: result.externalId,
      externalSource: result.externalSource,
      externalRating: result.rating,
      externalRatingVotes: result.ratingVotes,
      externalRatingsJson: result.ratings ? JSON.stringify(result.ratings) : undefined,
    }

    switch (effectiveType(result)) {
      case 'anime':
        return {
          ...common,
          type: 'tvshow',
          isAnime: true,
          studio: result.studio,
          network: result.studio,
          seasons: [
            {
              seasonNumber: 1,
              title: 'Season 1',
              totalEpisodes: result.totalCount ?? result.episodes?.length ?? 0,
              episodesData: result.episodes ? JSON.stringify(result.episodes) : undefined,
            },
          ],
        }
      case 'tvshow':
        return { ...common, type: 'tvshow', isAnime: false, studio: result.studio, network: result.studio }
      case 'manga':
        return { ...common, type: 'manga', totalChapters: result.totalCount }
      case 'book':
        return { ...common, type: 'book', author: result.author || i18n.t.searchModal.unknownAuthor, totalPages: result.totalCount }
      case 'game':
        return { ...common, type: 'game', platform: result.platform || fallbackPlatform }
      case 'movie':
        return { ...common, type: 'movie', durationMinutes: result.totalCount, isAnime: false, studio: result.studio }
    }
  }

  async function addResult(result: ExternalMedia) {
    const key = resultKey(result)
    if (addingKey || addedKeys[key]) return

    addingKey = key
    addError = null

    try {
      const created = await createMedia(buildPayload(result))
      addedKeys[key] = true
      onMediaAdded(created)
    } catch (error) {
      addError = error
    } finally {
      addingKey = ''
    }
  }

  function closeOnBackdrop(event: MouseEvent) {
    if (event.target === event.currentTarget) {
      onClose()
    }
  }

  function sourceBadgeClass(source?: string | null): string {
    const s = (source ?? '').toLowerCase()
    if (s.includes('anilist')) return 'bg-[#02a9ff]/15 text-[#38bdf8] border-[#02a9ff]/30'
    if (s.includes('mal') || s.includes('myanimelist') || s.includes('jikan')) return 'bg-[#2e51a2]/20 text-[#60a5fa] border-[#2e51a2]/30'
    if (s.includes('mangaupdate')) return 'bg-[#3b82f6]/20 text-[#93c5fd] border-[#3b82f6]/30'
    if (s.includes('tmdb')) return 'bg-[#01b4e4]/15 text-[#38bdf8] border-[#01b4e4]/30'
    if (s.includes('kitsu')) return 'bg-[#fd755c]/15 text-[#fb923c] border-[#fd755c]/30'
    if (s.includes('rawg')) return 'bg-white/10 text-slate-200 border-white/20'
    if (s.includes('openlibrary')) return 'bg-amber-500/15 text-amber-300 border-amber-500/30'
    return 'bg-white/10 text-muted border-white/10'
  }

  function handleKeydown(event: KeyboardEvent) {
    if (isOpen && event.key === 'Escape') {
      if (previewItem) {
        previewItem = null
      } else {
        onClose()
      }
    }
  }
</script>

<svelte:window onkeydown={handleKeydown} />

{#if isOpen}
  <div class="fixed inset-0 z-50 flex items-start justify-center overflow-y-auto bg-canvas/85 p-4 backdrop-blur-sm sm:items-center" role="presentation" onclick={closeOnBackdrop}>
    <div class="my-auto flex min-h-[60vh] max-h-[85vh] w-full max-w-3xl flex-col overflow-hidden rounded-lg border border-border bg-surface shadow-2xl shadow-black/50" role="dialog" aria-modal="true" aria-labelledby="search-title">
      <header class="flex items-start justify-between gap-4 px-5 pb-4 pt-5 sm:px-6">
        <div>
          <p class="text-xs font-semibold uppercase tracking-[0.18em] text-accent-soft">{i18n.t.searchModal.eyebrow}</p>
          <h2 id="search-title" class="mt-1 text-xl font-bold tracking-tight text-ink">{i18n.t.searchModal.title}</h2>
        </div>
        <button type="button" class="grid h-9 w-9 place-items-center rounded-lg text-muted transition hover:bg-elevated hover:text-ink" aria-label={i18n.t.common.close} onclick={onClose}>
          <X size={18} aria-hidden="true" />
        </button>
      </header>

      <div class="border-y border-border px-5 py-3 sm:px-6">
        <div class="flex items-center gap-2">
          <label class="relative block flex-1">
            <span class="sr-only">{i18n.t.searchModal.inputLabel}</span>
            <Search size={16} class="pointer-events-none absolute left-3 top-1/2 -translate-y-1/2 text-muted" aria-hidden="true" />
            <input
              bind:this={searchInput}
              bind:value={query}
              class="h-10 w-full rounded-lg border border-border bg-elevated pl-9 pr-3 text-sm text-ink outline-none placeholder:text-muted focus:border-accent focus:ring-2 focus:ring-accent/30"
              type="search"
              placeholder={i18n.t.searchModal.placeholder(labelForCategory(activeType))}
              autocomplete="off"
            />
          </label>

          <label class="sr-only" for="search-category">{i18n.t.searchModal.categoriesLabel}</label>
          <select
            id="search-category"
            class="h-10 shrink-0 rounded-lg border border-border bg-elevated px-3 text-xs font-semibold text-ink outline-none transition focus:border-accent focus:ring-2 focus:ring-accent/30"
            value={activeType}
            onchange={(e) => (activeType = (e.currentTarget as HTMLSelectElement).value as SearchCategory)}
          >
            {#each categories as category}
              <option value={category}>{labelForCategory(category)}</option>
            {/each}
          </select>
        </div>
      </div>

      <div class="min-h-72 flex-1 overflow-y-auto px-5 py-4 sm:px-6">
        {#if addError}<p class="mb-4 rounded-lg border border-rose-400/30 bg-rose-400/10 px-3 py-2 text-sm text-rose-200" role="alert">{errorMessage(addError)}</p>{/if}
        {#if !canSearch}
          <div class="flex min-h-64 flex-col items-center justify-center gap-3 text-center">
            <div class="grid h-12 w-12 place-items-center rounded-lg bg-card text-muted"><Search size={22} aria-hidden="true" /></div>
            <p class="text-sm text-muted">{i18n.t.searchModal.emptyQueryTitle}</p>
            <p class="text-xs text-muted">{i18n.t.searchModal.emptyQueryHint}</p>
          </div>
        {:else if searching}
          <div class="space-y-3" aria-hidden="true">
            {#each Array(3) as _, index (index)}
              <div class="flex gap-4 rounded-lg bg-card p-3">
                <div class="h-28 w-20 animate-pulse rounded-md bg-canvas"></div>
                <div class="flex-1 space-y-2 py-1">
                  <div class="h-4 w-1/2 animate-pulse rounded bg-canvas"></div>
                  <div class="h-3 w-full animate-pulse rounded bg-canvas"></div>
                  <div class="h-3 w-4/5 animate-pulse rounded bg-canvas"></div>
                </div>
              </div>
            {/each}
          </div>
          <p class="sr-only" role="status">{i18n.t.searchModal.searching}</p>
        {:else if searchError}
          <div class="flex min-h-64 flex-col items-center justify-center gap-2 text-center">
            <p class="text-sm text-rose-200" role="alert">{errorMessage(searchError)}</p>
            <p class="text-xs text-muted">{i18n.t.searchModal.errorHint}</p>
          </div>
        {:else if results.length === 0}
          <div class="flex min-h-64 flex-col items-center justify-center gap-2 text-center">
            <p class="text-sm font-semibold text-ink">{i18n.t.searchModal.emptyTitle}</p>
            <p class="text-xs text-muted">{i18n.t.searchModal.emptyHint}</p>
          </div>
        {:else if activeType === 'all'}
          <!-- Grouped by category -->
          <div class="space-y-6">
            {#each groupedResults as group (group.category)}
              <section class="space-y-3">
                <div class="flex items-center justify-between border-b border-border/50 pb-2">
                  <h3 class="text-sm font-bold uppercase tracking-wider text-accent-soft">{group.title}</h3>
                  <button
                    type="button"
                    class="inline-flex items-center gap-1 text-xs font-medium text-muted transition hover:text-ink"
                    onclick={() => (activeType = group.category as SearchCategory)}
                  >
                    <span>{i18n.t.searchModal.searchMore}</span>
                    <ChevronRight size={14} aria-hidden="true" />
                  </button>
                </div>

                <ul class="space-y-2.5">
                  {#each group.items as result (resultKey(result))}
                    {@const key = resultKey(result)}
                    <!-- svelte-ignore a11y_click_events_have_key_events -->
                    <!-- svelte-ignore a11y_no_noninteractive_element_interactions -->
                    <li
                      class="flex cursor-pointer gap-4 rounded-lg bg-card p-3 transition hover:bg-elevated/70"
                      onclick={() => (previewItem = result)}
                    >
                      <div class="h-24 w-16 shrink-0 overflow-hidden rounded-md bg-canvas">
                        {#if result.coverUrl}
                          <img src={result.coverUrl} alt={result.title} class="h-full w-full object-cover" loading="lazy" />
                        {:else}
                          <div class="grid h-full place-items-center text-muted"><ImageIcon size={22} stroke-width={1.25} aria-hidden="true" /></div>
                        {/if}
                      </div>

                      <div class="min-w-0 flex-1 space-y-1.5">
                        <div class="flex items-start justify-between gap-3">
                          <div class="min-w-0">
                            <h4 class="truncate text-sm font-semibold text-ink" title={result.title}>{result.title}</h4>
                            {#if result.originalTitle}
                              <p class="truncate text-xs text-muted" title={result.originalTitle}>{result.originalTitle}</p>
                            {/if}
                          </div>

                          {#if addedKeys[key]}
                            <span class="flex h-8 w-8 shrink-0 items-center justify-center rounded-full border border-emerald-500/20 bg-emerald-500/10 text-emerald-400" title={i18n.t.searchModal.inLibrary}>
                              <Check size={16} aria-hidden="true" />
                            </span>
                          {:else}
                            <button
                              type="button"
                              class="flex h-8 w-8 shrink-0 items-center justify-center rounded-full border border-border bg-elevated text-muted transition hover:border-accent hover:bg-panel hover:text-ink disabled:cursor-wait disabled:opacity-70"
                              title={i18n.t.common.add}
                              disabled={Boolean(addingKey)}
                              onclick={(e) => {
                                e.stopPropagation()
                                void addResult(result)
                              }}
                            >
                              {#if addingKey === key}
                                <div class="h-3.5 w-3.5 animate-spin rounded-full border-2 border-accent border-t-transparent"></div>
                              {:else}
                                <Plus size={16} aria-hidden="true" />
                              {/if}
                            </button>
                          {/if}
                        </div>

                        <div class="flex flex-wrap items-center gap-2 text-xs text-muted">
                          {#if result.externalSource}
                            <span class={`rounded px-1.5 py-0.5 text-[10px] font-semibold border ${sourceBadgeClass(result.externalSource)}`}>
                              {result.externalSource}
                            </span>
                          {/if}
                          {#if result.rating}
                            <span class="flex items-center gap-0.5 font-semibold text-star">
                              <Star size={12} fill="currentColor" />
                              {result.rating.toFixed(1)}
                            </span>
                          {/if}
                          {#if metaLine(result)}<span>{metaLine(result)}</span>{/if}
                          {#if countLabel(result)}<span class="rounded-full bg-canvas px-2 py-0.5 text-[11px] font-semibold text-muted">{countLabel(result)}</span>{/if}
                        </div>

                        {#if result.description}
                          <p class="line-clamp-2 text-xs leading-relaxed text-muted">{result.description}</p>
                        {/if}
                      </div>
                    </li>
                  {/each}
                </ul>
              </section>
            {/each}
          </div>
        {:else}
          <!-- Single category list -->
          <ul class="space-y-3">
            {#each results as result (resultKey(result))}
              {@const key = resultKey(result)}
              <!-- svelte-ignore a11y_click_events_have_key_events -->
              <!-- svelte-ignore a11y_no_noninteractive_element_interactions -->
              <li
                class="flex cursor-pointer gap-4 rounded-lg bg-card p-3 transition hover:bg-elevated/70"
                onclick={() => (previewItem = result)}
              >
                <div class="h-28 w-20 shrink-0 overflow-hidden rounded-md bg-canvas">
                  {#if result.coverUrl}
                    <img src={result.coverUrl} alt={result.title} class="h-full w-full object-cover" loading="lazy" />
                  {:else}
                    <div class="grid h-full place-items-center text-muted"><ImageIcon size={27} stroke-width={1.25} aria-hidden="true" /></div>
                  {/if}
                </div>

                <div class="min-w-0 flex-1 space-y-2">
                  <div class="flex items-start justify-between gap-3">
                    <div class="min-w-0">
                      <h3 class="truncate text-sm font-semibold text-ink" title={result.title}>{result.title}</h3>
                      {#if result.originalTitle}
                        <p class="truncate text-xs text-muted" title={result.originalTitle}>{result.originalTitle}</p>
                      {/if}
                    </div>

                    {#if addedKeys[key]}
                      <span class="flex h-8 w-8 shrink-0 items-center justify-center rounded-full border border-emerald-500/20 bg-emerald-500/10 text-emerald-400" title={i18n.t.searchModal.inLibrary}>
                        <Check size={16} aria-hidden="true" />
                      </span>
                    {:else}
                      <button
                        type="button"
                        class="flex h-8 w-8 shrink-0 items-center justify-center rounded-full border border-border bg-elevated text-muted transition hover:border-accent hover:bg-panel hover:text-ink disabled:cursor-wait disabled:opacity-70"
                        title={i18n.t.common.add}
                        disabled={Boolean(addingKey)}
                        onclick={(e) => {
                          e.stopPropagation()
                          void addResult(result)
                        }}
                      >
                        {#if addingKey === key}
                          <div class="h-3.5 w-3.5 animate-spin rounded-full border-2 border-accent border-t-transparent"></div>
                        {:else}
                          <Plus size={16} aria-hidden="true" />
                        {/if}
                      </button>
                    {/if}
                  </div>

                  <div class="flex flex-wrap items-center gap-2 text-xs text-muted">
                    {#if result.externalSource}
                      <span class={`rounded px-1.5 py-0.5 text-[10px] font-semibold border ${sourceBadgeClass(result.externalSource)}`}>
                        {result.externalSource}
                      </span>
                    {/if}
                    {#if result.rating}
                      <span class="flex items-center gap-0.5 font-semibold text-star">
                        <Star size={12} fill="currentColor" />
                        {result.rating.toFixed(1)}
                      </span>
                    {/if}
                    {#if metaLine(result)}<span>{metaLine(result)}</span>{/if}
                    {#if countLabel(result)}<span class="rounded-full bg-canvas px-2 py-0.5 text-[11px] font-semibold text-muted">{countLabel(result)}</span>{/if}
                  </div>

                  {#if result.description}
                    <p class="line-clamp-2 text-xs leading-5 text-muted">{result.description}</p>
                  {/if}
                </div>
              </li>
            {/each}
          </ul>
        {/if}
      </div>
    </div>
  </div>
{/if}

<!-- Preview modal (Requirement 13) -->
{#if previewItem}
  {@const prevKey = resultKey(previewItem)}
  <div
    class="fixed inset-0 z-[60] flex items-center justify-center overflow-y-auto bg-black/75 p-4 backdrop-blur-md"
    role="presentation"
    onclick={() => (previewItem = null)}
  >
    <!-- svelte-ignore a11y_click_events_have_key_events -->
    <!-- svelte-ignore a11y_no_noninteractive_element_interactions -->
    <div
      class="relative flex max-h-[85vh] w-full max-w-2xl flex-col overflow-hidden rounded-xl border border-border bg-surface p-6 shadow-2xl"
      role="dialog"
      aria-modal="true"
      tabindex="-1"
      onclick={(e) => e.stopPropagation()}
    >
      <button
        type="button"
        class="absolute right-4 top-4 grid h-8 w-8 place-items-center rounded-lg text-muted transition hover:bg-elevated hover:text-ink"
        onclick={() => (previewItem = null)}
      >
        <X size={18} aria-hidden="true" />
      </button>

      <div class="overflow-y-auto pr-1">
        <div class="flex flex-col gap-5 sm:flex-row">
          <div class="mx-auto aspect-[2/3] w-40 shrink-0 overflow-hidden rounded-lg bg-canvas sm:mx-0">
            {#if previewItem.coverUrl}
              <img src={previewItem.coverUrl} alt={previewItem.title} class="h-full w-full object-cover" />
            {:else}
              <div class="grid h-full place-items-center text-muted"><ImageIcon size={32} stroke-width={1.25} aria-hidden="true" /></div>
            {/if}
          </div>

          <div class="min-w-0 flex-1 space-y-3">
            <div class="flex flex-wrap items-center gap-2">
              <span class="rounded-full bg-elevated px-2.5 py-0.5 text-[11px] font-semibold uppercase tracking-wider text-accent-soft">
                {labelForCategory(previewItem.type as SearchCategory)}
              </span>
              {#if previewItem.externalSource}
                <span class={`rounded-full px-2.5 py-0.5 text-[11px] font-semibold border ${sourceBadgeClass(previewItem.externalSource)}`}>
                  {previewItem.externalSource}
                </span>
              {/if}
            </div>
            <div>
              <h3 class="mt-1 text-lg font-bold text-ink">{previewItem.title}</h3>
              {#if previewItem.originalTitle}
                <p class="text-xs text-muted">{previewItem.originalTitle}</p>
              {/if}
            </div>

            <!-- Ratings -->
            {#if previewItem.ratings && previewItem.ratings.length > 0}
              <div class="flex flex-wrap items-center gap-2">
                {#each previewItem.ratings as r}
                  <div class="inline-flex items-center gap-1 rounded-md border border-border bg-elevated px-2 py-0.5 text-xs">
                    <span class="font-medium text-muted">{r.source}:</span>
                    <span class="flex items-center gap-0.5 font-bold text-star">
                      <Star size={11} fill="currentColor" />
                      {(r.rating ?? r.score ?? 0).toFixed(1)}
                    </span>
                  </div>
                {/each}
              </div>
            {:else if previewItem.rating}
              <div class="inline-flex items-center gap-1 rounded-md border border-border bg-elevated px-2 py-0.5 text-xs">
                <span class="font-medium text-muted">{previewItem.externalSource || 'Rating'}:</span>
                <span class="flex items-center gap-0.5 font-bold text-star">
                  <Star size={11} fill="currentColor" />
                  {previewItem.rating.toFixed(1)}
                </span>
              </div>
            {:else}
              <div class="inline-flex items-center gap-1 rounded-md border border-border bg-elevated px-2 py-0.5 text-xs text-muted">
                <span>{i18n.t.detail.previewModal.noRatings}</span>
              </div>
            {/if}

            <div class="space-y-1 text-xs text-muted">
              <div>
                <span class="font-medium text-ink">{i18n.t.detail.previewModal.year}:</span>
                {previewItem.releaseYear ?? i18n.t.detail.previewModal.noData}
              </div>
              {#if previewItem.type === 'manga' || previewItem.type === 'book'}
                <div>
                  <span class="font-medium text-ink">{i18n.t.detail.previewModal.author}:</span>
                  {previewItem.author ?? i18n.t.detail.previewModal.noData}
                </div>
              {:else}
                <div>
                  <span class="font-medium text-ink">{i18n.t.detail.previewModal.studio}:</span>
                  {previewItem.studio ?? i18n.t.detail.previewModal.noData}
                </div>
              {/if}
              {#if previewItem.platform}
                <div>
                  <span class="font-medium text-ink">{i18n.t.detail.previewModal.platform}:</span>
                  {previewItem.platform}
                </div>
              {/if}
              <div>
                <span class="font-medium text-ink">{i18n.t.detail.previewModal.count}:</span>
                {countLabel(previewItem) || i18n.t.detail.previewModal.noData}
              </div>
            </div>

            <div class="pt-2">
              {#if addedKeys[prevKey]}
                <div class="inline-flex items-center gap-1.5 rounded-lg border border-emerald-500/20 bg-emerald-500/10 px-4 py-2 text-xs font-semibold text-emerald-400">
                  <Check size={16} aria-hidden="true" />
                  {i18n.t.searchModal.inLibrary}
                </div>
              {:else}
                <button
                  type="button"
                  class="inline-flex items-center gap-2 rounded-lg border border-border bg-elevated px-4 py-2 text-xs font-semibold text-ink transition hover:border-accent hover:bg-panel disabled:cursor-wait disabled:opacity-70"
                  disabled={Boolean(addingKey)}
                  onclick={() => void addResult(previewItem!)}
                >
                  {#if addingKey === prevKey}
                    <div class="h-4 w-4 animate-spin rounded-full border-2 border-accent border-t-transparent"></div>
                    <span>{i18n.t.common.adding}</span>
                  {:else}
                    <Plus size={16} aria-hidden="true" />
                    <span>{i18n.t.common.add}</span>
                  {/if}
                </button>
              {/if}
            </div>
          </div>
        </div>

        <div class="mt-5 border-t border-border pt-4">
          <h4 class="text-xs font-semibold uppercase tracking-wider text-muted">{i18n.t.detail.previewModal.description}</h4>
          {#if previewItem.description}
            <p class="mt-1.5 whitespace-pre-line text-xs leading-relaxed text-muted">{previewItem.description}</p>
          {:else}
            <p class="mt-1.5 text-xs italic text-muted/70">{i18n.t.detail.previewModal.noDescription}</p>
          {/if}
        </div>

        {#if previewItem.episodes && previewItem.episodes.length > 0}
          <div class="mt-5 border-t border-border pt-4">
            <h4 class="text-xs font-semibold uppercase tracking-wider text-muted">{i18n.t.detail.previewModal.episodesList(previewItem.episodes.length)}</h4>
            <ul class="mt-2 max-h-48 space-y-1.5 overflow-y-auto pr-1">
              {#each previewItem.episodes as ep}
                <li class="flex items-center justify-between rounded bg-elevated/50 px-2.5 py-1.5 text-xs text-ink">
                  <span class="font-medium text-muted">E{ep.number}</span>
                  <span class="truncate pl-2 text-right">{ep.title || i18n.t.detail.episodeTitle(ep.number)}</span>
                </li>
              {/each}
            </ul>
          </div>
        {/if}
      </div>
    </div>
  </div>
{/if}
