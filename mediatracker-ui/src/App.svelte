<script>
  import { deleteMedia, getMedia } from './lib/api.js'
  import CreateModal from './lib/components/CreateModal.svelte'
  import MediaCard from './lib/components/MediaCard.svelte'
  import SearchModal from './lib/components/SearchModal.svelte'

  const categories = [
    { id: 'all', label: 'Все' },
    { id: 'game', label: 'Игры' },
    { id: 'movie', label: 'Фильмы' },
    { id: 'tvshow', label: 'Сериалы' },
    { id: 'anime', label: 'Аниме' },
    { id: 'book', label: 'Книги' },
    { id: 'manga', label: 'Манга' },
  ]

  const statuses = [
    { id: 'all', label: 'Все' },
    { id: 1, label: 'В процессе' },
    { id: 0, label: 'В планах' },
    { id: 2, label: 'Пройдено' },
  ]

  let items = $state([])
  let activeCategory = $state('all')
  let activeStatus = $state('all')
  let search = $state('')
  let loading = $state(true)
  let error = $state('')
  let showCreateModal = $state(false)
  let showSearchModal = $state(false)
  let requestSequence = 0

  let filters = $derived({
    type: activeCategory === 'all' || activeCategory === 'anime' ? undefined : activeCategory,
    status: activeStatus === 'all' ? undefined : activeStatus,
    isAnime: activeCategory === 'anime' ? true : undefined,
    search: search.trim() || undefined,
  })

  $effect(() => {
    const currentFilters = filters
    const delay = window.setTimeout(() => loadMedia(currentFilters), search ? 250 : 0)

    return () => window.clearTimeout(delay)
  })

  async function loadMedia(filtersToLoad = filters) {
    const sequence = ++requestSequence
    loading = true
    error = ''

    try {
      const media = await getMedia(filtersToLoad)

      if (sequence === requestSequence) {
        items = media
      }
    } catch (requestError) {
      if (sequence === requestSequence) {
        error = requestError.message
      }
    } finally {
      if (sequence === requestSequence) {
        loading = false
      }
    }
  }

  function updateItem(updatedItem) {
    items = items.map((item) => (item.id === updatedItem.id ? updatedItem : item))
  }

  async function removeItem(item) {
    await deleteMedia(item.id)
    items = items.filter((currentItem) => currentItem.id !== item.id)
  }

  function handleCreated() {
    showCreateModal = false
    loadMedia()
  }

  function handleMediaAdded() {
    loadMedia()
  }

  function handleGlobalKeydown(event) {
    if ((event.ctrlKey || event.metaKey) && event.key.toLowerCase() === 'k') {
      event.preventDefault()
      showSearchModal = true
    }
  }
</script>

<svelte:window onkeydown={handleGlobalKeydown} />

<svelte:head>
  <title>MediaTracker</title>
  <meta name="description" content="Личный трекер игр, фильмов, книг и манги" />
</svelte:head>

