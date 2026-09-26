<script lang="ts">
  import { ArrowLeft, CalendarDays, Check, ChevronDown, Eye, Image as ImageIcon, List, Minus, Pencil, Plus, RefreshCw, Star, Trash2 } from 'lucide-svelte'
  import { errorMessage, getMedia, getMediaItem, setProgress, setSeasonProgress, updateMedia, updateStatus } from '$lib/api'
  import { i18n } from '$lib/i18n/index.svelte'
  import { clampProgress, isTvShowDetail, MEDIA_STATUS, type AppView, type MediaDetail, type MediaItem, type MediaStatus, type TvSeason } from '$lib/types'
  import { createProgressDebounce } from '$lib/utils/progressDebounce'

  interface Props {
    mediaId: string
    refreshKey: number
    onBack: () => void
    onUpdate: () => void
    onDelete: (id: string) => Promise<void>
    onEdit: (item: MediaItem) => void
    onOpenRelated: (item: MediaItem) => void
    onNavigate?: (view: AppView) => void
  }

  interface ProgressInfo {
    current: number
    total: number | null
    editable: boolean
    label: string
  }

  interface EpisodeRow {
    id: string
    number: number
    title: string
    airDate: string | null
    description: string | null
    watched: boolean
  }

  let { mediaId, refreshKey, onBack, onUpdate, onDelete, onEdit, onOpenRelated, onNavigate = () => {} }: Props = $props()

  const statusOptions: readonly MediaStatus[] = [
    MEDIA_STATUS.planned,
    MEDIA_STATUS.inProgress,
    MEDIA_STATUS.completed,
    MEDIA_STATUS.onHold,
    MEDIA_STATUS.dropped,
  ]
  const maxEpisodesPerSeason = 200

  let media = $state<MediaDetail | null>(null)
  let isLoading = $state(true)
  let loadError = $state<unknown>(null)
  let requestSequence = 0
  let trackedMediaId: string | null = null

  let synopsisExpanded = $state(false)
  let statusMenuOpen = $state(false)

  let related = $state<MediaItem[]>([])
  let relatedLoading = $state(false)
  let relatedError = $state<unknown>(null)
  let relatedSequence = 0

  let statusValue = $state<MediaStatus>(MEDIA_STATUS.planned)
  let statusBusy = $state(false)
  let statusError = $state<unknown>(null)

  let scoreValue = $state<number | null>(null)
  let ratingBusy = $state(false)
  let ratingError = $state<unknown>(null)

  let progressValue = $state(0)
  let committedProgress = $state(0)
  let pendingSnapshot = $state<number | null>(null)
  let progressError = $state<unknown>(null)

  let selectedSeasonId = $state<string | null>(null)
  let episodeBusy = $state('')

  const progressDebounce = createProgressDebounce({
    send: (id, value) => setProgress(id, value),
    buildRequest: (id, value) => ({ url: `/api/media/${id}/progress`, body: { currentProgress: value } }),
    onCommitted: (value) => {
      committedProgress = value
      if (progressValue === value) onUpdate()
    },
    onError: (error) => {
      progressValue = pendingSnapshot ?? committedProgress
      committedProgress = progressValue
      pendingSnapshot = null
      progressError = error
    },
  })

  let progressInfo = $derived(media ? readProgress(media) : null)
  let seasons = $derived(media && isTvShowDetail(media) ? media.seasons ?? [] : [])
  let seasonViews = $derived(seasons.map((season) => ({ season, episodes: buildEpisodes(season) })))
  let season = $derived(seasonViews.find((view) => view.season.id === selectedSeasonId) ?? seasonViews[0] ?? null)
  let episodes = $derived(season?.episodes ?? [])
  let currentSeason = $derived(season?.season ?? null)
  let originalTitle = $derived(media ? readOriginalTitle(media) : null)
  let synopsisText = $derived(media?.notes?.trim() ?? '')
  let synopsisExpandable = $derived(synopsisText.length > 280)
  let progressPercent = $derived.by(() => {
    const info = progressInfo
    if (!info || info.total === null || info.total <= 0) return 0
    return Math.min(progressValue / info.total, 1) * 100
  })

  $effect(() => {
    void refreshKey
    const id = mediaId
    const isNew = trackedMediaId !== id
    trackedMediaId = id
    void load(id, ++requestSequence, isNew)
  })

  $effect(() => {
    return () => void progressDebounce.flush(true)
  })

  async function load(id: string, sequence: number, isNew: boolean) {
    if (isNew) {
      media = null
      isLoading = true
      loadError = null
      selectedSeasonId = null
      statusMenuOpen = false
      synopsisExpanded = false
      related = []
      relatedError = null
      progressError = null
      statusError = null
      ratingError = null
    }

    try {
      const loaded = await getMediaItem(id)
      if (sequence !== requestSequence) return
      media = loaded
      syncFrom(loaded)
      void loadRelated(loaded)
    } catch (error) {
      if (sequence === requestSequence) {
        loadError = error
        if (isNew) media = null
      }
    } finally {
      if (sequence === requestSequence) isLoading = false
    }
  }

  function syncFrom(item: MediaDetail) {
    statusValue = item.status
    scoreValue = item.score
    const info = readProgress(item)
    progressValue = info?.current ?? 0
    committedProgress = progressValue
    pendingSnapshot = null
  }

  async function loadRelated(item: MediaItem) {
    const sequence = ++relatedSequence
    const franchiseId = item.franchiseId

    if (!franchiseId) {
      related = []
      relatedError = null
      relatedLoading = false
      return
    }

    relatedLoading = true
    relatedError = null

    try {
      const all = await getMedia()
      if (sequence !== relatedSequence) return
      related = all
        .filter((candidate) => candidate.franchiseId === franchiseId && candidate.id !== item.id)
        .toSorted((left, right) => orderOf(left) - orderOf(right) || left.title.localeCompare(right.title))
    } catch (error) {
      if (sequence === relatedSequence) {
        related = []
        relatedError = error
      }
    } finally {
      if (sequence === relatedSequence) relatedLoading = false
    }
  }

  function orderOf(item: MediaItem): number {
    return item.franchiseOrder ?? Number.MAX_SAFE_INTEGER
  }

  function buildEpisodes(value: TvSeason): EpisodeRow[] {
    const total = Math.max(value.totalEpisodes ?? 0, 0)
    const watched = Math.max(value.currentEpisode ?? 0, 0)
    const limit = Math.min(total, Math.max(watched, maxEpisodesPerSeason))

    return Array.from({ length: limit }, (_, index) => {
      const number = index + 1
      return {
        id: `${value.id}:${number}`,
        number,
        title: i18n.t.detail.episodeTitle(number),
        airDate: value.airDate ?? null,
        description: value.notes ?? null,
        watched: number <= watched,
      }
    })
  }

  function readProgress(item: MediaItem): ProgressInfo | null {
    switch (item.type) {
      case 'game':
        return { current: item.hoursPlayed ?? 0, total: null, editable: true, label: i18n.t.detail.hoursLabel }
      case 'book':
        return { current: item.currentPage, total: item.totalPages, editable: true, label: i18n.t.detail.pagesLabel }
      case 'manga':
        return { current: item.currentChapter, total: item.totalChapters, editable: true, label: i18n.t.detail.chaptersLabel }
      case 'tvshow':
        return { current: item.totalEpisodesWatched, total: item.totalEpisodesCount, editable: false, label: i18n.t.detail.episodesLabel }
      default:
        return null
    }
  }

  function readOriginalTitle(item: MediaItem): string | null {
    if (item.type === 'tvshow' || item.type === 'movie') {
      const value = item.romajiTitle?.trim()
      return value ? value : null
    }

    return null
  }

  function isAnime(item: MediaItem): boolean {
    return (item.type === 'tvshow' || item.type === 'movie') && item.isAnime
  }

  function typeLabel(item: MediaItem): string {
    return isAnime(item) ? i18n.t.navigation.anime : i18n.t.types[item.type]
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

  function dataSource(item: MediaItem): string {
    if (isAnime(item) || item.type === 'manga') return 'AniList'

    switch (item.type) {
      case 'game':
        return 'RAWG'
      case 'book':
        return 'OpenLibrary'
      default:
        return 'TMDB'
    }
  }

  function providerValue(item: MediaItem): string {
    const empty = i18n.t.detailModal.valueEmpty

    switch (item.type) {
      case 'tvshow':
        return item.network || empty
      case 'game':
        return item.platform || empty
      default:
        return empty
    }
  }

  function tags(item: MediaItem): string[] {
    const list: string[] = [typeLabel(item)]

    switch (item.type) {
      case 'game':
        if (item.platform) list.push(item.platform)
        break
      case 'book':
        if (item.author) list.push(item.author)
        break
      case 'manga':
        list.push(i18n.t.card.volume(item.currentVolume))
        break
      case 'movie':
        if (item.studio) list.push(item.studio)
        if (item.director) list.push(item.director)
        break
      case 'tvshow':
        if (item.studio) list.push(item.studio)
        if (item.network) list.push(item.network)
        break
    }

    return list
  }

  function specRows(item: MediaItem): Array<{ label: string; value: string }> {
    const empty = i18n.t.detailModal.valueEmpty
    const rows: Array<{ label: string; value: string }> = [
      { label: i18n.t.detail.formatLabel, value: typeLabel(item) },
      { label: i18n.t.detail.startDateLabel, value: formatDate(item.startedAt) },
      { label: i18n.t.detail.endDateLabel, value: formatDate(item.finishedAt) },
      { label: i18n.t.status.label, value: statusLabel(item.status) },
    ]

    switch (item.type) {
      case 'tvshow':
        rows.push({ label: i18n.t.detail.episodesLabel, value: i18n.t.card.episodes(item.totalEpisodesWatched, item.totalEpisodesCount) })
        break
      case 'book':
        rows.push({ label: i18n.t.detail.pagesLabel, value: i18n.t.card.pages(item.currentPage, item.totalPages) })
        break
      case 'manga':
        rows.push({ label: i18n.t.detail.chaptersLabel, value: i18n.t.card.chapters(item.currentChapter, item.totalChapters) })
        break
      case 'game':
        rows.push({ label: i18n.t.detail.hoursLabel, value: i18n.t.card.hours(item.hoursPlayed ?? 0) })
        break
    }

    rows.push({ label: i18n.t.detail.durationLabel, value: item.type === 'movie' && item.durationMinutes > 0 ? i18n.t.card.movie(item.durationMinutes) : empty })

    switch (item.type) {
      case 'tvshow':
      case 'movie':
        rows.push({ label: i18n.t.detailModal.studio, value: item.studio || empty })
        break
      case 'book':
      case 'manga':
        rows.push({ label: i18n.t.detailModal.author, value: item.type === 'book' ? item.author || empty : empty })
        break
      case 'game':
        rows.push({ label: i18n.t.detailModal.platform, value: item.platform || empty })
        break
    }

    rows.push({ label: i18n.t.detail.source, value: dataSource(item) })
    rows.push({ label: i18n.t.detail.providerLabel, value: providerValue(item) })

    return rows
  }

  function historyProgressText(): string {
    const info = progressInfo
    if (!info) return i18n.t.detailModal.valueEmpty
    return info.total !== null ? `${format(progressValue)} / ${format(info.total)}` : format(progressValue)
  }

  function formatDate(value: string | null): string {
    if (!value) return i18n.t.detailModal.dateEmpty
    const parsed = new Date(value)
    return Number.isNaN(parsed.getTime())
      ? i18n.t.detailModal.dateEmpty
      : new Intl.DateTimeFormat(i18n.current, { dateStyle: 'medium' }).format(parsed)
  }

  function format(value: number): string {
    return new Intl.NumberFormat(i18n.current).format(value)
  }

  function hasNumber(value: number | null | undefined): boolean {
    return typeof value === 'number'
  }

  function externalRatingText(score: number | null | undefined): string {
    return typeof score === 'number' ? score.toFixed(1) : ''
  }

  function externalRatingVotesText(count: number | null | undefined): string {
    return typeof count === 'number' ? i18n.t.detail.votes(count) : ''
  }

  function scoreText(score: number | null): string {
    return score === null ? i18n.t.detailModal.scoreEmpty : i18n.t.detail.ratingValue(score)
  }

  function clearScore() {
    void setScore(scoreValue ?? 0)
  }

  function stepProgress(delta: number) {
    const info = progressInfo
    const target = media
    if (!info || !info.editable || !target) return

    const next = clampProgress(progressValue + delta, info.total)
    if (next === progressValue) return

    if (pendingSnapshot === null) pendingSnapshot = committedProgress
    progressValue = next
    progressError = null
    progressDebounce.schedule(target.id, next)
  }

  async function changeStatus(value: MediaStatus) {
    const target = media
    statusMenuOpen = false
    if (!target || statusBusy) return
    if (value === statusValue) return

    const previous = statusValue
    statusValue = value
    statusBusy = true
    statusError = null

    try {
      await updateStatus(target.id, value)
      onUpdate()
    } catch (error) {
      statusValue = previous
      statusError = error
    } finally {
      statusBusy = false
    }
  }

  async function setScore(score: number) {
    const target = media
    if (!target || ratingBusy) return

    const next = scoreValue === score ? null : score
    const previous = scoreValue
    scoreValue = next
    ratingBusy = true
    ratingError = null

    try {
      await updateMedia(target.id, { score: next })
      onUpdate()
    } catch (error) {
      scoreValue = previous
      ratingError = error
    } finally {
      ratingBusy = false
    }
  }

  function retry() {
    void load(mediaId, ++requestSequence, true)
  }

  function startEdit() {
    const target = media
    if (target) onEdit(target)
  }

  async function removeMedia() {
    const target = media
    if (!target || deleteBusy) return
    if (!window.confirm(i18n.t.card.confirmDelete(target.title))) return

    deleteBusy = true
    deleteError = null

    try {
      await onDelete(target.id)
      onBack()
    } catch (error) {
      deleteError = error
    } finally {
      deleteBusy = false
    }
  }

  async function markEpisode(number: number) {
    const target = currentSeason
    if (!target || episodeBusy) return

    episodeBusy = target.id
    progressError = null

    try {
      await setSeasonProgress(target.id, number)
      onUpdate()
    } catch (error) {
      progressError = error
    } finally {
      episodeBusy = ''
    }
  }

  function handleWindowPointerDown(event: PointerEvent) {
    if (!statusMenuOpen) return
    const target = event.target
    if (target instanceof Element && target.closest('[data-status-menu]')) return
    statusMenuOpen = false
  }
</script>

<svelte:window onpointerdown={handleWindowPointerDown} />

<div class="space-y-5">
  <button type="button" class="inline-flex items-center gap-2 text-sm font-medium text-muted transition hover:text-white" onclick={onBack}><ArrowLeft size={16} aria-hidden="true" />{i18n.t.common.back}</button>

  {#if !media && isLoading}
    <div class="grid gap-6 lg:grid-cols-[20rem_minmax(0,1fr)]" aria-hidden="true">
      <div class="aspect-[2/3] w-full animate-pulse rounded-lg bg-card"></div>
      <div class="space-y-4">
        <div class="h-9 w-3/4 animate-pulse rounded bg-card"></div>
        <div class="h-4 w-1/2 animate-pulse rounded bg-card"></div>
        <div class="h-40 animate-pulse rounded-lg bg-card"></div>
      </div>
    </div>
    <p class="sr-only" role="status">{i18n.t.common.loading}</p>
  {:else if !media}
    <div class="flex min-h-72 flex-col items-center justify-center gap-3 rounded-lg bg-rose-400/5 p-6 text-center">
      <p class="text-sm text-rose-200" role="alert">{loadError ? errorMessage(loadError) : i18n.t.detail.notFound}</p>
      {#if loadError}
        <button type="button" class="inline-flex items-center gap-2 rounded-md bg-accent px-4 py-2 text-sm font-medium text-white transition hover:bg-accent-hover" onclick={retry}><RefreshCw size={15} aria-hidden="true" />{i18n.t.common.retry}</button>
      {/if}
    </div>
  {:else}
    {@const support = progressInfo}
    <div class="flex flex-col gap-6 lg:flex-row lg:gap-0">
      <aside class="w-full space-y-5 lg:w-80 lg:shrink-0 lg:pr-6">
        <div class="aspect-[2/3] w-full overflow-hidden rounded-lg bg-[#222634]">
          {#if media.coverUrl}
            <img src={media.coverUrl} alt={media.title} class="h-full w-full object-cover" />
          {:else}
            <div class="grid h-full place-items-center text-muted"><ImageIcon size={40} stroke-width={1.25} aria-hidden="true" /></div>
          {/if}
        </div>

        <div class="relative" data-status-menu>
          <button type="button" class="flex w-full items-center justify-between gap-2 rounded-md bg-[#5844e0] px-4 py-2.5 text-sm font-medium text-white transition hover:bg-[#4a37d4] disabled:cursor-wait disabled:opacity-70" disabled={statusBusy} aria-haspopup="listbox" aria-expanded={statusMenuOpen} onclick={() => (statusMenuOpen = !statusMenuOpen)}>
            <span>{statusLabel(statusValue)}</span>
            <ChevronDown size={16} class={`transition ${statusMenuOpen ? 'rotate-180' : ''}`} aria-hidden="true" />
          </button>
          {#if statusMenuOpen}
            <ul class="absolute inset-x-0 top-full z-20 mt-1 overflow-hidden rounded-md border border-white/5 bg-[#222634] py-1 shadow-xl shadow-black/40" role="listbox">
              {#each statusOptions as option (option)}
                <li>
                  <button type="button" class={`flex w-full items-center justify-between gap-2 px-3 py-2 text-left text-sm transition hover:bg-[#282d3d] ${option === statusValue ? 'text-[#a5b4fc]' : 'text-[#f3f4f6]'}`} onclick={() => void changeStatus(option)}>
                    {statusLabel(option)}
                    {#if option === statusValue}<Check size={14} aria-hidden="true" />{/if}
                  </button>
                </li>
              {/each}
            </ul>
          {/if}
          {#if statusError}<p class="mt-1.5 text-xs text-rose-300" role="alert">{errorMessage(statusError)}</p>{/if}
        </div>

        <section class="space-y-2 rounded-lg bg-[#222634] p-4">
          <h2 class="text-[11px] font-semibold uppercase tracking-wide text-[#6b7280]">{i18n.t.detail.historyTitle}</h2>
          <dl class="space-y-1.5 text-sm">
            <div class="flex items-center justify-between gap-3"><dt class="text-muted">{i18n.t.detail.startedLabel}</dt><dd class="font-medium text-white">{formatDate(media.startedAt)}</dd></div>
            <div class="flex items-center justify-between gap-3"><dt class="text-muted">{i18n.t.detail.endedLabel}</dt><dd class="font-medium text-white">{formatDate(media.finishedAt)}</dd></div>
            <div class="flex items-center justify-between gap-3"><dt class="text-muted">{i18n.t.detail.progressShort}</dt><dd class="font-medium tabular-nums text-white">{historyProgressText()}</dd></div>
          </dl>
        </section>

        <section class="space-y-1.5">
          <h2 class="text-[11px] font-semibold uppercase tracking-wide text-[#6b7280]">{i18n.t.detail.actionsTitle}</h2>
          <button type="button" class="flex w-full items-center gap-2.5 rounded-md bg-[#222634] px-3 py-2.5 text-sm font-medium text-[#d1d5db] transition hover:bg-[#282d3d]" onclick={() => onNavigate('lists')}><List size={16} class="text-[#a5b4fc]" aria-hidden="true" />{i18n.t.detail.addToLists}</button>
          <button type="button" class="flex w-full items-center gap-2.5 rounded-md bg-[#222634] px-3 py-2.5 text-sm font-medium text-[#d1d5db] transition hover:bg-[#282d3d]" onclick={() => onNavigate('calendar')}><CalendarDays size={16} class="text-[#f59e0b]" aria-hidden="true" />{i18n.t.detail.activity}</button>
          <button type="button" class="flex w-full items-center gap-2.5 rounded-md bg-[#222634] px-3 py-2.5 text-sm font-medium text-[#d1d5db] transition hover:bg-[#282d3d]" onclick={startEdit}><Pencil size={16} class="text-[#7dd3fc]" aria-hidden="true" />{i18n.t.detailModal.edit}</button>
          <button type="button" class="flex w-full items-center gap-2.5 rounded-md bg-[#222634] px-3 py-2.5 text-sm font-medium text-rose-300 transition hover:bg-[#282d3d] disabled:cursor-wait disabled:opacity-70" disabled={deleteBusy} onclick={() => void removeMedia()}><Trash2 size={16} class="text-rose-400" aria-hidden="true" />{i18n.t.detailModal.delete}</button>
          {#if deleteError}<p class="text-xs text-rose-300" role="alert">{errorMessage(deleteError)}</p>{/if}
        </section>

        <section class="space-y-2.5 rounded-lg bg-[#222634] p-4">
          <h2 class="text-[11px] font-semibold uppercase tracking-wide text-[#6b7280]">{i18n.t.detail.detailsTitle}</h2>
          <dl class="space-y-2">
            {#each specRows(media) as row (row.label)}
              <div class="flex items-start justify-between gap-3">
                <dt class="shrink-0 text-[11px] font-medium uppercase tracking-wide text-[#6b7280]">{row.label}</dt>
                <dd class="text-right text-sm text-white">{row.value}</dd>
              </div>
            {/each}
          </dl>
        </section>
      </aside>

      <div class="min-w-0 flex-1 space-y-5">
        <header class="flex flex-wrap items-start justify-between gap-4">
          <div class="min-w-0">
            <p class="text-sm text-muted">{originalTitle ?? typeLabel(media)}</p>
            <h1 class="mt-1 break-words text-3xl font-bold text-white">{media.title}</h1>
          </div>
          {#if seasons.length > 1}
            <label class="relative">
              <span class="sr-only">{i18n.t.navigation.seasons}</span>
              <select class="h-10 rounded-md border border-white/5 bg-[#222634] px-3 text-sm font-medium text-[#f3f4f6] outline-none transition focus:ring-2 focus:ring-[#5844e0]" value={currentSeason?.id ?? ''} onchange={(event) => (selectedSeasonId = (event.currentTarget as HTMLSelectElement).value)}>
                {#each seasons as value (value.id)}
                  <option value={value.id}>{i18n.t.createModal.fields.season} {value.seasonNumber} — {value.title}</option>
                {/each}
              </select>
            </label>
          {/if}
        </header>

        <ul class="flex flex-wrap gap-2">
          {#each tags(media) as tag (tag)}
            <li class="rounded-full bg-[#5844e0]/20 px-2.5 py-1 text-xs text-[#a5b4fc]">{tag}</li>
          {/each}
        </ul>

        <section class="space-y-2">
          {#if synopsisText}
            <p class={`whitespace-pre-line break-words text-sm leading-relaxed text-[#d1d5db] ${synopsisExpandable && !synopsisExpanded ? 'line-clamp-4' : ''}`}>{synopsisText}</p>
            {#if synopsisExpandable}
              <button type="button" class="inline-flex items-center gap-1 text-xs font-semibold text-[#a5b4fc] transition hover:text-white" onclick={() => (synopsisExpanded = !synopsisExpanded)}>
                {synopsisExpanded ? i18n.t.detail.collapse : i18n.t.detail.readMore}
                <ChevronDown size={14} class={synopsisExpanded ? 'rotate-180 transition' : 'transition'} aria-hidden="true" />
              </button>
            {/if}
          {:else}
            <p class="text-sm text-muted">{i18n.t.detail.noSynopsis}</p>
          {/if}
        </section>

        <div class="grid gap-3 sm:grid-cols-2">
          <div class="rounded-lg bg-[#222634] p-3">
            <p class="text-[11px] font-medium uppercase tracking-wide text-[#6b7280]">{dataSource(media)} · {i18n.t.detail.externalRating}</p>
            {#if hasNumber(media.externalRating)}
              <div class="mt-1.5 flex items-center gap-1.5">
                <Star size={16} class="text-[#f59e0b]" fill="currentColor" aria-hidden="true" />
                <span class="text-lg font-bold text-white">{externalRatingText(media.externalRating)}<span class="text-sm font-medium text-muted"> / 10</span></span>
              </div>
              {#if hasNumber(media.externalRatingVotes)}
                <p class="mt-0.5 text-xs text-muted">{externalRatingVotesText(media.externalRatingVotes)}</p>
              {/if}
            {:else}
              <p class="mt-1.5 text-sm text-muted">{i18n.t.detail.externalRatingEmpty}</p>
            {/if}
          </div>
          <div class="rounded-lg bg-[#222634] p-3">
            <div class="flex items-center justify-between gap-2">
              <p class="text-[11px] font-medium uppercase tracking-wide text-[#6b7280]">{i18n.t.detail.yourRating}</p>
              {#if scoreValue !== null}
                <button type="button" class="text-xs font-medium text-muted transition hover:text-white disabled:cursor-wait disabled:opacity-60" disabled={ratingBusy} onclick={clearScore}>{i18n.t.detail.clearRating}</button>
              {/if}
            </div>
            <div class="mt-1 flex flex-wrap items-center gap-0.5">
              {#each Array(10) as _, index (index)}
                {@const value = index + 1}
                <button type="button" class="grid h-7 w-7 place-items-center rounded-md transition hover:bg-[#282d3d] disabled:cursor-wait disabled:opacity-60" aria-label={i18n.t.detail.starAria(value)} disabled={ratingBusy} onclick={() => void setScore(value)}>
                  <Star size={15} class={value <= (scoreValue ?? 0) ? 'text-[#f59e0b]' : 'text-[#6b7280]'} fill={value <= (scoreValue ?? 0) ? 'currentColor' : 'none'} aria-hidden="true" />
                </button>
              {/each}
            </div>
            <p class="mt-1 text-sm font-semibold text-white">{scoreText(scoreValue)}</p>
            {#if ratingError}<p class="text-xs text-rose-300" role="alert">{errorMessage(ratingError)}</p>{/if}
          </div>
        </div>

        {#if media.type === 'tvshow'}
          <section class="space-y-2">
            <div class="flex flex-wrap items-center justify-between gap-2">
              <h2 class="text-base font-semibold text-white">{i18n.t.detail.episodesLabel}</h2>
              {#if currentSeason}
                <span class="text-xs text-muted">{currentSeason.title} · {i18n.t.card.episodes(currentSeason.currentEpisode, currentSeason.totalEpisodes)}</span>
              {/if}
            </div>
            {#if seasons.length === 0}
              <p class="rounded-lg bg-[#222634] p-4 text-sm text-muted">{i18n.t.views.noSeasons}</p>
            {:else if episodes.length === 0}
              <p class="rounded-lg bg-[#222634] p-4 text-sm text-muted">{i18n.t.common.noData}</p>
            {:else}
              {#each episodes as episode (episode.id)}
                <article class="mb-2 flex items-center gap-3.5 rounded-lg bg-[#222634] p-3.5 transition hover:bg-[#282d3d]">
                  <span class="grid h-9 w-9 shrink-0 place-items-center rounded-md bg-[#13151b] text-xs font-bold text-[#9ca3af]">E{episode.number}</span>
                  <div class="min-w-0 flex-1">
                    <p class="truncate text-sm font-semibold text-white">{episode.title}</p>
                    <p class="mt-0.5 flex flex-wrap items-center gap-x-2 text-xs text-[#9ca3af]">
                      {#if episode.airDate}<span>{formatDate(episode.airDate)}</span>{/if}
                      {#if episode.watched}<span class="font-medium text-[#a5b4fc]">{i18n.t.status.completed}</span>{/if}
                    </p>
                    {#if episode.description}
                      <p class="mt-1 line-clamp-2 text-xs leading-5 text-[#9ca3af]">{episode.description}</p>
                    {/if}
                  </div>
                  <div class="flex shrink-0 items-center gap-1.5">
                    <button type="button" class={`grid h-8 w-8 place-items-center rounded-full transition disabled:cursor-wait disabled:opacity-60 ${episode.watched ? 'bg-[#5844e0]/20 text-[#a5b4fc]' : 'text-[#9ca3af] hover:bg-[#13151b] hover:text-white'}`} aria-label={i18n.t.detail.markWatched} title={i18n.t.detail.markWatched} disabled={Boolean(episodeBusy)} onclick={() => void markEpisode(episode.number)}>
                      <Eye size={15} aria-hidden="true" />
                    </button>
                    <button type="button" class="grid h-8 w-8 place-items-center rounded-full text-[#9ca3af] transition hover:bg-[#13151b] hover:text-white" aria-label={i18n.t.views.listsTitle} title={i18n.t.views.listsTitle} onclick={() => onNavigate('lists')}><List size={15} aria-hidden="true" /></button>
                    <button type="button" class="grid h-8 w-8 place-items-center rounded-full text-[#9ca3af] transition hover:bg-[#13151b] hover:text-white" aria-label={i18n.t.views.calendarTitle} title={i18n.t.views.calendarTitle} onclick={() => onNavigate('calendar')}><CalendarDays size={15} aria-hidden="true" /></button>
                  </div>
                </article>
              {/each}
              {#if progressError}<p class="text-xs text-rose-300" role="alert">{errorMessage(progressError)}</p>{/if}
            {/if}
          </section>
        {:else if support && support.editable}
          <section class="space-y-3 rounded-lg bg-[#222634] p-4">
            <div class="flex items-center justify-between gap-3">
              <h2 class="text-[11px] font-semibold uppercase tracking-wide text-[#6b7280]">{support.label}</h2>
              <span class="text-sm font-semibold tabular-nums text-white">{support.total !== null ? `${format(progressValue)} / ${format(support.total)}` : format(progressValue)}</span>
            </div>
            <div class="flex h-10 items-center rounded-md bg-[#13151b]">
              <button type="button" class="grid h-full w-10 place-items-center rounded-l-md text-[#9ca3af] transition hover:bg-[#282d3d] hover:text-white disabled:cursor-not-allowed disabled:opacity-40" aria-label={i18n.t.card.decrement} disabled={progressValue <= 0} onclick={() => stepProgress(-1)}><Minus size={15} aria-hidden="true" /></button>
              <span class="flex-1 text-center text-sm font-semibold tabular-nums text-white">{format(progressValue)}</span>
              <button type="button" class="grid h-full w-10 place-items-center rounded-r-md text-[#9ca3af] transition hover:bg-[#282d3d] hover:text-white" aria-label={i18n.t.card.increment} onclick={() => stepProgress(1)}><Plus size={15} aria-hidden="true" /></button>
            </div>
            {#if support.total !== null && support.total > 0}
              <div class="h-1.5 overflow-hidden rounded-full bg-[#13151b]"><div class="h-full rounded-full bg-[#5844e0] transition-[width] duration-200" style={`width: ${progressPercent}%`}></div></div>
            {/if}
            {#if progressError}<p class="text-xs text-rose-300" role="alert">{errorMessage(progressError)}</p>{/if}
          </section>
        {/if}

        {#if hasRelatedMedia}
          <section class="space-y-3">
            <h2 class="text-base font-semibold text-white">{i18n.t.detail.relatedTitle}</h2>
            <div class="grid grid-cols-2 gap-3 sm:grid-cols-3 md:grid-cols-4 lg:grid-cols-5">
              {#if media.relations && media.relations.length > 0}
                {#each media.relations as rel (rel.id)}
                  <button type="button" class="group flex flex-col items-start text-left" onclick={() => onSelectMedia(rel.id)}>
                    <div class="aspect-[2/3] w-full overflow-hidden rounded-md bg-[#222634] transition group-hover:ring-2 group-hover:ring-[#5844e0]">
                      {#if rel.coverUrl}
                        <img src={rel.coverUrl} alt={rel.title} class="h-full w-full object-cover transition duration-200 group-hover:scale-105" />
                      {:else}
                        <div class="grid h-full place-items-center text-muted"><ImageIcon size={24} stroke-width={1.25} aria-hidden="true" /></div>
                      {/if}
                    </div>
                    <span class="mt-1.5 line-clamp-1 text-xs font-medium text-white transition group-hover:text-[#a5b4fc]">{rel.title}</span>
                    <span class="text-[11px] text-muted">{rel.relationType || typeLabel(rel)}</span>
                  </button>
                {/each}
              {/if}
            </div>
          </section>
        {/if}
      </div>
    </div>
  {/if}
</div>
