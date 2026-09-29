<script module lang="ts">
  import type { LibrarySort } from '../media/FilterBar.svelte'

  let savedHomeSort: LibrarySort = 'newest'
</script>

<script lang="ts">
  import { deleteMedia, getMedia, getMediaItem, setProgress, setSeasonProgress } from '$lib/api'
  import { showToast } from '$lib/stores/toast.svelte'
  import { i18n } from '$lib/i18n/index.svelte'
  import { MEDIA_STATUS, isTvShowDetail, type MediaItem } from '$lib/types'
  import MediaGrid from '../media/MediaGrid.svelte'

  interface Props {
    refreshKey: number
    onOpen: (item: MediaItem) => void
    onMediaChanged: () => void
    onEdit?: (item: MediaItem) => void
  }

  let { refreshKey, onOpen, onMediaChanged, onEdit = () => {} }: Props = $props()

  let inProgress = $state<MediaItem[]>([])
  let upNext = $state<MediaItem[]>([])
  let recentlyCompleted = $state<MediaItem[]>([])
  let loading = $state(true)
  let loadError = $state<unknown>(null)
  let sort = $state<LibrarySort>(savedHomeSort)
  let requestSequence = 0
  let hasLoaded = false

  $effect(() => {
    savedHomeSort = sort
  })

  $effect(() => {
    void refreshKey
    void sort
    const isInitial = !hasLoaded
    void loadSections(++requestSequence, isInitial)
  })

  function sortFilters(value: LibrarySort) {
    switch (value) {
      case 'newest':
        return { sortBy: 'createdAt' as const, sortOrder: 'desc' as const }
      case 'oldest':
        return { sortBy: 'createdAt' as const, sortOrder: 'asc' as const }
      case 'rating':
        return { sortBy: 'score' as const, sortOrder: 'desc' as const }
      case 'title':
        return { sortBy: 'title' as const, sortOrder: 'asc' as const }
    }
  }

  async function loadSections(sequence: number, showLoading = true) {
    if (showLoading) {
      loading = true
    }
    loadError = null

    try {
      const sortParams = sortFilters(sort)
      const [active, planned, completed] = await Promise.all([
        getMedia({ status: MEDIA_STATUS.inProgress, ...sortParams }),
        getMedia({ status: MEDIA_STATUS.planned, ...sortParams }),
        getMedia({ status: MEDIA_STATUS.completed, ...sortParams }),
      ])

      if (sequence === requestSequence) {
        hasLoaded = true
        inProgress = active
        upNext = planned
        recentlyCompleted = completed.toSorted((left, right) => {
          if (sort === 'rating') {
            return (right.score ?? 0) - (left.score ?? 0)
          }
          if (sort === 'title') {
            return left.title.localeCompare(right.title)
          }
          if (sort === 'oldest') {
            const leftTime = left.finishedAt ? Date.parse(left.finishedAt) : Date.parse(left.createdAt)
            const rightTime = right.finishedAt ? Date.parse(right.finishedAt) : Date.parse(right.createdAt)
            return leftTime - rightTime
          }
          const leftTime = left.finishedAt ? Date.parse(left.finishedAt) : 0
          const rightTime = right.finishedAt ? Date.parse(right.finishedAt) : 0
          return rightTime - leftTime
        })
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

  function refresh() {
    void loadSections(++requestSequence, false)
  }

  async function updateProgress(id: string, currentProgress: number) {
    const updateInList = (list: MediaItem[]) =>
      list.map((item) => {
        if (item.id !== id) return item
        if (item.type === 'game') return { ...item, hoursPlayed: currentProgress }
        if (item.type === 'book') return { ...item, currentPage: currentProgress }
        if (item.type === 'manga') return { ...item, currentChapter: currentProgress }
        return item
      })
    inProgress = updateInList(inProgress)
    upNext = updateInList(upNext)
    recentlyCompleted = updateInList(recentlyCompleted)
    await setProgress(id, currentProgress)
  }

  async function removeItem(item: MediaItem): Promise<void> {
    const main = document.querySelector('main')
    const currentScroll = main ? main.scrollTop : (typeof window !== 'undefined' ? window.scrollY : 0)

    const prevInProgress = inProgress
    const prevUpNext = upNext
    const prevCompleted = recentlyCompleted

    inProgress = inProgress.filter((i) => i.id !== item.id)
    upNext = upNext.filter((i) => i.id !== item.id)
    recentlyCompleted = recentlyCompleted.filter((i) => i.id !== item.id)

    onMediaChanged()

    try {
      await deleteMedia(item.id)
    } catch {
      inProgress = prevInProgress
      upNext = prevUpNext
      recentlyCompleted = prevCompleted
      showToast(i18n.t.errors.unexpected, 'error')
    }

    setTimeout(() => {
      if (main && Math.abs(main.scrollTop - currentScroll) > 5) {
        main.scrollTop = currentScroll
      }
    }, 20)
  }

  // Bug 6: step episode for tvshow cards on Home screen optimistically
  async function stepEpisode(item: MediaItem, delta: number) {
    if (item.type !== 'tvshow') return
    const prevWatched = item.totalEpisodesWatched ?? 0
    const nextWatched = Math.max(0, prevWatched + delta)
    item.totalEpisodesWatched = nextWatched
    inProgress = [...inProgress]

    try {
      const detail = await getMediaItem(item.id)
      if (!isTvShowDetail(detail) || !detail.seasons?.length) return

      const activeSeason =
        detail.seasons.find((s) => s.status === MEDIA_STATUS.inProgress) ??
        detail.seasons.find((s) => s.status === MEDIA_STATUS.planned) ??
        detail.seasons[detail.seasons.length - 1]

      if (!activeSeason) return

      const next = Math.max(0, Math.min(
        (activeSeason.currentEpisode ?? 0) + delta,
        activeSeason.totalEpisodes > 0 ? activeSeason.totalEpisodes : Infinity
      ))

      await setSeasonProgress(activeSeason.id, next)
      onMediaChanged()
    } catch {
      item.totalEpisodesWatched = prevWatched
      inProgress = [...inProgress]
      showToast(i18n.t.errors.unexpected, 'error')
    }
  }
</script>

<div class="space-y-10">
  <section class="space-y-4">
    <div class="flex items-end justify-between gap-4">
      <div>
        <p class="text-xs font-semibold uppercase tracking-[0.18em] text-accent-soft">{i18n.t.library.collectionLabel}</p>
        <h2 class="mt-1 text-xl font-bold tracking-tight text-ink">{i18n.t.views.inProgress}</h2>
      </div>
      <div class="flex items-center gap-2">
        <label class="sr-only" for="home-sort">{i18n.t.sort.label}</label>
        <select
          id="home-sort"
          class="h-8 rounded-md border border-border bg-card px-2.5 text-xs font-medium text-ink outline-none focus:border-accent focus:ring-2 focus:ring-accent/30"
          value={sort}
          onchange={(e) => (sort = (e.currentTarget as HTMLSelectElement).value as LibrarySort)}
        >
          <option value="newest">{i18n.t.sort.newest}</option>
          <option value="oldest">{i18n.t.sort.oldest}</option>
          <option value="rating">{i18n.t.sort.rating}</option>
          <option value="title">{i18n.t.sort.title}</option>
        </select>
      </div>
    </div>
    <MediaGrid items={inProgress} {loading} error={loadError} onRetry={refresh} onOpen={onOpen} onProgress={updateProgress} onProgressCommitted={onMediaChanged} onDelete={removeItem} onEdit={onEdit} onEpisodeStep={stepEpisode} />
  </section>

  <section class="space-y-4">
    <h2 class="text-xl font-bold tracking-tight text-ink">{i18n.t.views.upNext}</h2>
    <MediaGrid items={upNext} {loading} error={loadError} onRetry={refresh} onOpen={onOpen} onProgress={updateProgress} onProgressCommitted={onMediaChanged} onDelete={removeItem} onEdit={onEdit} />
  </section>

  <section class="space-y-4">
    <h2 class="text-xl font-bold tracking-tight text-ink">{i18n.t.views.recentlyCompleted}</h2>
    <MediaGrid items={recentlyCompleted} {loading} error={loadError} onRetry={refresh} onOpen={onOpen} onProgress={updateProgress} onProgressCommitted={onMediaChanged} onDelete={removeItem} onEdit={onEdit} />
  </section>
</div>

