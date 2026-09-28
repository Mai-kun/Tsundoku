<script lang="ts">
  import { deleteMedia, getMedia, getMediaItem, setProgress, setSeasonProgress } from '$lib/api'
  import { i18n } from '$lib/i18n/index.svelte'
  import { isTvShowDetail, MEDIA_STATUS, type MediaFilters, type MediaItem, type StatusFilter } from '$lib/types'
  import FilterBar, { type GroupBy, type LibrarySort } from '../media/FilterBar.svelte'
  import MediaGrid from '../media/MediaGrid.svelte'

  export type Category = 'tvshow' | 'movie' | 'anime' | 'manga' | 'game' | 'book'

  interface Props {
    category: Category
    refreshKey: number
    onOpen: (item: MediaItem) => void
    onMediaChanged: () => void
    onEdit?: (item: MediaItem) => void
  }

  let { category, refreshKey, onOpen, onMediaChanged, onEdit = () => {} }: Props = $props()

  let status = $state<StatusFilter>('all')
  let sort = $state<LibrarySort>('newest')
  let groupBy = $state<GroupBy>('status')
  let search = $state('')
  let allItems = $state<MediaItem[]>([])
  let loading = $state(true)
  let loadError = $state<unknown>(null)
  let requestSequence = 0

  let filteredItems = $derived(status === 'all' ? allItems : allItems.filter((item) => item.status === status))
  let statusCounts = $derived(countStatuses(allItems))

  const statusSections = $derived([
    { status: MEDIA_STATUS.inProgress, title: i18n.t.status.inProgress },
    { status: MEDIA_STATUS.planned, title: i18n.t.status.planned },
    { status: MEDIA_STATUS.completed, title: i18n.t.status.completed },
    { status: MEDIA_STATUS.onHold, title: i18n.t.status.paused },
    { status: MEDIA_STATUS.dropped, title: i18n.t.status.dropped },
  ])

  let statusGroups = $derived.by(() => {
    return statusSections
      .map((sec) => ({
        status: sec.status,
        title: sec.title,
        items: filteredItems.filter((item) => item.status === sec.status),
      }))
      .filter((sec) => (status === 'all' ? sec.items.length > 0 : sec.status === status))
  })

  interface FranchiseGroup {
    name: string
    items: MediaItem[]
  }

  let franchiseGroups = $derived.by<FranchiseGroup[]>(() => {
    const map = new Map<string, MediaItem[]>()
    const noFranchise: MediaItem[] = []

    for (const item of filteredItems) {
      const name = item.franchiseName?.trim()
      if (name) {
        if (!map.has(name)) map.set(name, [])
        map.get(name)!.push(item)
      } else {
        noFranchise.push(item)
      }
    }

    const groups: FranchiseGroup[] = Array.from(map.entries()).map(([name, list]) => ({
      name,
      items: list,
    }))

    if (noFranchise.length > 0) {
      groups.push({
        name: i18n.t.grouping.noFranchise,
        items: noFranchise,
      })
    }

    return groups
  })

  $effect(() => {
    void refreshKey
    void category
    void search
    void sort
    const sequence = ++requestSequence
    const delay = search.trim() ? 500 : 0
    const timer = setTimeout(() => void loadItems(sequence), delay)

    return () => clearTimeout(timer)
  })

  function categoryFilters(): MediaFilters {
    const filters: MediaFilters = {
      search: search.trim() || undefined,
      ...sortFilters(sort),
    }

    switch (category) {
      case 'anime':
        return { ...filters, isAnime: true }
      case 'tvshow':
        return { ...filters, type: 'tvshow', isAnime: false }
      case 'movie':
        return { ...filters, type: 'movie', isAnime: false }
      default:
        return { ...filters, type: category }
    }
  }

  function sortFilters(value: LibrarySort): Pick<MediaFilters, 'sortBy' | 'sortOrder'> {
    switch (value) {
      case 'oldest':
        return { sortBy: 'createdAt', sortOrder: 'asc' }
      case 'rating':
        return { sortBy: 'score', sortOrder: 'desc' }
      case 'title':
        return { sortBy: 'title', sortOrder: 'asc' }
      default:
        return { sortBy: 'createdAt', sortOrder: 'desc' }
    }
  }

  async function loadItems(sequence: number) {
    if (allItems.length === 0) {
      loading = true
    }
    loadError = null

    try {
      const found = await getMedia(categoryFilters())
      if (sequence === requestSequence) {
        allItems = found
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
    void loadItems(++requestSequence)
  }

  async function updateProgress(id: string, currentProgress: number) {
    await setProgress(id, currentProgress)
  }

  function countStatuses(list: MediaItem[]): Partial<Record<StatusFilter, number>> {
    const counts: Partial<Record<StatusFilter, number>> = { all: list.length }

    for (const value of [MEDIA_STATUS.planned, MEDIA_STATUS.inProgress, MEDIA_STATUS.completed, MEDIA_STATUS.onHold, MEDIA_STATUS.dropped]) {
      counts[value] = list.filter((item) => item.status === value).length
    }

    return counts
  }

  async function removeItem(item: MediaItem) {
    const main = document.querySelector('main')
    const currentScroll = main ? main.scrollTop : (typeof window !== 'undefined' ? window.scrollY : 0)

    allItems = allItems.filter((i) => i.id !== item.id)
    await deleteMedia(item.id)
    onMediaChanged()

    setTimeout(() => {
      if (main && Math.abs(main.scrollTop - currentScroll) > 5) {
        main.scrollTop = currentScroll
      }
    }, 20)
  }

  function updateStatus(value: StatusFilter) {
    status = value
  }

  async function stepEpisode(item: MediaItem, delta: number) {
    if (item.type !== 'tvshow') return
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
    refresh()
  }
</script>

<div class="space-y-6">
  <FilterBar
    {status}
    {sort}
    {groupBy}
    {search}
    counts={statusCounts}
    onStatusChange={updateStatus}
    onSortChange={(value) => (sort = value)}
    onGroupByChange={(value) => (groupBy = value)}
    onSearchChange={(value) => (search = value)}
  />

  <p class="text-xs font-medium text-muted">{i18n.t.library.resultCount(filteredItems.length)}</p>

  {#if loading && allItems.length === 0}
    <MediaGrid items={[]} loading={true} error={null} onRetry={refresh} onOpen={onOpen} onProgress={updateProgress} onProgressCommitted={onMediaChanged} onEpisodeStep={stepEpisode} onDelete={removeItem} onEdit={onEdit} />
  {:else if groupBy === 'status'}
    {#if statusGroups.length === 0 && !loading}
      <MediaGrid items={[]} {loading} error={loadError} onRetry={refresh} onOpen={onOpen} onProgress={updateProgress} onProgressCommitted={onMediaChanged} onEpisodeStep={stepEpisode} onDelete={removeItem} onEdit={onEdit} />
    {:else}
      <div class="space-y-8">
        {#each statusGroups as group (group.status)}
          <section class="space-y-3">
            <div class="flex items-center gap-2">
              <h2 class="text-base font-bold tracking-tight text-ink">{group.title}</h2>
              <span class="rounded-full bg-surface px-2.5 py-0.5 text-xs font-semibold text-muted">{group.items.length}</span>
            </div>
            <MediaGrid items={group.items} loading={false} error={null} onRetry={refresh} onOpen={onOpen} onProgress={updateProgress} onProgressCommitted={onMediaChanged} onEpisodeStep={stepEpisode} onDelete={removeItem} onEdit={onEdit} />
          </section>
        {/each}
      </div>
    {/if}
  {:else if groupBy === 'franchise'}
    {#if franchiseGroups.length === 0 && !loading}
      <MediaGrid items={[]} {loading} error={loadError} onRetry={refresh} onOpen={onOpen} onProgress={updateProgress} onProgressCommitted={onMediaChanged} onEpisodeStep={stepEpisode} onDelete={removeItem} onEdit={onEdit} />
    {:else}
      <div class="space-y-8">
        {#each franchiseGroups as group (group.name)}
          <section class="space-y-3">
            <div class="flex items-center gap-2">
              <h2 class="text-base font-bold tracking-tight text-ink">{group.name}</h2>
              <span class="rounded-full bg-surface px-2.5 py-0.5 text-xs font-semibold text-muted">{group.items.length}</span>
            </div>
            <MediaGrid items={group.items} loading={false} error={null} onRetry={refresh} onOpen={onOpen} onProgress={updateProgress} onProgressCommitted={onMediaChanged} onEpisodeStep={stepEpisode} onDelete={removeItem} onEdit={onEdit} />
          </section>
        {/each}
      </div>
    {/if}
  {:else}
    <MediaGrid items={filteredItems} {loading} error={loadError} onRetry={refresh} onOpen={onOpen} onProgress={updateProgress} onProgressCommitted={onMediaChanged} onEpisodeStep={stepEpisode} onDelete={removeItem} onEdit={onEdit} />
  {/if}
</div>
