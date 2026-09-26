<script lang="ts">
  import { Image as ImageIcon, Pencil, Trash2, X } from 'lucide-svelte'
  import { errorMessage, getMediaItem } from '$lib/api'
  import { i18n } from '$lib/i18n/index.svelte'
  import { isTvShowDetail, type MediaItem, type MediaStatus, type TvSeason } from '$lib/types'

  interface Props {
    item: MediaItem | null
    onClose: () => void
    onEdit: (item: MediaItem) => void
    onDelete: (item: MediaItem) => Promise<void>
    onOpenSeasons: (id: string) => void
  }

  let { item, onClose, onEdit, onDelete, onOpenSeasons }: Props = $props()

  let seasons = $state<TvSeason[]>([])
  let loading = $state(false)
  let loadError = $state<unknown>(null)
  let deleteError = $state<unknown>(null)
  let deleteBusy = $state(false)
  let requestSequence = 0

  $effect(() => {
    const current = item

    if (!current) {
      seasons = []
      loading = false
      loadError = null
      deleteError = null
      return
    }

    seasons = []
    loadError = null
    deleteError = null

    if (current.type !== 'tvshow') {
      loading = false
      return
    }

    const sequence = ++requestSequence
    loading = true

    void (async () => {
      try {
        const loaded = await getMediaItem(current.id)
        if (sequence === requestSequence && isTvShowDetail(loaded)) seasons = loaded.seasons
      } catch (error) {
        if (sequence === requestSequence) loadError = error
      } finally {
        if (sequence === requestSequence) loading = false
      }
    })()
  })

  function typeLabel(media: MediaItem): string {
    if (media.type === 'tvshow' && media.isAnime) return i18n.t.navigation.anime
    return i18n.t.types[media.type]
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

  function formatDate(value: string | null): string {
    if (!value) return i18n.t.detailModal.dateEmpty
    const parsed = new Date(value)
    return Number.isNaN(parsed.getTime()) ? i18n.t.detailModal.dateEmpty : new Intl.DateTimeFormat(i18n.current, { dateStyle: 'medium' }).format(parsed)
  }

  function extraRows(media: MediaItem): Array<{ label: string; value: string }> {
    switch (media.type) {
      case 'game':
        return [
          { label: i18n.t.detailModal.platform, value: media.platform || i18n.t.detailModal.valueEmpty },
          { label: i18n.t.detailModal.progress, value: i18n.t.card.hours(media.hoursPlayed ?? 0) },
        ]
      case 'book':
        return [
          { label: i18n.t.detailModal.author, value: media.author || i18n.t.detailModal.valueEmpty },
          { label: i18n.t.detailModal.progress, value: i18n.t.card.pages(media.currentPage, media.totalPages) },
        ]
      case 'manga':
        return [
          { label: i18n.t.createModal.fields.currentVolume, value: String(media.currentVolume) },
          { label: i18n.t.detailModal.progress, value: i18n.t.card.chapters(media.currentChapter, media.totalChapters) },
        ]
      case 'movie':
        return [
          { label: i18n.t.detailModal.director, value: media.director || i18n.t.detailModal.valueEmpty },
          { label: i18n.t.detailModal.studio, value: media.studio || i18n.t.detailModal.valueEmpty },
          { label: i18n.t.createModal.fields.durationMinutes, value: i18n.t.card.movie(media.durationMinutes) },
        ]
      case 'tvshow':
        return [
          { label: i18n.t.detailModal.studio, value: media.studio || i18n.t.detailModal.valueEmpty },
          { label: i18n.t.detailModal.network, value: media.network || i18n.t.detailModal.valueEmpty },
          { label: i18n.t.detailModal.progress, value: i18n.t.card.episodes(media.totalEpisodesWatched, media.totalEpisodesCount) },
        ]
    }
  }

  function closeOnBackdrop(event: MouseEvent) {
    if (event.target === event.currentTarget) onClose()
  }

  function handleKeydown(event: KeyboardEvent) {
    if (event.key !== 'Escape' || !item) return
    event.preventDefault()
    onClose()
  }

  async function remove() {
    if (!item || deleteBusy) return
    if (!window.confirm(i18n.t.card.confirmDelete(item.title))) return

    deleteBusy = true
    deleteError = null

    try {
      await onDelete(item)
      onClose()
    } catch (error) {
      deleteError = error
    } finally {
      deleteBusy = false
    }
  }
</script>

<svelte:window onkeydown={handleKeydown} />

{#if item}
  <div class="fixed inset-0 z-50 flex items-center justify-center bg-black/60 p-4 backdrop-blur-sm" role="presentation" onclick={closeOnBackdrop}>
    <div class="max-h-[90vh] w-full max-w-2xl overflow-y-auto rounded-2xl border border-border bg-surface shadow-2xl shadow-black/40" role="dialog" aria-modal="true" tabindex="-1" aria-label={item.title} onclick={(event) => event.stopPropagation()}>
      <header class="flex items-start justify-between gap-4 border-b border-border p-5">
        <div class="min-w-0">
          <p class="text-xs font-semibold uppercase tracking-[0.16em] text-accent-soft">{i18n.t.detailModal.eyebrow}</p>
          <h2 class="mt-1 break-words text-lg font-bold tracking-tight text-ink">{item.title}</h2>
        </div>
        <button type="button" class="grid h-8 w-8 shrink-0 place-items-center rounded-lg text-muted transition hover:bg-elevated hover:text-ink" aria-label={i18n.t.common.close} onclick={onClose}><X size={16} aria-hidden="true" /></button>
      </header>

      <div class="grid gap-5 p-5 sm:grid-cols-[10rem_1fr]">
        <div class="aspect-[3/4] overflow-hidden rounded-xl bg-elevated">
          {#if item.coverUrl}
            <img src={item.coverUrl} alt={item.title} class="h-full w-full object-cover" />
          {:else}
            <div class="grid h-full place-items-center bg-gradient-to-br from-panel to-elevated text-muted"><ImageIcon size={38} stroke-width={1.25} aria-hidden="true" /></div>
          {/if}
        </div>

        <div class="min-w-0 space-y-4">
          <dl class="grid grid-cols-2 gap-3 text-sm">
            <div>
              <dt class="text-xs text-muted">{i18n.t.detailModal.typeLabel}</dt>
              <dd class="font-medium text-ink">{typeLabel(item)}</dd>
            </div>
            <div>
              <dt class="text-xs text-muted">{i18n.t.status.label}</dt>
              <dd><span class={`inline-flex rounded-md px-2 py-0.5 text-xs font-semibold ${statusClass(item.status)}`}>{statusLabel(item.status)}</span></dd>
            </div>
            <div>
              <dt class="text-xs text-muted">{i18n.t.detailModal.scoreLabel}</dt>
              <dd class="font-medium text-amber-300">{item.score !== null ? `★ ${item.score}` : i18n.t.detailModal.scoreEmpty}</dd>
            </div>
            {#each extraRows(item) as row (row.label)}
              <div>
                <dt class="text-xs text-muted">{row.label}</dt>
                <dd class="font-medium text-ink">{row.value}</dd>
              </div>
            {/each}
            <div>
              <dt class="text-xs text-muted">{i18n.t.detailModal.startedAt}</dt>
              <dd class="font-medium text-ink">{formatDate(item.startedAt)}</dd>
            </div>
            <div>
              <dt class="text-xs text-muted">{i18n.t.detailModal.finishedAt}</dt>
              <dd class="font-medium text-ink">{formatDate(item.finishedAt)}</dd>
            </div>
          </dl>

          <div class="space-y-1">
            <p class="text-xs text-muted">{i18n.t.detailModal.notes}</p>
            <p class="whitespace-pre-line text-sm leading-6 text-ink">{item.notes?.trim() || i18n.t.detailModal.noNotes}</p>
          </div>
        </div>
      </div>
      {#if item.type === 'tvshow'}
        <section class="space-y-3 border-t border-border p-5">
          <div class="flex items-center justify-between gap-3">
            <h3 class="text-sm font-semibold text-ink">{i18n.t.detailModal.seasons}</h3>
            <span class="text-xs text-muted">{i18n.t.detailModal.seasonsCount(seasons.length)}</span>
          </div>

          {#if loading}
            <p class="text-xs text-muted" role="status">{i18n.t.common.loading}</p>
          {:else if loadError}
            <p class="text-xs text-rose-300" role="alert">{errorMessage(loadError)}</p>
          {:else if seasons.length === 0}
            <p class="text-xs text-muted">{i18n.t.views.noSeasons}</p>
          {:else}
            <ul class="space-y-2">
              {#each seasons as season (season.id)}
                <li class="flex items-center justify-between gap-3 rounded-lg border border-border bg-elevated/60 px-3 py-2">
                  <span class="truncate text-sm text-ink" title={season.title}>{season.title}</span>
                  <span class="shrink-0 text-xs tabular-nums text-muted">{i18n.t.detailModal.seasonEpisodes(season.currentEpisode, season.totalEpisodes)}</span>
                </li>
              {/each}
            </ul>
          {/if}
        </section>
      {/if}

      <footer class="flex flex-wrap justify-end gap-2 border-t border-border p-5">
        {#if item.type === 'tvshow'}
          <button type="button" class="inline-flex items-center gap-2 rounded-lg border border-border bg-elevated px-3 py-2 text-sm font-semibold text-ink transition hover:border-accent/50" onclick={() => onOpenSeasons(item.id)}>{i18n.t.detailModal.openSeasons}</button>
        {/if}
        <button type="button" class="inline-flex items-center gap-2 rounded-lg border border-border bg-elevated px-3 py-2 text-sm font-semibold text-ink transition hover:border-accent/50" onclick={() => onEdit(item)}><Pencil size={15} aria-hidden="true" />{i18n.t.detailModal.edit}</button>
        <button type="button" class="inline-flex items-center gap-2 rounded-lg border border-rose-400/30 bg-rose-400/10 px-3 py-2 text-sm font-semibold text-rose-200 transition hover:bg-rose-400/20 disabled:cursor-wait disabled:opacity-70" disabled={deleteBusy} onclick={() => void remove()}><Trash2 size={15} aria-hidden="true" />{i18n.t.detailModal.delete}</button>
      </footer>

      {#if deleteError}
        <p class="px-5 pb-5 text-xs text-rose-300" role="alert">{errorMessage(deleteError)}</p>
      {/if}
    </div>
  </div>
{/if}

