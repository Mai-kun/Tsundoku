<script lang="ts">
  import { deleteMedia, getMedia, setProgress } from '$lib/api'
  import { i18n } from '$lib/i18n/index.svelte'
  import { MEDIA_STATUS, type MediaFilters, type MediaItem, type StatusFilter } from '$lib/types'
  import FilterBar, { type LibrarySort } from '../media/FilterBar.svelte'
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
  let search = $state('')
  let allItems = $state<MediaItem[]>([])
  let loading = $state(true)
  let loadError = $state<unknown>(null)
  let requestSequence = 0

  let items = $derived(status === 'all' ? allItems : allItems.filter((item) => item.status === status))
  let statusCounts = $derived(countStatuses(allItems))

  $effect(() => {
    void refreshKey
    void category
    void search
    void sort
    const sequence = ++requestSequence
    const delay = search.trim() ? 250 : 0
    const isInitial = allItems.length === 0
    const timer = setTimeout(() => void loadItems(sequence, isInitial), delay)

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

  async function loadItems(sequence: number, showLoading = true) {
    if (showLoading) {
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
    void loadItems(++requestSequence, false)
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
</script>

<div class="space-y-6">
  <FilterBar {status} {sort} {search} counts={statusCounts} onStatusChange={updateStatus} onSortChange={(value) => (sort = value)} onSearchChange={(value) => (search = value)} />
  <p class="text-xs font-medium text-muted">{i18n.t.library.resultCount(items.length)}</p>
  <MediaGrid {items} loading={loading} error={loadError} onRetry={refresh} onOpen={onOpen} onProgress={updateProgress} onProgressCommitted={onMediaChanged} onDelete={removeItem} onEdit={onEdit} />
</div>
