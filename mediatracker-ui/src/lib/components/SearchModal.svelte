<script>
  import { untrack } from 'svelte'
  import { createMedia, searchExternal } from '../api.js'

  const categories = [
    { id: 'anime', label: 'Аниме' },
    { id: 'manga', label: 'Манга' },
    { id: 'movie', label: 'Фильмы' },
    { id: 'tvshow', label: 'Сериалы' },
    { id: 'game', label: 'Игры' },
    { id: 'book', label: 'Книги' },
  ]

  const minQueryLength = 2
  const debounceDelay = 300
  const plannedStatus = 0
  const fallbackAuthor = 'Неизвестный автор'
  const fallbackPlatform = 'PC'

  const countUnits = {
    anime: 'эп.',
    manga: 'гл.',
    book: 'стр.',
    movie: 'мин.',
  }

  let { isOpen, initialType = 'anime', onClose = () => {}, onMediaAdded = () => {} } = $props()

  let query = $state('')
  let activeType = $state(untrack(() => initialType))
  let results = $state([])
  let searching = $state(false)
  let searchError = $state('')
  let addError = $state('')
  let addingKey = $state('')
  let addedKeys = $state({})
  let searchInput = $state(null)
  let requestSequence = 0

  let term = $derived(query.trim())
  let canSearch = $derived(term.length >= minQueryLength)
  let activeCategory = $derived(categories.find((category) => category.id === activeType) ?? categories[0])

  $effect(() => {
    if (!isOpen) return

    const pendingTerm = term
    const pendingType = activeType
    const sequence = ++requestSequence

    addError = ''

    if (pendingTerm.length < minQueryLength) {
      results = []
      searching = false
      searchError = ''
      return
    }

    searching = true
    searchError = ''

    const delay = window.setTimeout(() => loadResults(pendingType, pendingTerm, sequence), debounceDelay)
    return () => window.clearTimeout(delay)
  })

  $effect(() => {
    if (isOpen) {
      activeType = initialType
    }
  })

  $effect(() => {
    if (isOpen && searchInput) {
      searchInput.focus()
    }
  })

  async function loadResults(type, pendingTerm, sequence) {
    try {
      const found = await searchExternal(type, pendingTerm)

      if (sequence === requestSequence) {
        results = found
      }
    } catch (requestError) {
      if (sequence === requestSequence) {
        results = []
        searchError = requestError.message
      }
    } finally {
      if (sequence === requestSequence) {
        searching = false
      }
    }
  }

  function resultKey(result) {
    return `${activeType}:${result.externalId || result.title}`
  }

  function metaLine(result) {
    return [result.releaseYear, result.studio, result.author, result.platform].filter(Boolean).join(' · ')
  }

  function countLabel(result) {
    if (result.totalCount === null || result.totalCount === undefined) {
      return null
    }

    const unit = countUnits[activeType]
    return unit ? `${result.totalCount} ${unit}` : String(result.totalCount)
  }

  function buildPayload(result) {
    const payload = {
      title: result.title,
      coverUrl: result.coverUrl,
      notes: result.description,
      status: plannedStatus,
    }

    switch (activeType) {
      case 'anime':
        return { ...payload, type: 'TvShow', isAnime: true, studio: result.studio, network: result.studio }
      case 'manga':
        return { ...payload, type: 'Manga', totalChapters: result.totalCount }
      case 'book':
        return { ...payload, type: 'Book', author: result.author || fallbackAuthor, totalPages: result.totalCount ?? 0 }
      case 'game':
        return { ...payload, type: 'Game', platform: result.platform || fallbackPlatform }
      case 'movie':
        return { ...payload, type: 'Movie', durationMinutes: result.totalCount ?? 0 }
      default:
        return { ...payload, type: 'TvShow', isAnime: false }
    }
  }

  async function addResult(result) {
    const key = resultKey(result)

    if (addingKey || addedKeys[key]) return

    addingKey = key
    addError = ''

    try {
      const created = await createMedia(buildPayload(result))
      addedKeys[key] = true
      onMediaAdded(created)
    } catch (requestError) {
      addError = requestError.message
    } finally {
      addingKey = ''
    }
  }

  function closeOnBackdrop(event) {
    if (event.target === event.currentTarget) {
      onClose()
    }
  }

  function handleKeydown(event) {
    if (isOpen && event.key === 'Escape') {
      onClose()
    }
  }
</script>

<svelte:window onkeydown={handleKeydown} />