<main class="min-h-screen bg-[#0f172a] text-slate-100">
  <div class="mx-auto max-w-7xl px-4 py-6 sm:px-6 lg:px-8">
    <header class="flex flex-col gap-5 border-b border-slate-800 pb-6 lg:flex-row lg:items-center lg:justify-between">
      <div class="flex items-center gap-3">
        <div class="flex h-11 w-11 items-center justify-center rounded-xl bg-blue-500/15 text-blue-300 ring-1 ring-inset ring-blue-400/30">
          <svg viewBox="0 0 24 24" class="h-6 w-6" fill="none" stroke="currentColor" stroke-width="1.75" aria-hidden="true">
            <path d="M4 5.5A2.5 2.5 0 0 1 6.5 3H20v16.5A1.5 1.5 0 0 1 18.5 21H6a2 2 0 0 1-2-2V5.5Z" />
            <path d="M8 7h8M8 11h8M8 15h5" />
          </svg>
        </div>
        <div>
          <p class="text-xs font-semibold uppercase tracking-[0.18em] text-blue-300">Личная библиотека</p>
          <h1 class="text-xl font-bold tracking-tight text-white sm:text-2xl">MediaTracker</h1>
        </div>
      </div>

      <div class="flex w-full flex-col gap-3 sm:flex-row lg:w-auto">
        <label class="relative min-w-0 sm:w-72">
          <span class="sr-only">Поиск по названию</span>
          <svg viewBox="0 0 24 24" class="pointer-events-none absolute left-3 top-1/2 h-4 w-4 -translate-y-1/2 text-slate-500" fill="none" stroke="currentColor" stroke-width="2" aria-hidden="true">
            <circle cx="11" cy="11" r="6" />
            <path d="m16 16 4 4" />
          </svg>
          <input
            class="w-full rounded-lg border border-slate-700 bg-slate-800 py-2.5 pl-9 pr-3 text-sm text-white outline-none transition placeholder:text-slate-500 focus:border-blue-400 focus:ring-2 focus:ring-blue-400/20"
            type="search"
            placeholder="Поиск по названию"
            bind:value={search}
          />
        </label>
        <button
          type="button"
          class="inline-flex items-center justify-center gap-2 rounded-lg border border-slate-700 bg-slate-800 px-4 py-2.5 text-sm font-semibold text-slate-200 transition hover:border-blue-400/60 hover:bg-slate-700 hover:text-white focus:outline-none focus:ring-2 focus:ring-blue-400"
          title="Поиск тайтлов — Ctrl+K"
          onclick={() => (showSearchModal = true)}
        >
          <svg viewBox="0 0 24 24" class="h-4 w-4" fill="none" stroke="currentColor" stroke-width="2" aria-hidden="true">
            <circle cx="11" cy="11" r="6" />
            <path d="m16 16 4 4" />
          </svg>
          Поиск тайтлов
          <kbd class="hidden rounded border border-slate-600 bg-slate-900 px-1.5 py-0.5 text-[10px] font-medium text-slate-400 lg:inline">Ctrl K</kbd>
        </button>
        <button type="button" class="inline-flex items-center justify-center gap-2 rounded-lg bg-blue-500 px-4 py-2.5 text-sm font-semibold text-white shadow-lg shadow-blue-950/40 transition hover:bg-blue-400 focus:outline-none focus:ring-2 focus:ring-blue-300" onclick={() => (showCreateModal = true)}>
          <svg viewBox="0 0 24 24" class="h-4 w-4" fill="none" stroke="currentColor" stroke-width="2.5" aria-hidden="true">
            <path d="M12 5v14M5 12h14" />
          </svg>
          Добавить медиа
        </button>
      </div>
    </header>

    <section class="space-y-4 py-6" aria-label="Фильтры библиотеки">
      <nav class="flex gap-2 overflow-x-auto pb-1" aria-label="Категории">
        {#each categories as category}
          <button
            type="button"
            class={`whitespace-nowrap rounded-full px-3.5 py-2 text-sm font-medium transition focus:outline-none focus:ring-2 focus:ring-blue-400 ${activeCategory === category.id ? 'bg-blue-500 text-white shadow-lg shadow-blue-950/30' : 'bg-slate-800 text-slate-300 hover:bg-slate-700 hover:text-white'}`}
            onclick={() => (activeCategory = category.id)}
          >
            {category.label}
          </button>
        {/each}
      </nav>

      <nav class="flex flex-wrap gap-2" aria-label="Статус">
        {#each statuses as status}
          <button
            type="button"
            class={`rounded-lg border px-3 py-1.5 text-xs font-semibold transition focus:outline-none focus:ring-2 focus:ring-blue-400 ${activeStatus === status.id ? 'border-blue-400/60 bg-blue-500/15 text-blue-200' : 'border-slate-700 bg-slate-900/40 text-slate-400 hover:border-slate-600 hover:text-slate-200'}`}
            onclick={() => (activeStatus = status.id)}
          >
            {status.label}
          </button>
        {/each}
      </nav>
    </section>

    {#if loading}
      <div class="flex min-h-72 items-center justify-center rounded-2xl border border-slate-800 bg-slate-900/30 text-sm text-slate-400">Загрузка библиотеки…</div>
    {:else if error}
      <div class="flex min-h-72 flex-col items-center justify-center gap-4 rounded-2xl border border-rose-500/30 bg-rose-500/5 p-6 text-center">
        <p class="text-sm text-rose-200">{error}</p>
        <button type="button" class="rounded-lg border border-rose-400/50 px-3 py-2 text-sm font-medium text-rose-100 transition hover:bg-rose-500/15" onclick={() => loadMedia()}>Повторить</button>
      </div>
    {:else if items.length === 0}
      <div class="flex min-h-72 flex-col items-center justify-center rounded-2xl border border-dashed border-slate-700 bg-slate-900/30 p-6 text-center">
        <div class="mb-4 flex h-14 w-14 items-center justify-center rounded-2xl bg-slate-800 text-slate-400">
          <svg viewBox="0 0 24 24" class="h-7 w-7" fill="none" stroke="currentColor" stroke-width="1.5" aria-hidden="true">
            <path d="M4 5.5A2.5 2.5 0 0 1 6.5 3H20v16.5A1.5 1.5 0 0 1 18.5 21H6a2 2 0 0 1-2-2V5.5Z" />
            <path d="M8 7h8M8 11h8M8 15h5" />
          </svg>
        </div>
        <p class="text-base font-semibold text-slate-200">Ничего не найдено, добавьте первый тайтл!</p>
        <p class="mt-1 text-sm text-slate-500">Соберите здесь всё, что хотите пройти, прочитать или посмотреть.</p>
      </div>
    {:else}
      <section class="grid grid-cols-2 gap-4 sm:grid-cols-3 md:grid-cols-4 lg:grid-cols-6" aria-label="Медиатека">
        {#each items as item (item.id)}
          <MediaCard {item} onUpdate={updateItem} onDelete={removeItem} />
        {/each}
      </section>
    {/if}
  </div>
</main>

{#if showCreateModal}
  <CreateModal onClose={() => (showCreateModal = false)} onCreated={handleCreated} />
{/if}

<SearchModal
  isOpen={showSearchModal}
  initialType={activeCategory === 'all' ? 'anime' : activeCategory}
  onClose={() => (showSearchModal = false)}
  onMediaAdded={handleMediaAdded}
/>
