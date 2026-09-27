<script lang="ts">
  import {
    ArrowLeft,
    ArrowUpDown,
    CalendarDays,
    Check,
    CheckCircle2,
    ChevronDown,
    ExternalLink,
    Eye,
    Image as ImageIcon,
    List,
    Minus,
    Pencil,
    Plus,
    RefreshCw,
    RotateCcw,
    Sparkles,
    Star,
    Trash2,
  } from 'lucide-svelte'
  import { errorMessage, getMedia, getMediaItem, refreshMetadata, setProgress, setSeasonProgress, updateMedia, updateStatus } from '$lib/api'
  import { i18n } from '$lib/i18n/index.svelte'
  import { showToast } from '$lib/stores/toast.svelte'
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

  interface RecommendationItem {
    id: string
    title: string
    coverUrl: string | null
    score: number | null
    type: string
  }

  interface RatingBadge {
    source: string
    score: number
    votes?: number | null
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

  let activeSubTab = $state<'overview' | 'episodes' | 'related' | 'recommendations'>('overview')
  let episodeSortOrder = $state<'asc' | 'desc'>('asc')
  let synopsisExpanded = $state(false)
  let statusMenuOpen = $state(false)
  let userRatingPopoverOpen = $state(false)

  let related = $state<MediaItem[]>([])
  let relatedLoading = $state(false)
  let relatedError = $state<unknown>(null)
  let relatedSequence = 0

  let recommendations = $state<RecommendationItem[]>([])
  let recommendationsLoading = $state(false)
  let recommendationsError = $state<unknown>(null)

  let deleteBusy = $state(false)
  let deleteError = $state<unknown>(null)

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
  let refreshBusy = $state(false)
  let refreshError = $state<unknown>(null)

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
  let sortedEpisodes = $derived.by(() => {
    const list = [...episodes]
    return episodeSortOrder === 'asc' ? list : list.reverse()
  })
  let currentSeason = $derived(season?.season ?? null)
  let originalTitle = $derived(media ? readOriginalTitle(media) : null)
  let synopsisText = $derived(media?.notes?.trim() ?? '')
  let synopsisExpandable = $derived(synopsisText.length > 280)
  let hasRelatedMedia = $derived(related.length > 0 || relatedLoading || relatedError !== null)

  let nextEpisode = $derived.by(() => {
    if (!currentSeason) return null
    const watched = currentSeason.currentEpisode ?? 0
    const total = currentSeason.totalEpisodes ?? 0
    if (watched >= total) return null
    return episodes.find((e) => e.number === watched + 1) ?? null
  })

  let progressPercent = $derived.by(() => {
    const info = progressInfo
    if (!info || info.total === null || info.total <= 0) return 0
    return Math.min(progressValue / info.total, 1) * 100
  })

  let seasonProgressPercent = $derived.by(() => {
    if (!currentSeason || !currentSeason.totalEpisodes || currentSeason.totalEpisodes <= 0) return 0
    return Math.min((currentSeason.currentEpisode ?? 0) / currentSeason.totalEpisodes, 1) * 100
  })

  let externalRatings = $derived.by<RatingBadge[]>(() => {
    if (!media) return []
    if (media.externalRatingsJson) {
      try {
        const parsed = JSON.parse(media.externalRatingsJson)
        if (Array.isArray(parsed) && parsed.length > 0) {
          return parsed.map((r: any) => ({
            source: r.source ?? r.Source ?? 'Source',
            score: typeof r.score === 'number' ? r.score : (typeof r.Score === 'number' ? r.Score : 0),
            votes: r.votes ?? r.Votes ?? null,
          }))
        }
      } catch {}
    }
    if (typeof media.externalRating === 'number') {
      return [
        {
          source: dataSource(media),
          score: media.externalRating,
          votes: media.externalRatingVotes,
        },
      ]
    }
    return []
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
      userRatingPopoverOpen = false
      synopsisExpanded = false
      activeSubTab = 'overview'
      related = []
      relatedError = null
      recommendations = []
      recommendationsError = null
      progressError = null
      statusError = null
      ratingError = null
      deleteError = null
      deleteBusy = false
    }

    try {
      const loaded = await getMediaItem(id)
      if (sequence !== requestSequence) return
      media = loaded
      syncFrom(loaded)
      void loadRelated(loaded)
    } catch (error) {
      console.error('[MediaDetailView] Failed to load media', id, error)
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

  async function loadRecommendations() {
    if (!media) return
    const cacheKey = `tsundoku_recs_${media.id}`
    const cachedStr = localStorage.getItem(cacheKey)
    if (cachedStr) {
      try {
        const cached = JSON.parse(cachedStr)
        // 30 days = 30 * 24 * 60 * 60 * 1000 = 2592000000 ms
        if (Date.now() - cached.timestamp < 2592000000 && Array.isArray(cached.items) && cached.items.length > 0) {
          recommendations = cached.items
          return
        }
      } catch {}
    }

    recommendationsLoading = true
    recommendationsError = null

    try {
      let items: RecommendationItem[] = []
      if (isAnime(media) || media.type === 'manga') {
        const query = `
          query ($search: String) {
            Media(search: $search) {
              recommendations(page: 1, perPage: 10, sort: RATING_DESC) {
                nodes {
                  mediaRecommendation {
                    id
                    title { romaji english userPreferred }
                    coverImage { large }
                    averageScore
                    type
                  }
                }
              }
            }
          }
        `
        const res = await fetch('https://graphql.anilist.co/', {
          method: 'POST',
          headers: { 'Content-Type': 'application/json' },
          body: JSON.stringify({ query, variables: { search: media.title } }),
        })
        if (res.ok) {
          const json = await res.json()
          const nodes = json?.data?.Media?.recommendations?.nodes ?? []
          items = nodes
            .filter((n: any) => n?.mediaRecommendation)
            .map((n: any) => ({
              id: String(n.mediaRecommendation.id),
              title:
                n.mediaRecommendation.title.english ||
                n.mediaRecommendation.title.romaji ||
                n.mediaRecommendation.title.userPreferred ||
                'Title',
              coverUrl: n.mediaRecommendation.coverImage?.large ?? null,
              score: typeof n.mediaRecommendation.averageScore === 'number' ? n.mediaRecommendation.averageScore / 10 : null,
              type: n.mediaRecommendation.type?.toLowerCase() === 'manga' ? 'manga' : 'anime',
            }))
        }
      }

      recommendations = items
      localStorage.setItem(cacheKey, JSON.stringify({ timestamp: Date.now(), items }))
    } catch (e) {
      recommendationsError = e
    } finally {
      recommendationsLoading = false
    }
  }

  function orderOf(item: MediaItem): number {
    return item.franchiseOrder ?? Number.MAX_SAFE_INTEGER
  }

  function buildEpisodes(value: TvSeason): EpisodeRow[] {
    let parsed: Array<{ number: number; title?: string; airDate?: string; description?: string }> = []
    if (value.episodesData) {
      try {
        parsed = JSON.parse(value.episodesData)
      } catch {}
    }
    const total = Math.max(value.totalEpisodes ?? 0, parsed.length, 0)
    const watched = Math.max(value.currentEpisode ?? 0, 0)
    const limit = Math.min(total, Math.max(watched, maxEpisodesPerSeason))

    return Array.from({ length: limit }, (_, index) => {
      const number = index + 1
      const found = parsed.find((p) => p.number === number)
      return {
        id: `${value.id}:${number}`,
        number,
        title: found?.title || i18n.t.detail.episodeTitle(number),
        airDate: found?.airDate ?? value.airDate ?? null,
        description: found?.description ?? value.notes ?? null,
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
    if (item.externalSource) return item.externalSource
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

  function providerDomain(item: MediaItem): string {
    const src = (item.externalSource || dataSource(item)).toLowerCase()
    if (src.includes('anilist')) return 'anilist.co'
    if (src.includes('mal') || src.includes('jikan') || src.includes('myanimelist')) return 'myanimelist.net'
    if (src.includes('mangaupdate')) return 'mangaupdates.com'
    if (src.includes('tmdb')) return 'themoviedb.org'
    if (src.includes('rawg')) return 'rawg.io'
    if (src.includes('openlibrary')) return 'openlibrary.org'
    return 'anilist.co'
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

    return [...new Set(list.filter(Boolean))]
  }

  function specRows(item: MediaItem): Array<{ label: string; value: string; isLink?: boolean }> {
    const empty = i18n.t.detailModal.valueEmpty
    const rows: Array<{ label: string; value: string; isLink?: boolean }> = [
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
    rows.push({ label: i18n.t.detail.providerLabel, value: providerDomain(item), isLink: true })

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
      showToast(i18n.t.status.label + ': ' + statusLabel(value), 'success')
      onUpdate()
    } catch (error) {
      statusValue = previous
      statusError = error
      showToast(errorMessage(error), 'error')
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
      showToast(next ? `${next} ★` : i18n.t.detail.clearRating, 'success')
      onUpdate()
    } catch (error) {
      scoreValue = previous
      ratingError = error
      showToast(errorMessage(error), 'error')
    } finally {
      ratingBusy = false
    }
  }

  function clearScore() {
    void setScore(scoreValue ?? 0)
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
      showToast(i18n.t.detailModal.delete, 'warning')
      onBack()
    } catch (error) {
      deleteError = error
      showToast(errorMessage(error), 'error')
    } finally {
      deleteBusy = false
    }
  }

  async function toggleEpisode(number: number) {
    const target = currentSeason
    if (!target || episodeBusy) return

    const current = target.currentEpisode ?? 0
    // If clicking an already watched episode: unwatch it to number - 1
    // If clicking an unwatched episode: mark watched up to number
    const nextVal = number <= current ? number - 1 : number

    episodeBusy = target.id
    progressError = null

    try {
      await setSeasonProgress(target.id, nextVal)
      target.currentEpisode = nextVal
      onUpdate()
    } catch (error) {
      progressError = error
      showToast(errorMessage(error), 'error')
    } finally {
      episodeBusy = ''
    }
  }

  async function markSeasonComplete() {
    const target = currentSeason
    if (!target || episodeBusy) return
    const total = target.totalEpisodes ?? 0
    if (total <= 0) return

    episodeBusy = target.id
    try {
      await setSeasonProgress(target.id, total)
      target.currentEpisode = total
      onUpdate()
      showToast(i18n.t.detail.markSeasonWatched, 'success')
    } catch (error) {
      progressError = error
      showToast(errorMessage(error), 'error')
    } finally {
      episodeBusy = ''
    }
  }

  async function resetSeasonProgress() {
    const target = currentSeason
    if (!target || episodeBusy) return

    episodeBusy = target.id
    try {
      await setSeasonProgress(target.id, 0)
      target.currentEpisode = 0
      onUpdate()
      showToast(i18n.t.detail.resetSeason, 'warning')
    } catch (error) {
      progressError = error
      showToast(errorMessage(error), 'error')
    } finally {
      episodeBusy = ''
    }
  }

  async function handleRefreshMetadata() {
    const target = media
    if (!target || refreshBusy) return
    refreshBusy = true
    refreshError = null
    try {
      const updated = await refreshMetadata(target.id)
      media = updated
      syncFrom(updated)
      showToast(i18n.t.detail.metadataUpdated, 'success')
      onUpdate()
    } catch (error) {
      refreshError = error
      showToast(errorMessage(error), 'error')
    } finally {
      refreshBusy = false
    }
  }

  function handleWindowPointerDown(event: PointerEvent) {
    const target = event.target
    if (statusMenuOpen && target instanceof Element && !target.closest('[data-status-menu]')) {
      statusMenuOpen = false
    }
    if (userRatingPopoverOpen && target instanceof Element && !target.closest('[data-rating-popover]')) {
      userRatingPopoverOpen = false
    }
  }
</script>

<svelte:window onpointerdown={handleWindowPointerDown} />

<div class="space-y-6">
  <button type="button" class="inline-flex items-center gap-2 text-sm font-medium text-muted transition hover:text-white" onclick={onBack}>
    <ArrowLeft size={16} aria-hidden="true" />
    {i18n.t.common.back}
  </button>

  {#if !media && isLoading}
    <div class="grid gap-6 lg:grid-cols-[20rem_minmax(0,1fr)]" aria-hidden="true">
      <div class="aspect-[2/3] w-full animate-pulse rounded-xl bg-card"></div>
      <div class="space-y-4">
        <div class="h-9 w-3/4 animate-pulse rounded bg-card"></div>
        <div class="h-4 w-1/2 animate-pulse rounded bg-card"></div>
        <div class="h-40 animate-pulse rounded-xl bg-card"></div>
      </div>
    </div>
    <p class="sr-only" role="status">{i18n.t.common.loading}</p>
  {:else if !media}
    <div class="flex min-h-72 flex-col items-center justify-center gap-3 rounded-xl bg-rose-400/5 p-6 text-center">
      <p class="text-sm text-rose-200" role="alert">{loadError ? errorMessage(loadError) : i18n.t.detail.notFound}</p>
      {#if loadError}
        <button type="button" class="inline-flex items-center gap-2 rounded-md bg-accent px-4 py-2 text-sm font-medium text-white transition hover:bg-accent-hover" onclick={retry}>
          <RefreshCw size={15} aria-hidden="true" />
          {i18n.t.common.retry}
        </button>
      {/if}
    </div>
  {:else}
    {@const support = progressInfo}
    <div class="flex flex-col gap-8 lg:flex-row">
      <!-- Left Column: Poster, Status + Rating, History, Actions, Details -->
      <aside class="w-full space-y-6 lg:w-80 lg:shrink-0">
        <div class="aspect-[2/3] w-full overflow-hidden rounded-xl bg-[#222634] shadow-lg">
          {#if media.coverUrl}
            <img src={media.coverUrl} alt={media.title} class="h-full w-full object-cover" />
          {:else}
            <div class="grid h-full place-items-center text-muted"><ImageIcon size={40} stroke-width={1.25} aria-hidden="true" /></div>
          {/if}
        </div>

        <!-- Status selector and User Rating in a unified row (Item 7) -->
        <div class="flex items-center gap-2">
          <div class="relative flex-1" data-status-menu>
            <button
              type="button"
              class="flex w-full items-center justify-between gap-2 rounded-lg border border-white/10 bg-[#222634] px-3.5 py-2.5 text-sm font-medium text-white transition hover:bg-[#282d3d] disabled:cursor-not-allowed disabled:opacity-70"
              disabled={statusBusy}
              aria-haspopup="listbox"
              aria-expanded={statusMenuOpen}
              onclick={() => (statusMenuOpen = !statusMenuOpen)}
            >
              <span class="truncate">{statusLabel(statusValue)}</span>
              <ChevronDown size={15} class={`shrink-0 transition ${statusMenuOpen ? 'rotate-180' : ''}`} aria-hidden="true" />
            </button>
            {#if statusMenuOpen}
              <ul class="absolute inset-x-0 top-full z-20 mt-1 overflow-hidden rounded-md border border-white/5 bg-[#222634] py-1 shadow-xl shadow-black/50" role="listbox">
                {#each statusOptions as option (option)}
                  <li>
                    <button
                      type="button"
                      class={`flex w-full items-center justify-between gap-2 px-3 py-2 text-left text-sm transition hover:bg-[#282d3d] ${option === statusValue ? 'text-[#a5b4fc]' : 'text-[#f3f4f6]'}`}
                      onclick={() => void changeStatus(option)}
                    >
                      {statusLabel(option)}
                      {#if option === statusValue}<Check size={14} aria-hidden="true" />{/if}
                    </button>
                  </li>
                {/each}
              </ul>
            {/if}
          </div>

          <!-- User Rating Button (Item 7) -->
          <div class="relative shrink-0" data-rating-popover>
            <button
              type="button"
              class={`flex h-10 items-center justify-center gap-1.5 rounded-lg border px-3.5 text-sm font-semibold transition hover:scale-105 active:scale-95 ${
                scoreValue !== null
                  ? 'border-amber-400/40 bg-amber-400/10 text-amber-300'
                  : 'border-white/10 bg-[#222634] text-white/80 hover:bg-[#282d3d] hover:text-white'
              }`}
              onclick={() => (userRatingPopoverOpen = !userRatingPopoverOpen)}
              title={i18n.t.detail.yourRating}
              aria-expanded={userRatingPopoverOpen}
            >
              {#if scoreValue !== null}
                <span class="font-bold tabular-nums">{scoreValue}</span>
                <Star size={14} class="text-amber-400" fill="currentColor" />
              {:else}
                <span class="text-xs">{i18n.t.detail.rateButton}</span>
                <Star size={13} class="text-muted" />
              {/if}
            </button>

            {#if userRatingPopoverOpen}
              <div class="absolute right-0 top-full z-30 mt-1.5 flex items-center gap-1 rounded-lg border border-white/10 bg-[#1e222d] p-1.5 shadow-2xl shadow-black/80">
                {#each Array(10) as _, index}
                  {@const val = index + 1}
                  <button
                    type="button"
                    class={`flex h-7 w-7 items-center justify-center rounded text-xs font-bold transition ${val === scoreValue ? 'bg-[#3b82f6] text-white shadow-md' : 'text-muted hover:bg-white/10 hover:text-white'}`}
                    onclick={() => { void setScore(val); userRatingPopoverOpen = false }}
                  >
                    {val}
                  </button>
                {/each}
                {#if scoreValue !== null}
                  <button
                    type="button"
                    class="ml-1 rounded px-1.5 py-1 text-[11px] font-semibold text-rose-400 hover:bg-rose-500/20"
                    title={i18n.t.detail.clearRating}
                    onclick={() => { clearScore(); userRatingPopoverOpen = false }}
                  >
                    ✕
                  </button>
                {/if}
              </div>
            {/if}
          </div>
        </div>
        {#if statusError}<p class="text-xs text-rose-300" role="alert">{errorMessage(statusError)}</p>{/if}

        <!-- Panel 1: Your History (Items 8, 9) -->
        <div>
          <h2 class="mb-2 text-xs font-bold uppercase tracking-wider text-slate-200">{i18n.t.detail.historyTitle}</h2>
          <div class="rounded-xl bg-[#222634] p-5 shadow-sm">
            <dl class="divide-y divide-white/5 text-sm">
              <div class="flex items-center justify-between gap-3 pb-3">
                <dt class="text-muted text-xs">{i18n.t.detail.startedLabel}</dt>
                <dd class="font-medium text-white text-xs">{formatDate(media.startedAt)}</dd>
              </div>
              <div class="flex items-center justify-between gap-3 py-3">
                <dt class="text-muted text-xs">{i18n.t.detail.endedLabel}</dt>
                <dd class="font-medium text-white text-xs">{formatDate(media.finishedAt)}</dd>
              </div>
              <div class="flex items-center justify-between gap-3 pt-3">
                <dt class="text-muted text-xs">{i18n.t.detail.progressShort}</dt>
                <dd class="font-medium tabular-nums text-white text-xs">{historyProgressText()}</dd>
              </div>
            </dl>
          </div>
        </div>

        <!-- Panel 2: Actions (Item 9) -->
        <div>
          <h2 class="mb-2 text-xs font-bold uppercase tracking-wider text-slate-200">{i18n.t.detail.actionsTitle}</h2>
          <div class="space-y-2 rounded-xl bg-[#222634] p-3.5 shadow-sm">
            <button
              type="button"
              class="flex w-full items-center gap-2.5 rounded-lg bg-surface/50 px-3 py-2.5 text-xs font-medium text-[#d1d5db] transition hover:bg-[#282d3d] hover:text-white disabled:cursor-not-allowed disabled:opacity-70"
              disabled={refreshBusy}
              onclick={() => void handleRefreshMetadata()}
            >
              <RefreshCw size={15} class={`text-[#34d399] ${refreshBusy ? 'animate-spin' : ''}`} aria-hidden="true" />
              {i18n.t.detail.updateMetadata}
            </button>
            {#if refreshError}<p class="text-xs text-rose-300" role="alert">{errorMessage(refreshError)}</p>{/if}

            <button
              type="button"
              class="flex w-full items-center gap-2.5 rounded-lg bg-surface/50 px-3 py-2.5 text-xs font-medium text-[#d1d5db] transition hover:bg-[#282d3d] hover:text-white"
              onclick={() => onNavigate('lists')}
            >
              <List size={15} class="text-[#a5b4fc]" aria-hidden="true" />
              {i18n.t.detail.addToLists}
            </button>

            <button
              type="button"
              class="flex w-full items-center gap-2.5 rounded-lg bg-surface/50 px-3 py-2.5 text-xs font-medium text-[#d1d5db] transition hover:bg-[#282d3d] hover:text-white"
              onclick={() => onNavigate('calendar')}
            >
              <CalendarDays size={15} class="text-[#f59e0b]" aria-hidden="true" />
              {i18n.t.detail.activity}
            </button>

            <button
              type="button"
              class="flex w-full items-center gap-2.5 rounded-lg bg-surface/50 px-3 py-2.5 text-xs font-medium text-[#d1d5db] transition hover:bg-[#282d3d] hover:text-white"
              onclick={startEdit}
            >
              <Pencil size={15} class="text-[#7dd3fc]" aria-hidden="true" />
              {i18n.t.detailModal.edit}
            </button>

            <button
              type="button"
              class="flex w-full items-center gap-2.5 rounded-lg bg-surface/50 px-3 py-2.5 text-xs font-medium text-rose-300 transition hover:bg-[#282d3d] disabled:cursor-not-allowed disabled:opacity-70"
              disabled={deleteBusy}
              onclick={() => void removeMedia()}
            >
              <Trash2 size={15} class="text-rose-400" aria-hidden="true" />
              {i18n.t.detailModal.delete}
            </button>
            {#if deleteError}<p class="text-xs text-rose-300" role="alert">{errorMessage(deleteError)}</p>{/if}
          </div>
        </div>

        <!-- Panel 3: Details (Items 8, 9, 11) -->
        <div>
          <h2 class="mb-2 text-xs font-bold uppercase tracking-wider text-slate-200">{i18n.t.detail.detailsTitle}</h2>
          <div class="rounded-xl bg-[#222634] p-5 shadow-sm">
            <dl class="divide-y divide-white/5 text-sm">
              {#each specRows(media) as row, idx (`${row.label}-${idx}`)}
                <div class="flex items-start justify-between gap-3 py-3 first:pt-0 last:pb-0">
                  <dt class="shrink-0 text-xs font-medium text-muted">{row.label}</dt>
                  <dd class="text-right text-xs font-medium text-white">
                    {#if row.isLink}
                      <a
                        href={`https://${row.value}`}
                        target="_blank"
                        rel="noreferrer"
                        class="inline-flex items-center gap-1 text-accent-soft hover:underline"
                      >
                        {row.value}
                        <ExternalLink size={11} aria-hidden="true" />
                      </a>
                    {:else}
                      {row.value}
                    {/if}
                  </dd>
                </div>
              {/each}
            </dl>
          </div>
        </div>
      </aside>

      <!-- Right Column: Header, Badges, Tabs, Tab Content -->
      <div class="min-w-0 flex-1 space-y-6">
        <!-- Title and Romaji/Type -->
        <header class="flex flex-wrap items-start justify-between gap-4">
          <div class="min-w-0">
            <p class="text-sm font-medium text-muted">{originalTitle ?? typeLabel(media)}</p>
            <h1 class="mt-1 break-words text-3xl font-extrabold tracking-tight text-white">{media.title}</h1>
          </div>
        </header>

        <!-- Category/Type Tags -->
        <ul class="flex flex-wrap gap-2">
          {#each tags(media) as tag, idx (`${tag}-${idx}`)}
            <li class="rounded-full bg-[#5844e0]/20 px-3 py-1 text-xs font-medium text-[#a5b4fc]">{tag}</li>
          {/each}
        </ul>

        <!-- Uniform External Ratings Badges (Item 6) -->
        <div class="flex flex-wrap items-center gap-2">
          {#each externalRatings as rating (rating.source)}
            {@const src = rating.source.toLowerCase()}
            <div class="inline-flex h-7 items-center gap-1.5 rounded-md border border-white/10 bg-[#222634] px-2.5 text-xs shadow-sm" title={`${rating.source}: ${rating.score.toFixed(1)}`}>
              <span class="flex items-center text-[#9ca3af]">
                {#if src.includes('anilist')}
                  <svg class="h-3.5 w-3.5 fill-[#02A9FF]" viewBox="0 0 24 24"><path d="M24 17.561v4.425H13.678v-4.425zM12.924 2.014l7.157 15.547H14.88l-1.393-3.088H8.847l-1.385 3.088H2.179L9.345 2.014h3.579zm-.897 8.358L10.37 6.452l-1.65 3.92h3.307z"/></svg>
                {:else if src.includes('tmdb')}
                  <span class="rounded bg-[#01b4e4] px-1 py-0.2 text-[9px] font-black text-black">TMDB</span>
                {:else if src.includes('rawg')}
                  <span class="rounded bg-white px-1 py-0.2 text-[9px] font-black text-black">RAWG</span>
                {:else if src.includes('kitsu')}
                  <span class="rounded bg-[#FD755C] px-1 py-0.2 text-[9px] font-black text-white">Kitsu</span>
                {:else if src.includes('mal') || src.includes('myanimelist')}
                  <span class="rounded bg-[#2e51a2] px-1 py-0.2 text-[9px] font-black text-white">MAL</span>
                {:else if src.includes('mangaupdate')}
                  <span class="rounded bg-[#3b82f6] px-1 py-0.2 text-[9px] font-black text-white">MU</span>
                {:else}
                  <Star size={12} class="text-[#f59e0b]" fill="currentColor" />
                {/if}
              </span>
              <span class="font-bold tabular-nums text-white">{rating.score.toFixed(1)}</span>
              {#if rating.votes}
                <span class="text-[10px] text-muted">({rating.votes > 1000 ? (rating.votes / 1000).toFixed(1) + 'k' : rating.votes})</span>
              {/if}
            </div>
          {/each}
        </div>

        <!-- Sub-navigation Tabs (Item 19) -->
        <nav class="flex items-center gap-1 border-b border-white/10 pb-px" aria-label="Sections">
          <button
            type="button"
            class={`flex items-center gap-2 border-b-2 px-4 py-2.5 text-sm font-semibold transition ${
              activeSubTab === 'overview'
                ? 'border-[#5844e0] text-white'
                : 'border-transparent text-muted hover:text-white'
            }`}
            onclick={() => (activeSubTab = 'overview')}
          >
            {i18n.t.detail.tabOverview}
          </button>

          {#if media.type === 'tvshow'}
            <button
              type="button"
              class={`flex items-center gap-2 border-b-2 px-4 py-2.5 text-sm font-semibold transition ${
                activeSubTab === 'episodes'
                  ? 'border-[#5844e0] text-white'
                  : 'border-transparent text-muted hover:text-white'
              }`}
              onclick={() => (activeSubTab = 'episodes')}
            >
              {i18n.t.detail.tabEpisodes}
              {#if currentSeason}
                <span class="rounded-full bg-white/10 px-2 py-0.5 text-xs text-[#a5b4fc]">
                  {currentSeason.currentEpisode}/{currentSeason.totalEpisodes}
                </span>
              {/if}
            </button>
          {/if}

          <button
            type="button"
            class={`flex items-center gap-2 border-b-2 px-4 py-2.5 text-sm font-semibold transition ${
              activeSubTab === 'related'
                ? 'border-[#5844e0] text-white'
                : 'border-transparent text-muted hover:text-white'
            }`}
            onclick={() => (activeSubTab = 'related')}
          >
            {i18n.t.detail.tabRelatedMedia}
            {#if related.length > 0}
              <span class="rounded-full bg-white/10 px-2 py-0.5 text-xs text-muted">
                {related.length}
              </span>
            {/if}
          </button>

          <button
            type="button"
            class={`flex items-center gap-2 border-b-2 px-4 py-2.5 text-sm font-semibold transition ${
              activeSubTab === 'recommendations'
                ? 'border-[#5844e0] text-white'
                : 'border-transparent text-muted hover:text-white'
            }`}
            onclick={() => { activeSubTab = 'recommendations'; void loadRecommendations() }}
          >
            <Sparkles size={14} class="text-[#a5b4fc]" aria-hidden="true" />
            {i18n.t.detail.tabRecommendations}
          </button>
        </nav>

        <!-- TAB 1: OVERVIEW -->
        {#if activeSubTab === 'overview'}
          <div class="space-y-6">
            <!-- Synopsis with conditional Read More (Item 5) -->
            <section class="space-y-2 rounded-xl bg-[#222634]/60 p-5 border border-white/5">
              <h2 class="text-xs font-bold uppercase tracking-wider text-slate-300">{i18n.t.detail.synopsisTitle}</h2>
              {#if synopsisText}
                <p class={`whitespace-pre-line break-words text-sm leading-relaxed text-[#d1d5db] ${synopsisExpandable && !synopsisExpanded ? 'line-clamp-4' : ''}`}>
                  {synopsisText}
                </p>
                {#if synopsisExpandable}
                  <button
                    type="button"
                    class="inline-flex items-center gap-1 pt-1 text-xs font-semibold text-[#a5b4fc] transition hover:text-white"
                    onclick={() => (synopsisExpanded = !synopsisExpanded)}
                  >
                    {synopsisExpanded ? i18n.t.detail.collapse : i18n.t.detail.readMore}
                    <ChevronDown size={14} class={`transition ${synopsisExpanded ? 'rotate-180' : ''}`} aria-hidden="true" />
                  </button>
                {/if}
              {:else}
                <p class="text-sm text-muted">{i18n.t.detail.noSynopsis}</p>
              {/if}
            </section>

            <!-- TV / Anime Compact Episode Progress Banner (Item 19) -->
            {#if media.type === 'tvshow' && currentSeason}
              <div class="relative overflow-hidden rounded-xl border border-white/10 bg-gradient-to-r from-[#1e2230] via-[#222634] to-[#1e2230] p-5 shadow-lg">
                <div class="flex flex-wrap items-center justify-between gap-4">
                  <div class="min-w-0">
                    <p class="text-xs font-semibold uppercase tracking-wider text-[#a5b4fc]">
                      {currentSeason.title}
                    </p>
                    <p class="mt-1 text-lg font-bold text-white">
                      {i18n.t.card.episodes(currentSeason.currentEpisode, currentSeason.totalEpisodes)}
                      <span class="ml-2 text-xs font-medium text-muted">({Math.round(seasonProgressPercent)}%)</span>
                    </p>
                  </div>

                  <div class="flex items-center gap-2">
                    {#if nextEpisode}
                      <button
                        type="button"
                        class="inline-flex items-center gap-2 rounded-lg bg-[#5844e0] px-4 py-2 text-xs font-semibold text-white shadow-md transition hover:bg-[#6b58eb] active:scale-95 disabled:opacity-50"
                        disabled={Boolean(episodeBusy)}
                        onclick={() => void toggleEpisode(nextEpisode!.number)}
                      >
                        <Check size={14} stroke-width={2.5} />
                        {i18n.t.detail.bannerNextEpisode}: E{nextEpisode.number}
                      </button>
                    {:else if currentSeason.totalEpisodes && currentSeason.currentEpisode >= currentSeason.totalEpisodes}
                      <span class="inline-flex items-center gap-1.5 rounded-lg bg-emerald-500/15 px-3 py-1.5 text-xs font-semibold text-emerald-300">
                        <CheckCircle2 size={15} />
                        {i18n.t.detail.bannerCompleted}
                      </span>
                    {/if}

                    <button
                      type="button"
                      class="rounded-lg border border-white/10 bg-surface/50 px-3 py-2 text-xs font-medium text-muted transition hover:bg-white/10 hover:text-white"
                      onclick={() => (activeSubTab = 'episodes')}
                    >
                      {i18n.t.detail.tabEpisodes} →
                    </button>
                  </div>
                </div>

                <div class="mt-4 h-2 w-full overflow-hidden rounded-full bg-black/40">
                  <div class="h-full rounded-full bg-gradient-to-r from-[#5844e0] to-[#7dd3fc] transition-all duration-300" style={`width: ${seasonProgressPercent}%`}></div>
                </div>
              </div>
            {/if}

            <!-- Book / Manga / Game Stepper Progress -->
            {#if support && support.editable}
              <section class="space-y-3 rounded-xl bg-[#222634] p-5 shadow-sm border border-white/5">
                <div class="flex items-center justify-between gap-3">
                  <h2 class="text-xs font-bold uppercase tracking-wider text-slate-300">{support.label}</h2>
                  <span class="text-sm font-semibold tabular-nums text-white">
                    {support.total !== null ? `${format(progressValue)} / ${format(support.total)}` : format(progressValue)}
                  </span>
                </div>
                <div class="flex h-10 items-center rounded-lg bg-[#13151b]">
                  <button type="button" class="grid h-full w-10 place-items-center rounded-l-lg text-[#9ca3af] transition hover:bg-[#282d3d] hover:text-white disabled:cursor-not-allowed disabled:opacity-40" aria-label={i18n.t.card.decrement} disabled={progressValue <= 0} onclick={() => stepProgress(-1)}><Minus size={15} aria-hidden="true" /></button>
                  <span class="flex-1 text-center text-sm font-semibold tabular-nums text-white">{format(progressValue)}</span>
                  <button type="button" class="grid h-full w-10 place-items-center rounded-r-lg text-[#9ca3af] transition hover:bg-[#282d3d] hover:text-white" aria-label={i18n.t.card.increment} onclick={() => stepProgress(1)}><Plus size={15} aria-hidden="true" /></button>
                </div>
                {#if support.total !== null && support.total > 0}
                  <div class="h-1.5 overflow-hidden rounded-full bg-[#13151b]"><div class="h-full rounded-full bg-[#5844e0] transition-[width] duration-200" style={`width: ${progressPercent}%`}></div></div>
                {/if}
                {#if progressError}<p class="text-xs text-rose-300" role="alert">{errorMessage(progressError)}</p>{/if}
              </section>
            {/if}
          </div>
        {/if}

        <!-- TAB 2: EPISODES (Items 1, 3, 4, 12) -->
        {#if activeSubTab === 'episodes' && media.type === 'tvshow'}
          <section class="space-y-4">
            <!-- Controls bar: Season select, Sort order (Item 3), Batch buttons (Item 1) -->
            <div class="flex flex-wrap items-center justify-between gap-3 rounded-xl bg-[#222634] p-3.5">
              <div class="flex items-center gap-3">
                {#if seasons.length > 1}
                  <select
                    class="h-9 rounded-md border border-white/10 bg-[#13151b] px-3 text-xs font-semibold text-white outline-none focus:ring-1 focus:ring-[#5844e0]"
                    value={currentSeason?.id ?? ''}
                    onchange={(event) => (selectedSeasonId = (event.currentTarget as HTMLSelectElement).value)}
                  >
                    {#each seasons as value (value.id)}
                      <option value={value.id}>{value.title || `Season ${value.seasonNumber}`}</option>
                    {/each}
                  </select>
                {:else if currentSeason}
                  <span class="text-xs font-semibold text-white">{currentSeason.title}</span>
                {/if}

                {#if currentSeason}
                  <span class="text-xs text-muted">
                    {i18n.t.card.episodes(currentSeason.currentEpisode, currentSeason.totalEpisodes)}
                  </span>
                {/if}
              </div>

              <div class="flex items-center gap-2">
                <!-- Episode Sorting Toggle (Item 3) -->
                <button
                  type="button"
                  class="inline-flex h-8 items-center gap-1.5 rounded-md border border-white/10 bg-surface/50 px-2.5 text-xs font-medium text-white transition hover:bg-white/10"
                  onclick={() => (episodeSortOrder = episodeSortOrder === 'asc' ? 'desc' : 'asc')}
                  title="Toggle episode sort order"
                >
                  <ArrowUpDown size={13} class="text-[#a5b4fc]" aria-hidden="true" />
                  {episodeSortOrder === 'asc' ? i18n.t.detail.sortAsc : i18n.t.detail.sortDesc}
                </button>

                <!-- Mark Season Watched (Item 1) -->
                <button
                  type="button"
                  class="inline-flex h-8 items-center gap-1.5 rounded-md bg-emerald-500/20 border border-emerald-500/30 px-2.5 text-xs font-semibold text-emerald-300 transition hover:bg-emerald-500/30 disabled:opacity-50"
                  disabled={Boolean(episodeBusy)}
                  onclick={() => void markSeasonComplete()}
                >
                  <Check size={13} stroke-width={2.5} />
                  {i18n.t.detail.markSeasonWatched}
                </button>

                <!-- Reset Season (Item 1) -->
                <button
                  type="button"
                  class="inline-flex h-8 items-center gap-1.5 rounded-md bg-rose-500/10 border border-rose-500/20 px-2.5 text-xs font-semibold text-rose-300 transition hover:bg-rose-500/20 disabled:opacity-50"
                  disabled={Boolean(episodeBusy)}
                  onclick={() => void resetSeasonProgress()}
                >
                  <RotateCcw size={13} />
                  {i18n.t.detail.resetSeason}
                </button>
              </div>
            </div>

            <!-- Episodes List -->
            {#if seasons.length === 0}
              <p class="rounded-xl bg-[#222634] p-5 text-sm text-muted">{i18n.t.views.noSeasons}</p>
            {:else if episodes.length === 0}
              <p class="rounded-xl bg-[#222634] p-5 text-sm text-muted">{i18n.t.common.noData}</p>
            {:else}
              <div class="space-y-2">
                {#each sortedEpisodes as episode (episode.id)}
                  <article class="flex items-center gap-3.5 rounded-xl border border-white/5 bg-[#222634] p-3.5 transition hover:bg-[#282d3d]">
                    <span class="grid h-9 w-9 shrink-0 place-items-center rounded-lg bg-[#13151b] text-xs font-bold text-[#9ca3af]">
                      E{episode.number}
                    </span>
                    <div class="min-w-0 flex-1">
                      <p class="truncate text-sm font-semibold text-white">{episode.title}</p>
                      {#if episode.airDate}
                        <p class="mt-0.5 text-xs text-muted">{formatDate(episode.airDate)}</p>
                      {/if}
                      {#if episode.description}
                        <p class="mt-1 line-clamp-2 text-xs leading-relaxed text-[#9ca3af]">{episode.description}</p>
                      {/if}
                    </div>

                    <div class="flex shrink-0 items-center gap-2">
                      <!-- Watched Checkmark / Eye toggle (Items 4, 12) -->
                      <button
                        type="button"
                        class={`grid h-8 w-8 place-items-center rounded-full border transition active:scale-95 disabled:cursor-wait disabled:opacity-60 ${
                          episode.watched
                            ? 'border-emerald-500/40 bg-emerald-500/20 text-emerald-400 hover:bg-emerald-500/30'
                            : 'border-white/10 bg-[#13151b] text-[#9ca3af] hover:bg-[#222634] hover:text-white'
                        }`}
                        aria-label={episode.watched ? i18n.t.detail.markWatched : i18n.t.detail.watchAction}
                        title={episode.watched ? 'Отменить просмотр' : i18n.t.detail.markWatched}
                        disabled={Boolean(episodeBusy)}
                        onclick={() => void toggleEpisode(episode.number)}
                      >
                        {#if episode.watched}
                          <Check size={16} stroke-width={2.8} aria-hidden="true" />
                        {:else}
                          <Eye size={15} aria-hidden="true" />
                        {/if}
                      </button>

                      <button
                        type="button"
                        class="grid h-8 w-8 place-items-center rounded-full text-muted transition hover:bg-[#13151b] hover:text-white"
                        aria-label={i18n.t.views.listsTitle}
                        title={i18n.t.views.listsTitle}
                        onclick={() => onNavigate('lists')}
                      >
                        <List size={15} aria-hidden="true" />
                      </button>
                    </div>
                  </article>
                {/each}
              </div>
              {#if progressError}<p class="text-xs text-rose-300" role="alert">{errorMessage(progressError)}</p>{/if}
            {/if}
          </section>
        {/if}

        <!-- TAB 3: RELATED MEDIA -->
        {#if activeSubTab === 'related'}
          <section class="space-y-4">
            <h2 class="text-sm font-bold uppercase tracking-wider text-slate-300">{i18n.t.detail.relatedTitle}</h2>
            {#if relatedLoading}
              <div class="grid grid-cols-2 gap-3 sm:grid-cols-3 md:grid-cols-4 lg:grid-cols-5">
                {#each Array(5) as _, idx (idx)}
                  <div class="space-y-2">
                    <div class="aspect-[2/3] w-full animate-pulse rounded-lg bg-[#222634]"></div>
                    <div class="h-3 w-3/4 animate-pulse rounded bg-[#222634]"></div>
                  </div>
                {/each}
              </div>
            {:else if relatedError}
              <div class="flex flex-col items-start gap-2 rounded-xl bg-rose-400/5 p-4">
                <p class="text-sm text-rose-200" role="alert">{errorMessage(relatedError)}</p>
                <button
                  type="button"
                  class="inline-flex items-center gap-2 rounded-md bg-accent px-3 py-1.5 text-xs font-medium text-white transition hover:bg-accent-hover"
                  onclick={() => { if (media) void loadRelated(media) }}
                >
                  <RefreshCw size={14} aria-hidden="true" />
                  {i18n.t.common.retry}
                </button>
              </div>
            {:else if related.length === 0}
              <p class="rounded-xl bg-[#222634] p-5 text-sm text-muted">{i18n.t.detail.relatedEmpty}</p>
            {:else}
              <div class="grid grid-cols-2 gap-3 sm:grid-cols-3 md:grid-cols-4 lg:grid-cols-5">
                {#each related as rel (rel.id)}
                  <button type="button" class="group flex flex-col items-start text-left" onclick={() => onOpenRelated(rel)}>
                    <div class="aspect-[2/3] w-full overflow-hidden rounded-lg bg-[#222634] transition group-hover:ring-2 group-hover:ring-[#5844e0]">
                      {#if rel.coverUrl}
                        <img src={rel.coverUrl} alt={rel.title} class="h-full w-full object-cover transition duration-300 group-hover:scale-105" />
                      {:else}
                        <div class="grid h-full place-items-center text-muted"><ImageIcon size={24} stroke-width={1.25} aria-hidden="true" /></div>
                      {/if}
                    </div>
                    <span class="mt-1.5 line-clamp-1 text-xs font-semibold text-white transition group-hover:text-[#a5b4fc]">{rel.title}</span>
                    <span class="text-[11px] text-muted">{typeLabel(rel)}</span>
                  </button>
                {/each}
              </div>
            {/if}
          </section>
        {/if}

        <!-- TAB 4: RECOMMENDATIONS (Item 19) -->
        {#if activeSubTab === 'recommendations'}
          <section class="space-y-4">
            <div class="flex items-center justify-between">
              <h2 class="text-sm font-bold uppercase tracking-wider text-slate-300">{i18n.t.detail.tabRecommendations}</h2>
              <span class="text-xs text-muted">Кэшируется на 30 дней</span>
            </div>

            {#if recommendationsLoading}
              <div class="grid grid-cols-2 gap-3 sm:grid-cols-3 md:grid-cols-4 lg:grid-cols-5">
                {#each Array(5) as _, idx (idx)}
                  <div class="space-y-2">
                    <div class="aspect-[2/3] w-full animate-pulse rounded-lg bg-[#222634]"></div>
                    <div class="h-3 w-3/4 animate-pulse rounded bg-[#222634]"></div>
                  </div>
                {/each}
              </div>
            {:else if recommendationsError}
              <div class="flex flex-col items-start gap-2 rounded-xl bg-rose-400/5 p-4">
                <p class="text-sm text-rose-200" role="alert">{errorMessage(recommendationsError)}</p>
                <button
                  type="button"
                  class="inline-flex items-center gap-2 rounded-md bg-accent px-3 py-1.5 text-xs font-medium text-white transition hover:bg-accent-hover"
                  onclick={() => void loadRecommendations()}
                >
                  <RefreshCw size={14} aria-hidden="true" />
                  {i18n.t.common.retry}
                </button>
              </div>
            {:else if recommendations.length === 0}
              <p class="rounded-xl bg-[#222634] p-5 text-sm text-muted">{i18n.t.detail.noRecommendations}</p>
            {:else}
              <div class="grid grid-cols-2 gap-3 sm:grid-cols-3 md:grid-cols-4 lg:grid-cols-5">
                {#each recommendations as rec (rec.id)}
                  <div class="group flex flex-col items-start text-left">
                    <div class="aspect-[2/3] w-full overflow-hidden rounded-lg bg-[#222634] transition group-hover:ring-2 group-hover:ring-[#5844e0]">
                      {#if rec.coverUrl}
                        <img src={rec.coverUrl} alt={rec.title} class="h-full w-full object-cover transition duration-300 group-hover:scale-105" />
                      {:else}
                        <div class="grid h-full place-items-center text-muted"><ImageIcon size={24} stroke-width={1.25} aria-hidden="true" /></div>
                      {/if}
                    </div>
                    <span class="mt-1.5 line-clamp-1 text-xs font-semibold text-white group-hover:text-[#a5b4fc]">{rec.title}</span>
                    <div class="flex items-center justify-between w-full mt-0.5 text-[11px] text-muted">
                      <span>{rec.type}</span>
                      {#if rec.score}
                        <span class="font-bold text-amber-400">★ {rec.score.toFixed(1)}</span>
                      {/if}
                    </div>
                  </div>
                {/each}
              </div>
            {/if}
          </section>
        {/if}
      </div>
    </div>
  {/if}
</div>
