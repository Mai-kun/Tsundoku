<script>
  import { incrementProgress } from '../api.js'

  const statusStyles = {
    0: { label: 'В планах', className: 'bg-slate-500/90 text-slate-100' },
    1: { label: 'В процессе', className: 'bg-blue-500/90 text-white' },
    2: { label: 'Пройдено', className: 'bg-emerald-500/90 text-white' },
    3: { label: 'На паузе', className: 'bg-amber-500/90 text-slate-950' },
    4: { label: 'Брошено', className: 'bg-rose-500/90 text-white' },
  }

  let { item, onUpdate = () => {}, onDelete = () => {} } = $props()

  let updating = $state(false)
  let deleting = $state(false)
  let error = $state('')
  let failedCoverId = $state(null)

  let type = $derived(resolveType(item))
  let status = $derived(statusStyles[item.status] ?? statusStyles[0])
  let metadata = $derived(getMetadata(item, type))
  let progress = $derived(getProgress(item, type))
  let increment = $derived(getIncrement(item, type))
  let hasCover = $derived(Boolean(item.coverUrl?.trim()) && failedCoverId !== item.id)

  function resolveType(media) {
    if (media.type) {
      return media.type.toLowerCase()
    }

    if ('platform' in media) return 'game'
    if ('author' in media) return 'book'
    if ('currentChapter' in media || 'totalChapters' in media || 'currentVolume' in media) return 'manga'
    if ('durationMinutes' in media) return 'movie'
    if ('network' in media || 'seasons' in media) return 'tvshow'
    return 'media'
  }

  function getMetadata(media, mediaType) {
    const labels = {
      game: 'Игра',
      movie: 'Фильм',
      tvshow: 'Сериал',
      book: 'Книга',
      manga: 'Манга',
      media: 'Медиа',
    }
    const detail =
      mediaType === 'game'
        ? media.platform
        : mediaType === 'book'
          ? media.author
          : mediaType === 'manga'
            ? media.currentVolume
              ? `Том ${media.currentVolume}`
              : null
            : mediaType === 'movie'
              ? media.studio || media.director
              : media.network || media.studio

    return [labels[mediaType], detail].filter(Boolean).join(' · ')
  }

  function getProgress(media, mediaType) {
    if (mediaType === 'book') {
      return `${media.currentPage ?? 0} / ${media.totalPages ?? 0} стр.`
    }

    if (mediaType === 'manga') {
      return `гл. ${media.currentChapter ?? 0}${media.totalChapters ? ` / ${media.totalChapters}` : ''}`
    }

    if (mediaType === 'game') {
      return `${media.hoursPlayed ?? 0} ч.`
    }

    if (mediaType === 'movie') {
      return `${media.durationMinutes ?? 0} мин.`
    }

    return null
  }

  function getIncrement(media, mediaType) {
    if (mediaType === 'book') {
      return { key: 'currentPage', value: (media.currentPage ?? 0) + 1, label: '+1 стр.' }
    }

    if (mediaType === 'manga') {
      return { key: 'currentChapter', value: (media.currentChapter ?? 0) + 1, label: '+1 гл.' }
    }

    if (mediaType === 'game') {
      return { key: 'hoursPlayed', value: (media.hoursPlayed ?? 0) + 1, label: '+1 ч.' }
    }

    return null
  }

  async function increaseProgress() {
    if (!increment || updating) return

    updating = true
    error = ''

    try {
      await incrementProgress(item.id, increment.value)
      onUpdate({ ...item, [increment.key]: increment.value })
    } catch (requestError) {
      error = requestError.message
    } finally {
      updating = false
    }
  }

  async function removeItem() {
    if (deleting || !window.confirm(`Удалить «${item.title}»?`)) return

    deleting = true
    error = ''

    try {
      await onDelete(item)
    } catch (requestError) {
      error = requestError.message
    } finally {
      deleting = false
    }
  }
</script>

<article class="group relative min-w-0">
  <div class="relative aspect-[2/3] overflow-hidden rounded-xl border border-slate-700/70 bg-slate-800 shadow-lg shadow-slate-950/20">
    {#if hasCover}
      <img
        src={item.coverUrl}
        alt={item.title}
        class="h-full w-full object-cover transition duration-300 group-hover:scale-105"
        onerror={() => (failedCoverId = item.id)}
      />
    {:else}
      <div class="flex h-full w-full items-center justify-center bg-gradient-to-br from-slate-700 to-slate-900 text-slate-500">
        <svg viewBox="0 0 24 24" class="h-12 w-12" fill="none" stroke="currentColor" stroke-width="1.25" aria-hidden="true">
          <path d="M4 5.5A2.5 2.5 0 0 1 6.5 3H20v16.5A1.5 1.5 0 0 1 18.5 21H6a2 2 0 0 1-2-2V5.5Z" />
          <path d="M8 7h8M8 11h8M8 15h5" />
        </svg>
      </div>
    {/if}

    <span class={`absolute left-2 top-2 rounded-full px-2 py-1 text-[10px] font-semibold shadow-sm ${status.className}`}>
      {status.label}
    </span>

    <button
      type="button"
      class="absolute right-2 top-2 inline-flex h-8 w-8 items-center justify-center rounded-full bg-slate-950/75 text-slate-200 opacity-0 transition hover:bg-rose-500 hover:text-white focus:opacity-100 focus:outline-none focus:ring-2 focus:ring-rose-300 group-hover:opacity-100 disabled:cursor-wait"
      aria-label={`Удалить ${item.title}`}
      title="Удалить"
      disabled={deleting}
      onclick={removeItem}
    >
      <svg viewBox="0 0 24 24" class="h-4 w-4" fill="none" stroke="currentColor" stroke-width="2" aria-hidden="true">
        <path d="M3 6h18M8 6V4h8v2m-9 0 1 14h8l1-14M10 10v6m4-6v6" />
      </svg>
    </button>
  </div>

  <div class="space-y-2 pt-3">
    <h2 class="line-clamp-2 min-h-10 text-sm font-semibold leading-5 text-slate-100" title={item.title}>{item.title}</h2>
    <p class="truncate text-xs text-slate-400" title={metadata}>{metadata}</p>

    {#if progress}
      <p class="text-xs font-medium text-slate-300">{progress}</p>
    {/if}

    {#if increment}
      <button
        type="button"
        class="w-full rounded-lg border border-slate-700 bg-slate-800 px-2 py-1.5 text-xs font-medium text-slate-200 transition hover:border-blue-400 hover:bg-blue-500/15 hover:text-blue-200 focus:outline-none focus:ring-2 focus:ring-blue-400 disabled:cursor-wait disabled:opacity-60"
        disabled={updating}
        onclick={increaseProgress}
      >
        {updating ? 'Сохранение…' : increment.label}
      </button>
    {/if}

    {#if error}
      <p class="text-xs text-rose-300" role="alert">{error}</p>
    {/if}
  </div>
</article>
