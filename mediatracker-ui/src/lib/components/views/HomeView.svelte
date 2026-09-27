<script lang="ts">
  import { deleteMedia, getMedia, setProgress } from '$lib/api'
  import { i18n } from '$lib/i18n/index.svelte'
  import { MEDIA_STATUS, type MediaItem } from '$lib/types'
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
  let requestSequence = 0

  $effect(() => {
    void refreshKey
    const isInitial = inProgress.length === 0 && upNext.length === 0 && recentlyCompleted.length === 0
    void loadSections(++requestSequence, isInitial)
  })

  async function loadSections(sequence: number, showLoading = true) {
    if (showLoading) {
      loading = true
    }
    loadError = null

    try {
      const [active, planned, completed] = await Promise.all([
        getMedia({ status: MEDIA_STATUS.inProgress, sortBy: 'createdAt', sortOrder: 'desc' }),
        getMedia({ status: MEDIA_STATUS.planned, sortBy: 'createdAt', sortOrder: 'desc' }),
        getMedia({ status: MEDIA_STATUS.completed, sortBy: 'createdAt', sortOrder: 'desc' }),
      ])

      if (sequence === requestSequence) {
        inProgress = active
        upNext = planned
        recentlyCompleted = completed.toSorted((left, right) => {
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
    await setProgress(id, currentProgress)
  }

  async function removeItem(item: MediaItem) {
    const main = document.querySelector('main')
    const currentScroll = main ? main.scrollTop : (typeof window !== 'undefined' ? window.scrollY : 0)

    inProgress = inProgress.filter((i) => i.id !== item.id)
    upNext = upNext.filter((i) => i.id !== item.id)
    recentlyCompleted = recentlyCompleted.filter((i) => i.id !== item.id)

    await deleteMedia(item.id)
    onMediaChanged()

    setTimeout(() => {
      if (main && Math.abs(main.scrollTop - currentScroll) > 5) {
        main.scrollTop = currentScroll
      }
    }, 20)
  }
</script>

<div class="space-y-10">
  <section class="space-y-4">
    <div class="flex items-end justify-between gap-4">
      <div>
        <p class="text-xs font-semibold uppercase tracking-[0.18em] text-accent-soft">{i18n.t.library.collectionLabel}</p>
        <h2 class="mt-1 text-xl font-bold tracking-tight text-ink">{i18n.t.views.inProgress}</h2>
      </div>
    </div>
    <MediaGrid items={inProgress} {loading} error={loadError} onRetry={refresh} onOpen={onOpen} onProgress={updateProgress} onProgressCommitted={onMediaChanged} onDelete={removeItem} onEdit={onEdit} />
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