{#if isOpen}
  <div class="fixed inset-0 z-50 flex items-start justify-center overflow-y-auto bg-slate-950/80 p-4 backdrop-blur-sm sm:items-center" role="presentation" onclick={closeOnBackdrop}>
    <div class="flex max-h-[85vh] w-full max-w-3xl flex-col overflow-hidden rounded-2xl border border-slate-800 bg-slate-900 text-slate-100 shadow-2xl shadow-slate-950/60" role="dialog" aria-modal="true" aria-labelledby="search-title">
      <div class="flex items-start justify-between gap-4 px-5 pt-5 sm:px-6">
        <div>
          <p class="text-xs font-semibold uppercase tracking-[0.2em] text-blue-300">Внешние базы</p>
          <h2 id="search-title" class="mt-1 text-xl font-semibold text-white">Поиск тайтлов</h2>
        </div>
        <button type="button" class="inline-flex h-9 w-9 items-center justify-center rounded-lg text-slate-400 transition hover:bg-slate-800 hover:text-white focus:outline-none focus:ring-2 focus:ring-blue-400" aria-label="Закрыть" onclick={onClose}>
          <svg viewBox="0 0 24 24" class="h-5 w-5" fill="none" stroke="currentColor" stroke-width="2" aria-hidden="true">
            <path d="m6 6 12 12M18 6 6 18" />
          </svg>
        </button>
      </div>

      <nav class="flex flex-wrap gap-2 px-5 pt-4 sm:px-6" aria-label="Категории поиска">
        {#each categories as category}
          <button
            type="button"
            aria-pressed={activeType === category.id}
            class={`rounded-full px-3.5 py-1.5 text-sm font-medium transition focus:outline-none focus:ring-2 focus:ring-blue-400 ${activeType === category.id ? 'bg-blue-500 text-white shadow-lg shadow-blue-950/30' : 'bg-slate-800 text-slate-300 hover:bg-slate-700 hover:text-white'}`}
            onclick={() => (activeType = category.id)}
          >
            {category.label}
          </button>
        {/each}
      </nav>

      <div class="px-5 pb-5 pt-4 sm:px-6">
        <label class="relative block">
          <span class="sr-only">Поиск тайтла</span>
          <svg viewBox="0 0 24 24" class="pointer-events-none absolute left-3 top-1/2 h-4 w-4 -translate-y-1/2 text-slate-500" fill="none" stroke="currentColor" stroke-width="2" aria-hidden="true">
            <circle cx="11" cy="11" r="6" />
            <path d="m16 16 4 4" />
          </svg>
          <input
            bind:this={searchInput}
            bind:value={query}
            class="w-full rounded-lg border border-slate-700 bg-slate-800 py-2.5 pl-9 pr-3 text-sm text-white outline-none transition placeholder:text-slate-500 focus:border-blue-400 focus:ring-2 focus:ring-blue-400/20"
            type="search"
            placeholder={`Поиск: ${activeCategory.label.toLowerCase()}…`}
            autocomplete="off"
          />
        </label>
      </div>

      <div class="min-h-72 flex-1 overflow-y-auto border-t border-slate-800 px-5 py-4 sm:px-6">
        {#if addError}
          <p class="mb-4 rounded-lg border border-rose-500/40 bg-rose-500/10 px-3 py-2 text-sm text-rose-200" role="alert">{addError}</p>
        {/if}

        {#if !canSearch}
          <div class="flex min-h-64 flex-col items-center justify-center gap-3 text-center">
            <div class="flex h-12 w-12 items-center justify-center rounded-2xl bg-slate-800 text-slate-400">
              <svg viewBox="0 0 24 24" class="h-6 w-6" fill="none" stroke="currentColor" stroke-width="1.75" aria-hidden="true">
                <circle cx="11" cy="11" r="6" />
                <path d="m16 16 4 4" />
              </svg>
            </div>
            <p class="text-sm text-slate-400">Введите название для поиска...</p>
            <p class="text-xs text-slate-500">Минимум 2 символа — результаты подтянутся из внешних баз.</p>
          </div>
        {:else if searching}
          <div class="space-y-3" aria-hidden="true">
            {#each [0, 1, 2] as row (row)}
              <div class="flex gap-4 rounded-xl border border-slate-800 bg-slate-950/40 p-3">
                <div class="h-28 w-20 shrink-0 animate-pulse rounded-lg bg-slate-800"></div>
                <div class="flex-1 space-y-2 py-1">
                  <div class="h-4 w-1/2 animate-pulse rounded bg-slate-800"></div>
                  <div class="h-3 w-1/3 animate-pulse rounded bg-slate-800/70"></div>
                  <div class="h-3 w-full animate-pulse rounded bg-slate-800/70"></div>
                  <div class="h-3 w-4/5 animate-pulse rounded bg-slate-800/70"></div>
                </div>
              </div>
            {/each}
          </div>
          <p class="sr-only" role="status">Идёт поиск…</p>
        {:else if searchError}
          <div class="flex min-h-64 flex-col items-center justify-center gap-2 text-center">
            <p class="text-sm text-rose-200">{searchError}</p>
            <p class="text-xs text-slate-500">Проверьте соединение и попробуйте другой запрос.</p>
          </div>
        {:else if results.length === 0}
          <div class="flex min-h-64 flex-col items-center justify-center gap-2 text-center">
            <p class="text-sm font-semibold text-slate-200">Ничего не найдено</p>
            <p class="text-xs text-slate-500">Попробуйте изменить запрос или выбрать другую категорию.</p>
          </div>
        {:else}
          <ul class="space-y-3">
            {#each results as result (resultKey(result))}
              {@const key = resultKey(result)}
              <li class="flex gap-4 rounded-xl border border-slate-800 bg-slate-950/40 p-3 transition hover:border-slate-700">
                <div class="h-28 w-20 shrink-0 overflow-hidden rounded-lg border border-slate-800 bg-slate-800">
                  {#if result.coverUrl}
                    <img src={result.coverUrl} alt={result.title} class="h-full w-full object-cover" loading="lazy" />
                  {:else}
                    <div class="flex h-full w-full items-center justify-center bg-gradient-to-br from-slate-700 to-slate-900 text-slate-500">
                      <svg viewBox="0 0 24 24" class="h-8 w-8" fill="none" stroke="currentColor" stroke-width="1.25" aria-hidden="true">
                        <path d="M4 5.5A2.5 2.5 0 0 1 6.5 3H20v16.5A1.5 1.5 0 0 1 18.5 21H6a2 2 0 0 1-2-2V5.5Z" />
                        <path d="M8 7h8M8 11h8M8 15h5" />
                      </svg>
                    </div>
                  {/if}
                </div>

                <div class="min-w-0 flex-1 space-y-1.5">
                  <div class="flex items-start justify-between gap-3">
                    <div class="min-w-0">
                      <h3 class="truncate text-sm font-semibold text-white" title={result.title}>{result.title}</h3>
                      {#if result.originalTitle}
                        <p class="truncate text-xs text-slate-500" title={result.originalTitle}>{result.originalTitle}</p>
                      {/if}
                    </div>

                    <div class="shrink-0">
                      {#if addedKeys[key]}
                        <span class="inline-flex items-center gap-1.5 rounded-lg border border-emerald-500/40 bg-emerald-500/15 px-3 py-1.5 text-xs font-semibold text-emerald-300">
                          В библиотеке
                          <svg viewBox="0 0 24 24" class="h-3.5 w-3.5" fill="none" stroke="currentColor" stroke-width="2.5" aria-hidden="true">
                            <path d="m5 13 4 4L19 7" />
                          </svg>
                        </span>
                      {:else}
                        <button
                          type="button"
                          class="inline-flex items-center gap-1.5 rounded-lg bg-blue-500 px-3 py-1.5 text-xs font-semibold text-white shadow-lg shadow-blue-950/40 transition hover:bg-blue-400 focus:outline-none focus:ring-2 focus:ring-blue-300 disabled:cursor-wait disabled:opacity-70"
                          disabled={Boolean(addingKey)}
                          onclick={() => addResult(result)}
                        >
                          {#if addingKey === key}
                            <svg viewBox="0 0 24 24" class="h-3.5 w-3.5 animate-spin" fill="none" aria-hidden="true">
                              <circle cx="12" cy="12" r="9" stroke="currentColor" stroke-opacity="0.25" stroke-width="4" />
                              <path d="M21 12a9 9 0 0 0-9-9" stroke="currentColor" stroke-width="4" stroke-linecap="round" />
                            </svg>
                            Добавление…
                          {:else}
                            <svg viewBox="0 0 24 24" class="h-3.5 w-3.5" fill="none" stroke="currentColor" stroke-width="2.5" aria-hidden="true">
                              <path d="M12 5v14M5 12h14" />
                            </svg>
                            Добавить
                          {/if}
                        </button>
                      {/if}
                    </div>
                  </div>

                  <div class="flex flex-wrap items-center gap-2 text-xs text-slate-400">
                    {#if metaLine(result)}
                      <span class="truncate">{metaLine(result)}</span>
                    {/if}
                    {#if countLabel(result)}
                      <span class="rounded-full bg-slate-800 px-2 py-0.5 text-[11px] font-medium text-slate-300">{countLabel(result)}</span>
                    {/if}
                  </div>

                  {#if result.description}
                    <p class="line-clamp-2 text-xs leading-5 text-slate-400">{result.description}</p>
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
