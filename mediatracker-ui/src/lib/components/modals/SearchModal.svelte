<script lang="ts">
  import { Check, Image as ImageIcon, Plus, Search, X } from 'lucide-svelte'
  import { untrack } from 'svelte'
  import { createMedia, errorMessage, searchExternal } from '$lib/api'
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
  let requestSequence = 0

  let term = $derived(query.trim())
  let canSearch = $derived(term.length >= minQueryLength)

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
      searchInput?.focus()
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
    const unit = type === 'anime' || type === 'tvshow'
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
    }

    switch (effectiveType(result)) {
      case 'anime':
        return { ...common, type: 'tvshow', isAnime: true, studio: result.studio, network: result.studio }
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

  function handleKeydown(event: KeyboardEvent) {
    if (isOpen && event.key === 'Escape') {
      onClose()
    }
  }
</script>

<svelte:window onkeydown={handleKeydown} />

{#if isOpen}
  <div class="fixed inset-0 z-50 flex items-start justify-center overflow-y-auto bg-canvas/85 p-4 backdrop-blur-sm sm:items-center" role="presentation" onclick={closeOnBackdrop}>
    <div class="my-auto flex max-h-[85vh] w-full max-w-3xl flex-col overflow-hidden rounded-lg border border-border bg-surface shadow-2xl shadow-black/50" role="dialog" aria-modal="true" aria-labelledby="search-title">
      <header class="flex items-start justify-between gap-4 px-5 pb-4 pt-5 sm:px-6"><div><p class="text-xs font-semibold uppercase tracking-[0.18em] text-accent-soft">{i18n.t.searchModal.eyebrow}</p><h2 id="search-title" class="mt-1 text-xl font-bold tracking-tight text-ink">{i18n.t.searchModal.title}</h2></div><button type="button" class="grid h-9 w-9 place-items-center rounded-lg text-muted transition hover:bg-elevated hover:text-ink" aria-label={i18n.t.common.close} onclick={onClose}><X size={18} aria-hidden="true" /></button></header>

      <nav class="flex flex-wrap gap-2 px-5 pb-4 sm:px-6" aria-label={i18n.t.searchModal.categoriesLabel}>{#each categories as category}<button type="button" aria-pressed={activeType === category} class={`rounded-lg px-3 py-1.5 text-xs font-semibold transition ${activeType === category ? 'bg-accent text-white' : 'bg-elevated text-muted hover:text-ink'}`} onclick={() => (activeType = category)}>{labelForCategory(category)}</button>{/each}</nav>

      <div class="border-y border-border px-5 py-4 sm:px-6"><label class="relative block"><span class="sr-only">{i18n.t.searchModal.inputLabel}</span><Search size={16} class="pointer-events-none absolute left-3 top-1/2 -translate-y-1/2 text-muted" aria-hidden="true" /><input bind:this={searchInput} bind:value={query} class="h-10 w-full rounded-lg border border-border bg-elevated pl-9 pr-3 text-sm text-ink outline-none placeholder:text-muted focus:border-accent focus:ring-2 focus:ring-accent/30" type="search" placeholder={i18n.t.searchModal.placeholder(labelForCategory(activeType))} autocomplete="off" /></label></div>

      <div class="min-h-72 flex-1 overflow-y-auto px-5 py-4 sm:px-6">
        {#if addError}<p class="mb-4 rounded-lg border border-rose-400/30 bg-rose-400/10 px-3 py-2 text-sm text-rose-200" role="alert">{errorMessage(addError)}</p>{/if}
        {#if !canSearch}
          <div class="flex min-h-64 flex-col items-center justify-center gap-3 text-center"><div class="grid h-12 w-12 place-items-center rounded-lg bg-card text-muted"><Search size={22} aria-hidden="true" /></div><p class="text-sm text-muted">{i18n.t.searchModal.emptyQueryTitle}</p><p class="text-xs text-muted">{i18n.t.searchModal.emptyQueryHint}</p></div>
        {:else if searching}
          <div class="space-y-3" aria-hidden="true">{#each Array(3) as _, index (index)}<div class="flex gap-4 rounded-lg bg-card p-3"><div class="h-28 w-20 animate-pulse rounded-md bg-canvas"></div><div class="flex-1 space-y-2 py-1"><div class="h-4 w-1/2 animate-pulse rounded bg-canvas"></div><div class="h-3 w-full animate-pulse rounded bg-canvas"></div><div class="h-3 w-4/5 animate-pulse rounded bg-canvas"></div></div></div>{/each}</div><p class="sr-only" role="status">{i18n.t.searchModal.searching}</p>
        {:else if searchError}
          <div class="flex min-h-64 flex-col items-center justify-center gap-2 text-center"><p class="text-sm text-rose-200" role="alert">{errorMessage(searchError)}</p><p class="text-xs text-muted">{i18n.t.searchModal.errorHint}</p></div>
        {:else if results.length === 0}
          <div class="flex min-h-64 flex-col items-center justify-center gap-2 text-center"><p class="text-sm font-semibold text-ink">{i18n.t.searchModal.emptyTitle}</p><p class="text-xs text-muted">{i18n.t.searchModal.emptyHint}</p></div>
        {:else}
          <ul class="space-y-3">{#each results as result (resultKey(result))}{@const key = resultKey(result)}<li class="flex gap-4 rounded-lg bg-card p-3"><div class="h-28 w-20 shrink-0 overflow-hidden rounded-md bg-canvas">{#if result.coverUrl}<img src={result.coverUrl} alt={result.title} class="h-full w-full object-cover" loading="lazy" />{:else}<div class="grid h-full place-items-center text-muted"><ImageIcon size={27} stroke-width={1.25} aria-hidden="true" /></div>{/if}</div><div class="min-w-0 flex-1 space-y-2"><div class="flex items-start justify-between gap-3"><div class="min-w-0"><h3 class="truncate text-sm font-semibold text-ink" title={result.title}>{result.title}</h3>{#if result.originalTitle}<p class="truncate text-xs text-muted" title={result.originalTitle}>{result.originalTitle}</p>{/if}</div>{#if addedKeys[key]}<span class="inline-flex shrink-0 items-center gap-1 rounded-md bg-emerald-400/10 px-2.5 py-1.5 text-xs font-semibold text-emerald-300"><Check size={14} aria-hidden="true" />{i18n.t.searchModal.inLibrary}</span>{:else}<button type="button" class="inline-flex shrink-0 items-center gap-1 rounded-md bg-accent px-2.5 py-1.5 text-xs font-semibold text-white transition hover:bg-accent-hover disabled:cursor-wait disabled:opacity-70" disabled={Boolean(addingKey)} onclick={() => void addResult(result)}>{#if addingKey === key}{i18n.t.common.adding}{:else}<Plus size={14} aria-hidden="true" />{i18n.t.common.add}{/if}</button>{/if}</div><div class="flex flex-wrap gap-2 text-xs text-muted">{#if metaLine(result)}<span>{metaLine(result)}</span>{/if}{#if countLabel(result)}<span class="rounded-full bg-canvas px-2 py-0.5 text-[11px] font-semibold text-muted">{countLabel(result)}</span>{/if}</div>{#if result.description}<p class="line-clamp-2 text-xs leading-5 text-muted">{result.description}</p>{/if}</div></li>{/each}</ul>
        {/if}
      </div>
    </div>
  </div>
{/if}
