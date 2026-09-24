<script lang="ts">
  import { deleteMedia, getMedia, setProgress } from '$lib/api'
  import { i18n } from '$lib/i18n/index.svelte'
  import { MEDIA_STATUS, type MediaItem } from '$lib/types'
  import MediaGrid from '../media/MediaGrid.svelte'

  interface Props {
    refreshKey: number
    onOpenTvShow: (id: string) => void
    onMediaChanged: () => void
  }

  let { refreshKey, onOpenTvShow, onMediaChanged }: Props = $props()

  let inProgress = $state<MediaItem[]>([])
  let upNext = $state<MediaItem[]>([])
  let recentlyCompleted = $state<MediaItem[]>([])
  let loading = $state(true)
  let loadError = $state<unknown>(null)
  let requestSequence = 0

  $effect(() => {
    void refreshKey
    void loadSections(++requestSequence)
  })

  async function loadSections(sequence: number) {
    loading = true
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
    void loadSections(++requestSequence)
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
</script>

<div class="space-y-10">
  <section class="space-y-4">
    <div class="flex items-end justify-between gap-4">
      <div>
        <p class="text-xs font-semibold uppercase tracking-[0.18em] text-accent-soft">{i18n.t.library.collectionLabel}</p>
        <h2 class="mt-1 text-xl font-bold tracking-tight text-ink">{i18n.t.views.inProgress}</h2>
      </div>
    </div>
    <MediaGrid items={inProgress} {loading} error={loadError} onRetry={refresh} onOpen={openItem} onProgress={updateProgress} onProgressCommitted={onMediaChanged} onDelete={removeItem} />
  </section>

  <section class="space-y-4">
    <h2 class="text-xl font-bold tracking-tight text-ink">{i18n.t.views.upNext}</h2>
    <MediaGrid items={upNext} {loading} error={loadError} onRetry={refresh} onOpen={openItem} onProgress={updateProgress} onProgressCommitted={onMediaChanged} onDelete={removeItem} />
  </section>

  <section class="space-y-4">
    <h2 class="text-xl font-bold tracking-tight text-ink">{i18n.t.views.recentlyCompleted}</h2>
    <MediaGrid items={recentlyCompleted} {loading} error={loadError} onRetry={refresh} onOpen={openItem} onProgress={updateProgress} onProgressCommitted={onMediaChanged} onDelete={removeItem} />
  </section>
</div>
