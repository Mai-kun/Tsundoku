<script lang="ts">
  import { Check, Image as ImageIcon, Minus, Plus, Trash2 } from 'lucide-svelte'
  import { untrack } from 'svelte'
  import { errorMessage } from '$lib/api'
  import { i18n } from '$lib/i18n/index.svelte'
  import { clampProgress, type MediaItem, type MediaStatus } from '$lib/types'

  interface Props {
    item: MediaItem
    onOpen?: (item: MediaItem) => void
    onProgress?: (id: string, currentProgress: number) => Promise<void>
    onProgressCommitted?: () => void
    onDelete?: (item: MediaItem) => Promise<void>
  }

  let {
    item,
    onOpen = () => {},
    onProgress,
    onProgressCommitted = () => {},
    onDelete,
  }: Props = $props()

  let trackedItem = $state(untrack(() => item))
  let currentProgress = $state(untrack(() => readProgress(item)))
  let committedProgress = $state(untrack(() => currentProgress))
  let pendingSnapshot = $state<number | null>(null)
  let hasScheduledSync = $state(false)
  let isSending = $state(false)
  let progressError = $state<unknown>(null)
  let deleteError = $state<unknown>(null)
  let progressTimer: ReturnType<typeof setTimeout> | null = null

  $effect(() => {
    if (item !== trackedItem && !hasScheduledSync && !isSending) {
      trackedItem = item
      currentProgress = readProgress(item)
      committedProgress = currentProgress
      pendingSnapshot = null
    }
  })

  $effect(() => {
    return () => {
      if (progressTimer) {
        clearTimeout(progressTimer)
      }
    }
  })

  function readProgress(media: MediaItem): number {
    switch (media.type) {
      case 'game':
        return media.hoursPlayed ?? 0
      case 'book':
        return media.currentPage
      case 'manga':
        return media.currentChapter
      default:
        return 0
    }
  }

  function totalForProgress(media: MediaItem): number | null {
    switch (media.type) {
      case 'book':
        return media.totalPages
      case 'manga':
        return media.totalChapters
      default:
        return null
    }
  }

  function statusLabel(status: MediaStatus): string {
    switch (status) {
      case 0:
        return i18n.t.status.planned
      case 1:
        return i18n.t.status.inProgress
      case 2:
        return i18n.t.status.completed
      case 3:
        return i18n.t.status.paused
      case 4:
        return i18n.t.status.dropped
    }
  }

  function statusClass(status: MediaStatus): string {
    switch (status) {
      case 1:
        return 'bg-accent/15 text-accent-soft'
      case 2:
        return 'bg-emerald-400/10 text-emerald-300'
      case 3:
        return 'bg-amber-400/10 text-amber-300'
      case 4:
        return 'bg-rose-400/10 text-rose-300'
      default:
        return 'bg-elevated text-muted'
    }
  }

  function format(value: number): string {
    return new Intl.NumberFormat(i18n.current).format(value)
  }

  function cardTypeLabel(media: MediaItem): string {
    if (media.type === 'tvshow' && media.isAnime) {
      return i18n.t.navigation.anime
    }

    return i18n.t.types[media.type]
  }

  function progressLabel(media: MediaItem): string | null {
    switch (media.type) {
      case 'game':
        return i18n.t.card.hours(currentProgress)
      case 'book':
        return i18n.t.card.pages(currentProgress, media.totalPages)
      case 'manga':
        return i18n.t.card.chapters(currentProgress, media.totalChapters)
      case 'movie':
        return i18n.t.card.movie(media.durationMinutes)
      case 'tvshow':
        return i18n.t.card.episodes(media.totalEpisodesWatched, media.totalEpisodesCount)
    }
  }

  function progressRatio(media: MediaItem): number | null {
    const total = media.type === 'tvshow' ? media.totalEpisodesCount : totalForProgress(media)
    const current = media.type === 'tvshow' ? media.totalEpisodesWatched : currentProgress

    return total !== null && total > 0 ? Math.min(current / total, 1) : null
  }

  function scheduleProgress(delta: number) {
    if (!onProgress || !supportsStepper(item)) return

    const next = clampProgress(currentProgress + delta, totalForProgress(item))
    if (next === currentProgress) return

    if (pendingSnapshot === null) {
      pendingSnapshot = committedProgress
    }

    currentProgress = next
    progressError = null
    scheduleSync()
  }

  function scheduleSync() {
    if (progressTimer) {
      clearTimeout(progressTimer)
    }

    hasScheduledSync = true
    progressTimer = setTimeout(() => {
      hasScheduledSync = false
      progressTimer = null
      void flushProgress()
    }, 375)
  }

  async function flushProgress() {
    if (!onProgress || isSending || currentProgress === committedProgress) return

    const target = currentProgress
    const snapshot = pendingSnapshot ?? committedProgress
    pendingSnapshot = null
    isSending = true

    try {
      await onProgress(item.id, target)
      committedProgress = target

      if (currentProgress === target) {
        onProgressCommitted()
      }
    } catch (error) {
      if (progressTimer) {
        clearTimeout(progressTimer)
        progressTimer = null
      }

      hasScheduledSync = false
      currentProgress = snapshot
      committedProgress = snapshot
      pendingSnapshot = null
      progressError = error
    } finally {
      isSending = false

      if (progressError === null && currentProgress !== committedProgress && !hasScheduledSync) {
        scheduleSync()
      }
    }
  }

  function supportsStepper(media: MediaItem): boolean {
    return media.type === 'game' || media.type === 'book' || media.type === 'manga'
  }

  async function removeItem() {
    if (!onDelete || !window.confirm(i18n.t.card.confirmDelete(item.title))) return

    deleteError = null

    try {
      await onDelete(item)
    } catch (error) {
      deleteError = error
    }
  }
