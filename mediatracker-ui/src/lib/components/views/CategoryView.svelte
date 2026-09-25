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
    onOpenTvShow: (id: string) => void
    onMediaChanged: () => void
    onEdit?: (item: MediaItem) => void
  }

  let { category, refreshKey, onOpenTvShow, onMediaChanged, onEdit = () => {} }: Props = $props()

  let status = $state<StatusFilter>('all')
  let sort = $state<LibrarySort>('newest')
  let search = $state('')
  let items = $state<MediaItem[]>([])
  let loading = $state(true)
  let loadError = $state<unknown>(null)
  let requestSequence = 0

  $effect(() => {
    void refreshKey
    const sequence = ++requestSequence
    const delay = search.trim() ? 250 : 0
    const timer = setTimeout(() => void loadItems(sequence), delay)

    return () => clearTimeout(timer)
  })

  function categoryFilters(): MediaFilters {
    const filters: MediaFilters = {
      search: search.trim() || undefined,
      status: status === 'all' ? undefined : status,
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
    loading = true
    loadError = null

    try {
      const found = await getMedia(categoryFilters())
      if (sequence === requestSequence) {
        items = found
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

  function openItem(item: MediaItem) {
    if (item.type === 'tvshow') {
      onOpenTvShow(item.id)
    }
  }

  async function removeItem(item: MediaItem) {
    await deleteMedia(item.id)
    onMediaChanged()
  }

  function updateStatus(value: StatusFilter) {
    status = value
  }
</script>

<div class="space-y-6">
  <FilterBar {status} {sort} {search} onStatusChange={updateStatus} onSortChange={(value) => (sort = value)} onSearchChange={(value) => (search = value)} />
  <p class="text-xs font-medium text-muted">{i18n.t.library.resultCount(items.length)}</p>
  <MediaGrid {items} loading={loading} error={loadError} onRetry={refresh} onOpen={openItem} onProgress={updateProgress} onProgressCommitted={onMediaChanged} onDelete={removeItem} onEdit={onEdit} />
</div>