</script>

<article class="group relative overflow-hidden rounded-2xl border border-border bg-surface shadow-sm transition hover:-translate-y-0.5 hover:border-accent/40 hover:shadow-xl hover:shadow-black/20" style="content-visibility: auto; contain-intrinsic-size: auto none;">
  <div class="aspect-[3/4] overflow-hidden bg-elevated">
    {#if item.coverUrl}
      <img src={item.coverUrl} alt={item.title} class="h-full w-full object-cover transition duration-500 group-hover:scale-[1.03]" loading="lazy" />
    {:else}
      <div class="flex h-full items-center justify-center bg-gradient-to-br from-panel to-elevated text-muted">
        <ImageIcon size={38} stroke-width={1.25} aria-hidden="true" />
      </div>
    {/if}

    <div class="absolute inset-x-0 top-0 flex items-start justify-between gap-2 p-3">
      <span class={`rounded-md px-2 py-1 text-[10px] font-bold uppercase tracking-wide backdrop-blur ${statusClass(item.status)}`}>{statusLabel(item.status)}</span>
      <button type="button" class="flex h-7 w-7 items-center justify-center rounded-md bg-canvas/70 text-muted opacity-0 transition hover:bg-rose-500/20 hover:text-rose-300 focus:opacity-100 group-hover:opacity-100" aria-label={i18n.t.card.deleteAria(item.title)} onclick={removeItem}>
        <Trash2 size={15} aria-hidden="true" />
      </button>
    </div>

    {#if item.type === 'tvshow'}
      <button type="button" class="absolute inset-0 z-0" aria-label={i18n.t.card.openDetails(item.title)} onclick={() => onOpen(item)}></button>
    {/if}
  </div>

  <div class="relative z-10 min-w-0 space-y-3 p-3.5">
    <div class="min-w-0">
      {#if item.type === 'tvshow'}
        <button type="button" class="block w-full truncate text-left text-sm font-semibold text-ink transition hover:text-accent-soft" title={item.title} onclick={() => onOpen(item)}>{item.title}</button>
      {:else}
        <h2 class="truncate text-sm font-semibold text-ink" title={item.title}>{item.title}</h2>
      {/if}
      <p class="mt-1 truncate text-xs text-muted">
        {cardTypeLabel(item)}
        {#if item.type === 'game' && item.platform}
          · {item.platform}
        {:else if item.type === 'book' && item.author}
          · {item.author}
        {:else if item.type === 'tvshow' && item.seasonsCount > 0}
          · {item.seasonsCount}
        {/if}
      </p>
    </div>

    {#if progressLabel(item)}
      <div class="space-y-1.5">
        <div class="flex items-center justify-between gap-2 text-xs text-muted">
          <span>{progressLabel(item)}</span>
          {#if item.score !== null}
            <span class="font-semibold text-amber-300">★ {format(item.score)}</span>
          {/if}
        </div>
        {#if progressRatio(item) !== null}
          <div class="h-1.5 overflow-hidden rounded-full bg-panel">
            <div class="h-full rounded-full bg-accent transition-[width] duration-200" style={`width: ${progressRatio(item)! * 100}%`}></div>
          </div>
        {/if}
      </div>
    {/if}

    {#if supportsStepper(item)}
      <div class="flex h-8 items-center rounded-lg border border-border bg-elevated">
        <button type="button" class="grid h-full w-8 place-items-center rounded-l-lg text-muted transition hover:bg-panel hover:text-ink" aria-label={i18n.t.card.decrement} onclick={() => scheduleProgress(-1)}><Minus size={14} aria-hidden="true" /></button>
        <span class="flex-1 text-center text-xs font-semibold tabular-nums text-ink">{format(currentProgress)}</span>
        <button type="button" class="grid h-full w-8 place-items-center rounded-r-lg text-muted transition hover:bg-panel hover:text-ink" aria-label={i18n.t.card.increment} onclick={() => scheduleProgress(1)}><Plus size={14} aria-hidden="true" /></button>
      </div>
    {/if}

    {#if item.status === 2}
      <div class="flex items-center gap-1.5 text-xs font-medium text-emerald-300"><Check size={14} aria-hidden="true" />{i18n.t.status.completed}</div>
    {/if}

    {#if progressError}
      <p class="text-xs leading-4 text-rose-300" role="alert">{errorMessage(progressError)}</p>
    {/if}
    {#if deleteError}
      <p class="text-xs leading-4 text-rose-300" role="alert">{errorMessage(deleteError)}</p>
    {/if}
  </div>
</article>
