<script lang="ts">
  import {
    ArrowLeft,
    ArrowUpDown,
    Bookmark,
    CalendarDays,
    Check,
    CheckCircle2,
    ChevronDown,
    ExternalLink,
    Eye,
    GitBranch,
    Image as ImageIcon,
    Layers,
    LayoutGrid,
    List,
    Minus,
    Pause,
    Pencil,
    Play,
    Plus,
    RefreshCw,
    RotateCcw,
    Sparkles,
    Star,
    Trash2,
    Languages,
    X,
  } from 'lucide-svelte'
  import { addVolume, createMedia, deleteVolume, enrichMedia, errorMessage, getExternalDetails, getMedia, getMediaItem, getSources, refreshMetadata, setProgress, setSeasonProgress, setVolumeProgress, translateText, updateMedia, updateStatus, updateVolume } from '$lib/api'
  import { i18n } from '$lib/i18n/index.svelte'
  import { showToast } from '$lib/stores/toast.svelte'
  import { clampProgress, isMangaDetail, isTvShowDetail, MEDIA_STATUS, type AppView, type MangaVolume, type MediaDetail, type MediaItem, type MediaStatus, type SourceInfo, type TvSeason } from '$lib/types'
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

  interface RelatedEntry {
    id: string
    title: string
    originalTitle?: string | null
    coverUrl: string | null
    bannerUrl?: string | null
    type: string
    format?: string | null
    year?: number | null
    relationType?: string
    rawRelationType?: string
    score?: number | null
    ratings?: { source: string; rating: number }[] | null
    description?: string | null
    episodes?: number | null
    chapters?: number | null
    volumes?: number | null
    studio?: string | null
    author?: string | null
    romajiTitle?: string | null
    duration?: number | null
    releaseDate?: string | null
    endDate?: string | null
    releaseStatus?: string | null
    externalSource?: string | null
    localItem?: MediaItem
  }

  interface RatingBadge {
    source: string
    score: number | null
    votes?: number | null
  }

  const CATEGORY_EXPECTED_SOURCES: Record<string, string[]> = {
    anime: ['AniList', 'MyAnimeList'],
    manga: ['AniList', 'MangaDex', 'MangaUpdates', 'MyAnimeList'],
    movie: ['TMDB'],
    tvshow: ['TMDB'],
    game: ['RAWG'],
    book: ['OpenLibrary'],
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

  let activeSubTab = $state<'overview' | 'episodes' | 'volumes' | 'related' | 'recommendations'>('overview')
  let episodeSortOrder = $state<'asc' | 'desc'>('asc')
  let synopsisExpanded = $state(false)
  let statusMenuOpen = $state(false)
  let userRatingPopoverOpen = $state(false)
  let availableSources = $state<SourceInfo[]>([])

  $effect(() => {
    void getSources()
      .then((res) => {
        if (res && res.length > 0) availableSources = res
      })
      .catch(() => {})
  })

  let related = $state<RelatedEntry[]>([])
  let relatedLoading = $state(false)
  let relatedError = $state<unknown>(null)
  let relatedSequence = 0
  let relatedViewMode = $state<'grouped' | 'timeline' | 'grid'>('grouped')
  let previewRelatedItem = $state<RelatedEntry | null>(null)
  let previewStatus = $state<MediaStatus>(MEDIA_STATUS.planned)
  let previewAddingBusy = $state(false)

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
  let isSynopsisTranslated = $state(false)
  let translatingSynopsis = $state(false)
  let translatedSynopsis = $state<string | null>(null)

  async function toggleTranslateSynopsis() {
    if (!media || !synopsisText || translatingSynopsis) return

    if (isSynopsisTranslated) {
      isSynopsisTranslated = false
      return
    }

    // Check if we already have a cached translation in DB matching current language
    const targetLang = i18n.current === 'en' ? 'en' : 'ru'
    if (media.translatedSynopsis && media.translationLanguage === targetLang) {
      translatedSynopsis = media.translatedSynopsis
      isSynopsisTranslated = true
      return
    }

    if (translatedSynopsis) {
      isSynopsisTranslated = true
      return
    }

    translatingSynopsis = true
    try {
      const res = await translateText(synopsisText, targetLang)
      if (res?.translatedText) {
        translatedSynopsis = res.translatedText
        isSynopsisTranslated = true
        // Persist to DB (fire-and-forget, don't block UI)
        updateMedia(media.id, { translatedSynopsis: res.translatedText, translationLanguage: targetLang }).catch(() => {})
      }
    } catch (err) {
      showToast(errorMessage(err), 'error')
    } finally {
      translatingSynopsis = false
    }
  }

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
    const results: RatingBadge[] = []
    const seen = new Set<string>()

    if (media.externalRatingsJson) {
      try {
        const parsed = JSON.parse(media.externalRatingsJson)
        if (Array.isArray(parsed) && parsed.length > 0) {
          for (const r of parsed) {
            const src = (r.source ?? r.Source ?? '').trim()
            if (!src) continue
            const rawScore = typeof r.score === 'number' ? r.score : (typeof r.Score === 'number' ? r.Score : (typeof r.rating === 'number' ? r.rating : (typeof r.Rating === 'number' ? r.Rating : null)))
            const votes = r.votes ?? r.Votes ?? null
            seen.add(src.toLowerCase())
            results.push({
              source: src,
              score: rawScore !== null && rawScore > 0 ? rawScore : null,
              votes,
            })
          }
        }
      } catch {}
    }

    if (results.length === 0 && typeof media.externalRating === 'number' && media.externalRating > 0) {
      const src = dataSource(media)
      seen.add(src.toLowerCase())
      results.push({
        source: src,
        score: media.externalRating,
        votes: media.externalRatingVotes,
      })
    }

    const isAnime = 'isAnime' in media ? Boolean((media as any).isAnime) : false
    const cat = (isAnime || (media as any).type === 'anime') ? 'anime' : media.type
    const expected = availableSources.length > 0
      ? availableSources.filter((s) => s.mediaTypes.includes(cat)).map((s) => s.name)
      : (CATEGORY_EXPECTED_SOURCES[cat] ?? [])
    for (const exp of expected) {
      const expNorm = exp.toLowerCase()
      const found = Array.from(seen).some((s) => s.includes(expNorm) || expNorm.includes(s))
      if (!found) {
        seen.add(expNorm)
        results.push({
          source: exp,
          score: null,
          votes: null,
        })
      }
    }

    return results
  })

  let mangaVolumes = $derived(media && isMangaDetail(media) ? (media.volumes ?? []) : [])
  let volumeBusy = $state('')
  let volumeError = $state<unknown>(null)

  async function stepVolumePage(vol: MangaVolume, delta: number) {
    if (!media) return
    const next = Math.max(0, vol.totalPages > 0 ? Math.min(vol.currentPage + delta, vol.totalPages) : vol.currentPage + delta)
    if (next === vol.currentPage) return

    vol.currentPage = next
    if (vol.totalPages > 0 && next >= vol.totalPages) {
      vol.status = MEDIA_STATUS.completed
    } else if (next > 0) {
      vol.status = MEDIA_STATUS.inProgress
    }

    try {
      volumeBusy = vol.id
      await setVolumeProgress(vol.id, { currentPage: next })
      onUpdate()
    } catch (err) {
      volumeError = err
    } finally {
      volumeBusy = ''
    }
  }

  async function markVolumeComplete(vol: MangaVolume) {
    if (!media || !vol.totalPages) return
    vol.currentPage = vol.totalPages
    vol.status = MEDIA_STATUS.completed

    try {
      volumeBusy = vol.id
      await setVolumeProgress(vol.id, { currentPage: vol.totalPages })
      onUpdate()
    } catch (err) {
      volumeError = err
    } finally {
      volumeBusy = ''
    }
  }

  async function unmarkVolumeComplete(vol: MangaVolume) {
    if (!media) return
    vol.currentPage = 0
    vol.status = MEDIA_STATUS.planned

    try {
      volumeBusy = vol.id
      await setVolumeProgress(vol.id, { currentPage: 0 })
      onUpdate()
    } catch (err) {
      volumeError = err
    } finally {
      volumeBusy = ''
    }
  }

  let addVolumeDialogOpen = $state(false)
  let addVolumeTitle = $state('')
  let addVolumeChapters = $state(0)

  async function handleAddVolume() {
    if (!media || media.type !== 'manga') return
    const volNum = mangaVolumes.length + 1
    addVolumeTitle = `Volume ${volNum}`
    addVolumeChapters = 0
    addVolumeDialogOpen = true
  }

  async function confirmAddVolume() {
    if (!media || media.type !== 'manga') return
    const volNum = mangaVolumes.length + 1
    addVolumeDialogOpen = false
    try {
      volumeBusy = 'add'
      await addVolume(media.id, {
        volumeNumber: volNum,
        title: addVolumeTitle || `Volume ${volNum}`,
        totalPages: 200,
        totalChapters: addVolumeChapters,
        currentPage: 0,
        currentChapter: 0,
      })
      await load(media.id, ++requestSequence, false)
      onUpdate()
    } catch (err) {
      volumeError = err
    } finally {
      volumeBusy = ''
    }
  }

  async function handleGenerateVolumes() {
    if (!media || media.type !== 'manga' || !media.totalVolumes) return
    try {
      volumeBusy = 'generate'
      const start = mangaVolumes.length + 1
      for (let i = start; i <= media.totalVolumes; i++) {
        await addVolume(media.id, {
          volumeNumber: i,
          title: `Volume ${i}`,
          totalPages: 200,
          totalChapters: 0,
          currentPage: 0,
          currentChapter: 0,
        })
      }
      await load(media.id, ++requestSequence, false)
      onUpdate()
    } catch (err) {
      volumeError = err
    } finally {
      volumeBusy = ''
    }
  }

  let editVolumeDialogOpen = $state(false)
  let editingVolume = $state<MangaVolume | null>(null)
  let editVolumeTitle = $state('')
  let editVolumePages = $state(200)
  let editVolumeChapters = $state(0)
  let editVolumeCurrentPage = $state(0)

  function openEditVolume(vol: MangaVolume) {
    editingVolume = vol
    editVolumeTitle = vol.title || `Volume ${vol.volumeNumber}`
    editVolumePages = vol.totalPages > 0 ? vol.totalPages : 200
    editVolumeChapters = vol.totalChapters ?? 0
    editVolumeCurrentPage = vol.currentPage ?? 0
    editVolumeDialogOpen = true
  }

  async function confirmEditVolume() {
    if (!editingVolume || !media) return
    editVolumeDialogOpen = false
    try {
      volumeBusy = editingVolume.id
      await updateVolume(editingVolume.id, {
        title: editVolumeTitle,
        totalPages: Math.max(editVolumePages, 1),
        totalChapters: Math.max(editVolumeChapters, 0),
        currentPage: Math.min(Math.max(editVolumeCurrentPage, 0), editVolumePages),
      })
      await load(media.id, ++requestSequence, false)
      onUpdate()
    } catch (err) {
      volumeError = err
    } finally {
      volumeBusy = ''
      editingVolume = null
    }
  }

  async function handleDeleteVolume(vol: MangaVolume) {
    if (!media) return
    const volName = vol.title || `Volume ${vol.volumeNumber}`
    if (!confirm(`Delete ${volName}?`)) return
    try {
      volumeBusy = vol.id
      await deleteVolume(vol.id)
      await load(media.id, ++requestSequence, false)
      onUpdate()
    } catch (err) {
      volumeError = err
    } finally {
      volumeBusy = ''
    }
  }

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
      if (typeof window !== 'undefined') window.scrollTo(0, 0)
      const main = document.querySelector('main')
      if (main) main.scrollTop = 0

      media = null
      isLoading = true
      loadError = null
      selectedSeasonId = null
      statusMenuOpen = false
      userRatingPopoverOpen = false
      synopsisExpanded = false
      isSynopsisTranslated = false
      translatedSynopsis = null
      translatingSynopsis = false
      activeSubTab = 'overview'
      related = []
      relatedError = null
      previewRelatedItem = null
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
      // Restore cached translation if available for current language
      const targetLang = i18n.current === 'en' ? 'en' : 'ru'
      if (loaded.translatedSynopsis && loaded.translationLanguage === targetLang) {
        translatedSynopsis = loaded.translatedSynopsis
        isSynopsisTranslated = true
      }
      void loadRelated(loaded)
      void triggerBackgroundEnrichment(loaded, sequence)
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

  async function triggerBackgroundEnrichment(current: MediaDetail, sequence: number) {
    if (!current.externalId && !current.title) return

    let hasMissingRatings = false
    const expected = availableSources.length > 0
      ? availableSources.filter((s) => s.mediaTypes.includes(current.type)).map((s) => s.name)
      : (CATEGORY_EXPECTED_SOURCES[current.type] ?? [])
    if (expected.length > 0) {
      const badges = externalRatings
      hasMissingRatings = badges.some((b) => b.score === null)
    }

    let isMangaMissingData = false
    if (current.type === 'manga') {
      isMangaMissingData = !current.totalChapters || !current.totalVolumes || !current.author
    }

    if (!hasMissingRatings && !isMangaMissingData) return

    try {
      const enriched = await enrichMedia(current.id)
      if (sequence === requestSequence && enriched) {
        media = enriched
        syncFrom(enriched)
      }
    } catch {
      // Background enrichment silently completes
    }
  }

  async function loadRelated(item: MediaItem, forceRefresh = false) {
    const sequence = ++relatedSequence
    relatedLoading = true
    relatedError = null

    try {
      const all = await getMedia()
      if (sequence !== relatedSequence) return

      const results: RelatedEntry[] = []

      // 1. Check local items with same franchiseId
      if (item.franchiseId) {
        const localMatches = all
          .filter((candidate) => candidate.franchiseId === item.franchiseId && candidate.id !== item.id)
          .toSorted((left, right) => orderOf(left) - orderOf(right) || left.title.localeCompare(right.title))

        for (const lm of localMatches) {
          results.push({
            id: lm.id,
            title: lm.title,
            coverUrl: lm.coverUrl,
            type: lm.type,
            localItem: lm,
          })
        }
      }

      // 2. Query external relations (AniList GraphQL for anime/manga)
      if (isAnime(item) || item.type === 'manga') {
        const cacheKey = `tsundoku_relations_${item.id}`
        if (forceRefresh) {
          localStorage.removeItem(cacheKey)
        }
        const cachedStr = localStorage.getItem(cacheKey)
        let externalNodes: any[] = []

        if (cachedStr) {
          try {
            const cached = JSON.parse(cachedStr)
            if (Date.now() - cached.timestamp < 2592000000 && Array.isArray(cached.items) && cached.items.length > 0) {
              externalNodes = cached.items
            }
          } catch {}
        }

        if (externalNodes.length === 0) {
          const query = `
            query ($id: Int, $idMal: Int, $search: String, $type: MediaType) {
              Media(id: $id, idMal: $idMal, search: $search, type: $type) {
                id
                title { romaji english userPreferred native }
                format
                type
                status
                description(asHtml: false)
                averageScore
                duration
                episodes
                chapters
                volumes
                coverImage { extraLarge large medium }
                bannerImage
                startDate { year month day }
                endDate { year month day }
                studios(isMain: true) { nodes { name } }
                staff(perPage: 3) {
                  edges {
                    role
                    node { name { full } }
                  }
                }
                relations {
                  edges {
                    relationType
                    node {
                      id
                      title { romaji english userPreferred native }
                      format
                      type
                      status
                      description(asHtml: false)
                      averageScore
                      duration
                      episodes
                      chapters
                      volumes
                      coverImage { extraLarge large medium }
                      bannerImage
                      startDate { year month day }
                      endDate { year month day }
                      studios(isMain: true) { nodes { name } }
                      staff(perPage: 3) {
                        edges {
                          role
                          node { name { full } }
                        }
                      }
                    }
                  }
                }
              }
            }
          `
          const source = (item.externalSource ?? '').toLowerCase()
          const isAniList = source.includes('anilist')
          const isMalOrShikimori = source.includes('shikimori') || source.includes('mal') || source.includes('jikan')
          const parsedId = item.externalId && /^\d+$/.test(item.externalId) ? parseInt(item.externalId, 10) : null
          const mediaType = item.type === 'manga' ? 'MANGA' : 'ANIME'

          let variables: Record<string, any> = { type: mediaType }
          if (isAniList && parsedId) {
            variables.id = parsedId
          } else if (isMalOrShikimori && parsedId) {
            variables.idMal = parsedId
          } else {
            variables.search = (item as any).romajiTitle?.trim() || item.title.trim()
          }

          let res = await fetch('https://graphql.anilist.co/', {
            method: 'POST',
            headers: { 'Content-Type': 'application/json' },
            body: JSON.stringify({ query, variables }),
          })

          // Fallback if id / idMal failed to match on AniList
          if (!res.ok && (variables.id || variables.idMal)) {
            const fallbackSearch = (item as any).romajiTitle?.trim() || item.title.trim()
            const fallbackRes = await fetch('https://graphql.anilist.co/', {
              method: 'POST',
              headers: { 'Content-Type': 'application/json' },
              body: JSON.stringify({ query, variables: { search: fallbackSearch, type: mediaType } }),
            })
            if (fallbackRes.ok) {
              res = fallbackRes
            }
          }

          if (res.ok) {
            const json = await res.json()
            const edges = json?.data?.Media?.relations?.edges ?? []
            externalNodes = edges.map((e: any) => {
              const node = e.node
              const desc = node?.description ? String(node.description).replace(/<[^>]*>/g, '').trim() : null
              const score = typeof node?.averageScore === 'number' ? parseFloat((node.averageScore / 10).toFixed(1)) : null
              const studio = node?.studios?.nodes?.[0]?.name ?? null
              const author = node?.staff?.edges?.find((st: any) => /story|art|original|author/i.test(st?.role ?? ''))?.node?.name?.full
                ?? node?.staff?.edges?.[0]?.node?.name?.full
                ?? null
              const originalTitle = node?.title?.native ?? null
              const romajiTitle = node?.title?.romaji ?? null
              const releaseDate = node?.startDate?.year
                ? `${String(node.startDate.year).padStart(4, '0')}-${String(node.startDate.month ?? 1).padStart(2, '0')}-${String(node.startDate.day ?? 1).padStart(2, '0')}`
                : null
              const endDate = node?.endDate?.year
                ? `${String(node.endDate.year).padStart(4, '0')}-${String(node.endDate.month ?? 1).padStart(2, '0')}-${String(node.endDate.day ?? 1).padStart(2, '0')}`
                : null

              return {
                id: String(node?.id),
                rawRelationType: e.relationType,
                relationType: formatRelationType(e.relationType),
                title: node?.title?.english || node?.title?.romaji || node?.title?.userPreferred || 'Title',
                originalTitle,
                romajiTitle,
                coverUrl: node?.coverImage?.large ?? node?.coverImage?.medium ?? null,
                bannerUrl: node?.bannerImage ?? null,
                format: node?.format ?? null,
                type: node?.type?.toLowerCase() === 'manga' ? 'manga' : 'anime',
                year: node?.startDate?.year ?? null,
                releaseDate,
                endDate,
                releaseStatus: node?.status ?? null,
                score,
                ratings: score ? [{ source: 'AniList', rating: score }] : null,
                description: desc,
                duration: typeof node?.duration === 'number' ? node.duration : null,
                episodes: node?.episodes ?? null,
                chapters: node?.chapters ?? null,
                volumes: node?.volumes ?? null,
                studio,
                author,
                externalSource: 'AniList',
              }
            })
            localStorage.setItem(cacheKey, JSON.stringify({ timestamp: Date.now(), items: externalNodes }))
          }
        }

        // Merge external nodes avoiding duplicates with local matches
        for (const ext of externalNodes) {
          if (ext.title.toLowerCase() === item.title.toLowerCase()) continue

          const matchedLocal = all.find(
            (m) =>
              (m.externalId && m.externalId === ext.id) ||
              m.title.toLowerCase() === ext.title.toLowerCase() ||
              ((m as any).romajiTitle && (m as any).romajiTitle.toLowerCase() === ext.title.toLowerCase())
          )

          if (!results.some((r) => r.id === ext.id || r.title.toLowerCase() === ext.title.toLowerCase())) {
            results.push({
              ...ext,
              coverUrl: matchedLocal?.coverUrl || ext.coverUrl,
              localItem: matchedLocal,
            })
          }
        }
      }

      if (sequence === relatedSequence) {
        related = results
      }
    } catch (error) {
      if (sequence === relatedSequence) {
        related = []
        relatedError = error
      }
    } finally {
      if (sequence === relatedSequence) relatedLoading = false
    }
  }

  function formatRelationType(relType?: string): string {
    const r = i18n.t.detail.relations
    switch (relType) {
      case 'SEQUEL':
        return r.sequel
      case 'PREQUEL':
        return r.prequel
      case 'ADAPTATION':
        return r.adaptation
      case 'SIDE_STORY':
        return r.sideStory
      case 'SPIN_OFF':
        return r.spinOff
      case 'SUMMARY':
        return r.summary
      case 'ALTERNATIVE':
        return r.alternative
      case 'CHARACTER':
        return r.character
      default:
        return r.other
    }
  }

  function formatMediaDisplayType(rel: RelatedEntry): string {
    const f = rel.format?.toUpperCase()
    const fmt = i18n.t.detail.formats
    if (f === 'MOVIE') return fmt.movie
    if (f === 'TV' || f === 'TV_SHORT') return fmt.tv
    if (f === 'OVA') return fmt.ova
    if (f === 'ONA') return fmt.ona
    if (f === 'SPECIAL') return fmt.special
    if (f === 'MANGA') return fmt.manga
    if (f === 'NOVEL') return fmt.novel
    if (f === 'ONE_SHOT') return fmt.oneShot
    if (f === 'MUSIC') return fmt.music
    return rel.type === 'manga' ? fmt.manga : fmt.tv
  }

  function statusBadgeClasses(status: MediaStatus): string {
    switch (status) {
      case 2:
        return 'bg-[#22c55e] text-white border-2 border-[#86efac]/80 ring-2 ring-[#86efac]/30'
      case 1:
        return 'bg-[#2563eb] text-white border-2 border-[#93c5fd]/80 ring-2 ring-[#93c5fd]/30'
      case 3:
        return 'bg-[#d97706] text-white border-2 border-amber-300/80 ring-2 ring-amber-300/30'
      case 4:
        return 'bg-[#dc2626] text-white border-2 border-rose-300/80 ring-2 ring-rose-300/30'
      default:
        return 'bg-[#334155] text-slate-100 border-2 border-slate-400/70 ring-2 ring-slate-400/20'
    }
  }

  interface RelationGroup {
    id: string
    title: string
    items: RelatedEntry[]
  }

  let relatedGroups = $derived.by<RelationGroup[]>(() => {
    if (related.length === 0) return []

    const main: RelatedEntry[] = []
    const spinoffs: RelatedEntry[] = []
    const adaptations: RelatedEntry[] = []
    const others: RelatedEntry[] = []

    for (const item of related) {
      const raw = (item.rawRelationType ?? '').toUpperCase()
      if (raw === 'SEQUEL' || raw === 'PREQUEL') {
        main.push(item)
      } else if (raw === 'SIDE_STORY' || raw === 'SPIN_OFF' || raw === 'CHARACTER') {
        spinoffs.push(item)
      } else if (raw === 'ADAPTATION' || item.type === 'manga' || ['MANGA', 'NOVEL', 'ONE_SHOT'].includes(item.format?.toUpperCase() ?? '')) {
        adaptations.push(item)
      } else {
        others.push(item)
      }
    }

    const groups: RelationGroup[] = []
    if (main.length > 0) {
      groups.push({ id: 'main', title: i18n.t.detail.groupMain, items: main })
    }
    if (spinoffs.length > 0) {
      groups.push({ id: 'spinoffs', title: i18n.t.detail.groupSpinoffs, items: spinoffs })
    }
    if (adaptations.length > 0) {
      groups.push({ id: 'adaptations', title: i18n.t.detail.groupAdaptations, items: adaptations })
    }
    if (others.length > 0) {
      groups.push({ id: 'others', title: i18n.t.detail.groupOthers, items: others })
    }

    return groups
  })

  interface TimelineEntry {
    id: string
    title: string
    coverUrl: string | null
    year: number | null
    formatDisplay: string
    relationType: string
    isCurrent: boolean
    localItem?: MediaItem
    rawItem?: RelatedEntry
  }

  let timelineEntries = $derived.by<TimelineEntry[]>(() => {
    if (!media) return []

    const currentYear = media.releaseDate ? new Date(media.releaseDate).getFullYear() : null
    const currentFormat = isTvShowDetail(media) ? i18n.t.detail.formats.tv : media.type === 'movie' ? i18n.t.detail.formats.movie : media.type === 'manga' ? i18n.t.detail.formats.manga : media.type

    const currentEntry: TimelineEntry = {
      id: media.id,
      title: media.title,
      coverUrl: media.coverUrl,
      year: currentYear,
      formatDisplay: currentFormat,
      relationType: i18n.t.detail.currentTitleBadge,
      isCurrent: true,
      localItem: media,
    }

    const items: TimelineEntry[] = [currentEntry]

    for (const r of related) {
      items.push({
        id: r.id,
        title: r.title,
        coverUrl: r.coverUrl,
        year: r.year ?? null,
        formatDisplay: formatMediaDisplayType(r),
        relationType: r.relationType ?? i18n.t.detail.relations.other,
        isCurrent: false,
        localItem: r.localItem,
        rawItem: r,
      })
    }

    return items.sort((a, b) => {
      if (a.year !== null && b.year !== null) return a.year - b.year
      if (a.year !== null) return -1
      if (b.year !== null) return 1
      return 0
    })
  })

  async function handleRelatedClick(rel: RelatedEntry) {
    if (rel.localItem) {
      onOpenRelated(rel.localItem)
      return
    }

    previewRelatedItem = rel
    previewStatus = MEDIA_STATUS.planned

    try {
      const details = await getExternalDetails(rel.type, rel.id, rel.title, rel.externalSource || 'AniList')
      if (details && previewRelatedItem?.id === rel.id) {
        previewRelatedItem = {
          ...previewRelatedItem,
          originalTitle: details.originalTitle || previewRelatedItem.originalTitle,
          romajiTitle: (details as any).romajiTitle || details.originalTitle || previewRelatedItem.romajiTitle,
          coverUrl: details.coverUrl || previewRelatedItem.coverUrl,
          description: details.description || previewRelatedItem.description,
          year: details.releaseYear ?? previewRelatedItem.year,
          releaseDate: details.releaseDate ?? previewRelatedItem.releaseDate,
          endDate: details.endDate ?? previewRelatedItem.endDate,
          studio: details.studio || previewRelatedItem.studio,
          author: details.author || previewRelatedItem.author,
          score: details.rating ?? previewRelatedItem.score,
          ratings: details.ratings ?? previewRelatedItem.ratings,
          episodes: details.totalCount ?? previewRelatedItem.episodes,
          duration: details.runtimeMinutes ?? previewRelatedItem.duration,
          releaseStatus: details.releaseStatus ?? previewRelatedItem.releaseStatus,
        }
      }
    } catch {}
  }

  async function addRelatedToLibrary(rel: RelatedEntry, status: MediaStatus) {
    previewAddingBusy = true
    try {
      // Ensure we have full details (including Kitsu ratings and exact release date)
      let itemDetails = rel
      let fetchedEpisodes: any = null
      try {
        const fetched = await getExternalDetails(rel.type, rel.id, rel.title, rel.externalSource || 'AniList')
        if (fetched) {
          fetchedEpisodes = fetched.episodes
          itemDetails = {
            ...rel,
            originalTitle: fetched.originalTitle || rel.originalTitle,
            romajiTitle: (fetched as any).romajiTitle || fetched.originalTitle || rel.romajiTitle,
            coverUrl: fetched.coverUrl || rel.coverUrl,
            description: fetched.description || rel.description,
            year: fetched.releaseYear ?? rel.year,
            releaseDate: fetched.releaseDate ?? rel.releaseDate,
            endDate: fetched.endDate ?? rel.endDate,
            releaseStatus: fetched.releaseStatus ?? rel.releaseStatus,
            studio: fetched.studio || rel.studio,
            author: fetched.author || rel.author,
            score: fetched.rating ?? rel.score,
            ratings: fetched.ratings ?? rel.ratings,
            episodes: fetched.totalCount ?? rel.episodes,
            duration: fetched.runtimeMinutes ?? rel.duration,
          }
        }
      } catch {}

      // Ensure current media has franchiseName or franchiseId so they are grouped together
      let franchiseName = media?.franchiseName || undefined
      let franchiseId = media?.franchiseId || undefined
      if (media && !franchiseId && !franchiseName) {
        franchiseName = media.title
        try {
          await updateMedia(media.id, { franchiseName: media.title })
          media.franchiseName = media.title
        } catch {}
      }

      const format = itemDetails.format?.toUpperCase() ?? ''
      const isMovie = format === 'MOVIE'
      const isManga = itemDetails.type === 'manga' || ['MANGA', 'NOVEL', 'ONE_SHOT'].includes(format)

      const ratingsJson = itemDetails.ratings && itemDetails.ratings.length > 0 ? JSON.stringify(itemDetails.ratings) : undefined
      const releaseDate = itemDetails.releaseDate ?? (itemDetails.year ? `${itemDetails.year}-01-01` : undefined)
      const endDate = itemDetails.endDate ?? undefined

      let created: MediaItem
      if (isMovie) {
        created = await createMedia({
          type: 'movie',
          title: itemDetails.title,
          status,
          coverUrl: itemDetails.coverUrl,
          notes: itemDetails.description,
          durationMinutes: itemDetails.duration ?? 0,
          isAnime: true,
          studio: itemDetails.studio ?? undefined,
          romajiTitle: itemDetails.romajiTitle ?? itemDetails.originalTitle ?? undefined,
          franchiseId,
          franchiseName,
          externalId: itemDetails.id,
          externalSource: itemDetails.externalSource ?? 'AniList',
          externalRating: itemDetails.score ?? undefined,
          externalRatingsJson: ratingsJson,
          releaseDate,
          endDate,
          releaseStatus: itemDetails.releaseStatus ?? undefined,
        })
      } else if (isManga) {
        created = await createMedia({
          type: 'manga',
          title: itemDetails.title,
          status,
          coverUrl: itemDetails.coverUrl,
          notes: itemDetails.description,
          author: itemDetails.author || undefined,
          romajiTitle: itemDetails.romajiTitle ?? itemDetails.originalTitle ?? undefined,
          totalChapters: itemDetails.chapters ?? null,
          totalVolumes: itemDetails.volumes ?? 1,
          currentVolume: 1,
          franchiseId,
          franchiseName,
          externalId: itemDetails.id,
          externalSource: itemDetails.externalSource ?? 'AniList',
          externalRating: itemDetails.score ?? undefined,
          externalRatingsJson: ratingsJson,
          releaseDate,
          endDate,
          releaseStatus: itemDetails.releaseStatus ?? undefined,
        })
      } else {
        created = await createMedia({
          type: 'tvshow',
          title: itemDetails.title,
          status,
          coverUrl: itemDetails.coverUrl,
          notes: itemDetails.description,
          durationMinutes: itemDetails.duration ?? undefined,
          episodeDurationMinutes: itemDetails.duration ?? undefined,
          isAnime: true,
          studio: itemDetails.studio ?? undefined,
          romajiTitle: itemDetails.romajiTitle ?? itemDetails.originalTitle ?? undefined,
          franchiseId,
          franchiseName,
          externalId: itemDetails.id,
          externalSource: itemDetails.externalSource ?? 'AniList',
          externalRating: itemDetails.score ?? undefined,
          externalRatingsJson: ratingsJson,
          releaseDate,
          endDate,
          releaseStatus: itemDetails.releaseStatus ?? undefined,
          seasons: [
            {
              seasonNumber: 1,
              title: 'Season 1',
              totalEpisodes: itemDetails.episodes ?? (fetchedEpisodes?.length || 12),
              airDate: releaseDate,
              episodesData: fetchedEpisodes && fetchedEpisodes.length > 0 ? JSON.stringify(fetchedEpisodes) : undefined,
              status,
            },
          ],
        })
      }

      showToast(i18n.t.searchModal.inLibrary, 'success')
      // Update the related grid immediately to show the "added" badge
      related = related.map((r) =>
        r.id === rel.id ? { ...r, localItem: created } : r
      )
      previewRelatedItem = null
      onUpdate()
      onOpenRelated(created)
    } catch (e) {
      console.error(e)
      showToast(errorMessage(e), 'error')
    } finally {
      previewAddingBusy = false
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

  function releaseStatusLabel(item: MediaItem): string {
    const raw = item.releaseStatus?.trim().toUpperCase()
    const r = i18n.t.detail.releaseStatuses
    if (raw) {
      if (raw === 'RELEASING' || raw === 'CURRENT' || raw === 'RETURNING SERIES') return r.releasing
      if (raw === 'FINISHED' || raw === 'COMPLETED' || raw === 'ENDED') return r.finished
      if (raw === 'NOT_YET_RELEASED' || raw === 'UPCOMING' || raw === 'IN PRODUCTION') return r.notYetReleased
      if (raw === 'CANCELLED' || raw === 'CANCELED') return r.cancelled
      if (raw === 'HIATUS' || raw === 'ON HIATUS') return r.hiatus
    }

    // Fallback: calculate from dates if no API status
    const now = new Date()
    now.setHours(0, 0, 0, 0)

    if (item.endDate) {
      const end = new Date(item.endDate)
      if (!Number.isNaN(end.getTime()) && end <= now) {
        return r.finished
      }
    }

    if (item.releaseDate) {
      const start = new Date(item.releaseDate)
      if (!Number.isNaN(start.getTime())) {
        if (start > now) return r.notYetReleased
        return r.releasing
      }
    }

    return i18n.t.detailModal.valueEmpty
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
        if (item.author) list.push(item.author)
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
      { label: i18n.t.detail.startDateLabel, value: formatDate(item.releaseDate ?? null) },
      { label: i18n.t.detail.endDateLabel, value: formatDate(item.endDate ?? null) },
      { label: i18n.t.status.label, value: releaseStatusLabel(item) },
    ]

    switch (item.type) {
      case 'tvshow':
        rows.push({ label: i18n.t.detail.episodesLabel, value: i18n.t.card.episodes(item.totalEpisodesWatched, item.totalEpisodesCount) })
        break
      case 'book':
        rows.push({ label: i18n.t.detail.pagesLabel, value: i18n.t.card.pages(item.currentPage, item.totalPages) })
        break
      case 'manga': {
        const mangaDetail = isMangaDetail(item) ? item : null
        const vols = mangaDetail?.volumes ?? []
        const hasVolChapters = vols.some((v) => (v.totalChapters ?? 0) > 0)
        const currentCh = hasVolChapters ? vols.reduce((sum, v) => sum + (v.currentChapter ?? 0), 0) : item.currentChapter
        const totalCh = hasVolChapters ? vols.reduce((sum, v) => sum + (v.totalChapters ?? 0), 0) : item.totalChapters
        rows.push({
          label: i18n.t.detail.chaptersLabel,
          value: totalCh && totalCh > 0
            ? i18n.t.card.chapters(currentCh, totalCh)
            : (i18n.current === 'ru' ? `Гл. ${currentCh} / —` : `Ch. ${currentCh} / —`),
        })

        const totalVols = vols.length > 0 ? vols.length : (item.totalVolumes ?? null)
        const curVol = item.currentVolume ?? (vols.length > 0 ? 1 : null)
        rows.push({
          label: i18n.t.detail.volumesLabel,
          value: totalVols !== null && totalVols > 0
            ? (curVol !== null && curVol > 0 ? `${curVol} / ${totalVols}` : `${totalVols}`)
            : (curVol !== null && curVol > 0 ? `${curVol} / —` : empty),
        })
        break
      }
      case 'game':
        rows.push({ label: i18n.t.detail.hoursLabel, value: i18n.t.card.hours(item.hoursPlayed ?? 0) })
        break
    }

    if (item.type === 'movie' || item.type === 'tvshow') {
      const duration = item.durationMinutes && item.durationMinutes > 0
        ? (item.type === 'movie' ? i18n.t.card.movie(item.durationMinutes) : `${item.durationMinutes} ${i18n.t.detail.minPerEp}`)
        : empty
      rows.push({ label: i18n.t.detail.durationLabel, value: duration })
    }

    switch (item.type) {
      case 'tvshow':
      case 'movie':
        rows.push({ label: i18n.t.detailModal.studio, value: item.studio || empty })
        if (item.romajiTitle) {
          rows.push({ label: i18n.t.detail.romajiTitle, value: item.romajiTitle })
        }
        break
      case 'book':
        rows.push({ label: i18n.t.detailModal.author, value: item.author || empty })
        break
      case 'manga':
        rows.push({ label: i18n.t.detailModal.author, value: item.author || empty })
        if (item.romajiTitle) {
          rows.push({ label: i18n.t.detail.romajiTitle, value: item.romajiTitle })
        }
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

<svelte:window onpointerdown={handleWindowPointerDown} onkeydown={(e) => { if (e.key === 'Escape' && previewRelatedItem) previewRelatedItem = null; }} />

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
              <div class="absolute right-0 top-full z-30 mt-2 w-48 rounded-xl border border-white/15 bg-[#1e222d] p-3 shadow-2xl shadow-black/90">
                <div class="mb-2 text-center text-xs font-semibold text-slate-300">
                  {i18n.t.detail.yourRating}
                </div>
                <div class="grid grid-cols-5 gap-1.5">
                  {#each Array(10) as _, index}
                    {@const val = index + 1}
                    <button
                      type="button"
                      class={`flex h-7 w-7 items-center justify-center rounded-md text-xs font-bold transition cursor-pointer ${
                        val === scoreValue
                          ? 'bg-[#3b82f6] text-white shadow-md'
                          : 'bg-white/5 text-slate-300 hover:bg-white/15 hover:text-white'
                      }`}
                      onclick={() => { void setScore(val); userRatingPopoverOpen = false }}
                    >
                      {val}
                    </button>
                  {/each}
                </div>
                {#if scoreValue !== null}
                  <div class="mt-2.5 border-t border-white/10 pt-2 text-center">
                    <button
                      type="button"
                      class="text-xs font-semibold text-rose-400 hover:text-rose-300 transition cursor-pointer"
                      onclick={() => { clearScore(); userRatingPopoverOpen = false }}
                    >
                      {i18n.t.detail.clearRating}
                    </button>
                  </div>
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
        <!-- Title and Romaji/Subtitle -->
        <header class="flex flex-wrap items-start justify-between gap-4">
          <div class="min-w-0">
            {#if originalTitle}
              <p class="text-sm font-medium text-muted">{originalTitle}</p>
            {/if}
            <h1 class="mt-1 break-words text-3xl font-extrabold tracking-tight text-white">{media.title}</h1>
          </div>
        </header>

        <!-- Category/Type Tags -->
        <ul class="flex flex-wrap gap-2">
          {#each tags(media) as tag, idx (`${tag}-${idx}`)}
            <li class="rounded-full bg-[#5844e0]/20 px-3 py-1 text-xs font-medium text-[#a5b4fc]">{tag}</li>
          {/each}
        </ul>

        <!-- Uniform External Ratings Badges (Item 6 & Point 1) -->
        <div class="flex flex-wrap items-center gap-2.5">
          {#each externalRatings as rating (rating.source)}
            {@const src = rating.source.toLowerCase()}
            <div
              class="inline-flex h-9 items-center gap-2 rounded-lg border border-white/15 bg-[#222634] px-3 shadow-sm transition hover:border-white/30 hover:bg-[#282d3d]"
              title={`${rating.source}: ${rating.score !== null && rating.score > 0 ? rating.score.toFixed(1) : '—'}`}
            >
              <span class="flex items-center">
                {#if src.includes('anilist')}
                  <span class="flex items-center gap-1 font-bold text-[#02a9ff] text-xs">
                    <svg class="h-4 w-4 fill-[#02a9ff]" viewBox="0 0 24 24"><path d="M24 17.561v4.425H13.678v-4.425zM12.924 2.014l7.157 15.547H14.88l-1.393-3.088H8.847l-1.385 3.088H2.179L9.345 2.014h3.579zm-.897 8.358L10.37 6.452l-1.65 3.92h3.307z"/></svg>
                    AniList
                  </span>
                {:else if src.includes('tmdb')}
                  <span class="rounded bg-[#01b4e4] px-1.5 py-0.5 text-[10px] font-black text-[#032541] tracking-wider">TMDB</span>
                {:else if src.includes('rawg')}
                  <span class="rounded bg-white px-1.5 py-0.5 text-[10px] font-black text-black tracking-wider">RAWG</span>
                {:else if src.includes('kitsu')}
                  <span class="rounded bg-[#fd755c] px-1.5 py-0.5 text-[10px] font-black text-white tracking-wider">Kitsu</span>
                {:else if src.includes('mal') || src.includes('myanimelist') || src.includes('jikan')}
                  <span class="rounded bg-[#2e51a2] px-1.5 py-0.5 text-[10px] font-black text-white tracking-wider">MAL</span>
                {:else if src.includes('mangaupdate')}
                  <span class="rounded bg-[#3b82f6] px-1.5 py-0.5 text-[10px] font-black text-white tracking-wider">MangaUpdates</span>
                {:else if src.includes('openlibrary')}
                  <span class="rounded bg-[#e1d9cb] px-1.5 py-0.5 text-[10px] font-bold text-[#2c221e]">OpenLibrary</span>
                {:else}
                  <span class="flex items-center gap-1 font-bold text-amber-400 text-xs">
                    <Star size={14} fill="currentColor" />
                    {rating.source}
                  </span>
                {/if}
              </span>
              {#if rating.score !== null && rating.score > 0}
                <span class="font-extrabold text-sm tabular-nums text-white">{rating.score.toFixed(1)}</span>
                {#if rating.votes}
                  <span class="text-xs text-muted font-normal">({rating.votes > 1000 ? (rating.votes / 1000).toFixed(1) + 'k' : rating.votes})</span>
                {/if}
              {:else}
                <span class="font-medium text-sm text-muted">—</span>
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

          {#if media.type === 'manga'}
            <button
              type="button"
              class={`flex items-center gap-2 border-b-2 px-4 py-2.5 text-sm font-semibold transition ${
                activeSubTab === 'volumes'
                  ? 'border-[#5844e0] text-white'
                  : 'border-transparent text-muted hover:text-white'
              }`}
              onclick={() => (activeSubTab = 'volumes')}
            >
              <Layers size={14} class="text-[#a5b4fc]" aria-hidden="true" />
              {i18n.t.detail.tabVolumes}
              {#if mangaVolumes.length > 0}
                <span class="rounded-full bg-white/10 px-2 py-0.5 text-xs text-[#a5b4fc]">
                  {mangaVolumes.length}
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
            <!-- Synopsis with conditional Read More (Item 5) & Translator (Item 4) -->
            <section class="space-y-2 rounded-xl bg-[#222634]/60 p-5 border border-white/5">
              <div class="flex items-center justify-between">
                <h2 class="text-xs font-bold uppercase tracking-wider text-slate-300">{i18n.t.detail.synopsisTitle}</h2>
                {#if synopsisText}
                  <button
                    type="button"
                    class="inline-flex items-center gap-1.5 rounded-md px-2 py-0.5 text-xs font-medium text-[#a5b4fc] transition hover:bg-white/10 hover:text-white cursor-pointer disabled:opacity-50"
                    disabled={translatingSynopsis}
                    onclick={() => void toggleTranslateSynopsis()}
                    title={isSynopsisTranslated ? i18n.t.detail.showOriginal : i18n.t.detail.translate}
                  >
                    {#if translatingSynopsis}
                      <div class="h-3 w-3 animate-spin rounded-full border border-accent border-t-transparent"></div>
                      <span>{i18n.t.detail.translating}</span>
                    {:else}
                      <Languages size={13} aria-hidden="true" />
                      <span>{isSynopsisTranslated ? i18n.t.detail.showOriginal : i18n.t.detail.translate}</span>
                    {/if}
                  </button>
                {/if}
              </div>
              {#if synopsisText}
                <p class={`whitespace-pre-line break-words text-sm leading-relaxed text-[#d1d5db] ${synopsisExpandable && !synopsisExpanded ? 'line-clamp-4' : ''}`}>
                  {isSynopsisTranslated && translatedSynopsis ? translatedSynopsis : synopsisText}
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

            <!-- Manga Volumes Section on Overview (Item 6) -->
            {#if media.type === 'manga'}
              {#if mangaVolumes.length > 0}
                <section class="space-y-3 rounded-xl bg-[#222634] p-5 shadow-sm border border-white/5">
                  <div class="flex items-center justify-between gap-3">
                    <div>
                      <h2 class="text-xs font-bold uppercase tracking-wider text-slate-300">{i18n.t.detail.tabVolumes}</h2>
                      <p class="text-xs text-muted mt-0.5">{mangaVolumes.length} {i18n.t.detail.volumesLabel.toLowerCase()}</p>
                    </div>
                    <div class="flex items-center gap-2">
                      <button
                        type="button"
                        class="rounded-lg border border-white/10 bg-surface/50 px-3 py-1.5 text-xs font-medium text-muted transition hover:bg-white/10 hover:text-white"
                        onclick={() => (activeSubTab = 'volumes')}
                      >
                        {i18n.t.detail.tabVolumes} →
                      </button>
                    </div>
                  </div>

                  <div class="grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-3 gap-3 pt-1">
                    {#each mangaVolumes as vol (vol.id)}
                      {@const isDone = vol.totalPages > 0 && vol.currentPage >= vol.totalPages}
                      {@const percent = vol.totalPages > 0 ? Math.min((vol.currentPage / vol.totalPages) * 100, 100) : 0}
                      <div class="rounded-lg border border-white/10 bg-[#13151b] p-3.5 space-y-2.5">
                        <div class="flex items-center justify-between gap-2">
                          <span class="text-xs font-bold text-white truncate">{vol.title || `Volume ${vol.volumeNumber}`}</span>
                          {#if isDone}
                            <span class="inline-flex items-center gap-1 rounded bg-emerald-500/15 px-1.5 py-0.5 text-[10px] font-bold text-emerald-300">
                              <Check size={11} stroke-width={2.5} />
                              OK
                            </span>
                          {:else}
                            <span class="text-xs font-semibold tabular-nums text-white">
                              {vol.currentPage} / {vol.totalPages > 0 ? vol.totalPages : 200} pp.
                            </span>
                          {/if}
                        </div>

                        <!-- Progress Bar -->
                        <div class="h-1.5 w-full overflow-hidden rounded-full bg-white/10">
                          <div class="h-full rounded-full bg-gradient-to-r from-[#5844e0] to-[#7dd3fc] transition-all duration-200" style={`width: ${percent}%`}></div>
                        </div>

                        <!-- Stepper and Action -->
                        <div class="flex items-center justify-between gap-2 pt-0.5">
                          <div class="flex h-7 items-center rounded-md bg-[#222634] border border-white/10">
                            <button
                              type="button"
                              class="grid h-full w-7 place-items-center text-muted transition hover:text-white disabled:opacity-30"
                              disabled={vol.currentPage <= 0 || Boolean(volumeBusy)}
                              onclick={() => void stepVolumePage(vol, -1)}
                            >
                              <Minus size={12} />
                            </button>
                            <span class="px-2 text-xs font-semibold tabular-nums text-white">{vol.currentPage}</span>
                            <button
                              type="button"
                              class="grid h-full w-7 place-items-center text-muted transition hover:text-white disabled:opacity-30"
                              disabled={(vol.totalPages > 0 && vol.currentPage >= vol.totalPages) || Boolean(volumeBusy)}
                              onclick={() => void stepVolumePage(vol, 1)}
                            >
                              <Plus size={12} />
                            </button>
                          </div>

                          <div class="flex items-center gap-1">
                            <button
                              type="button"
                              class="grid h-7 w-7 place-items-center rounded-md bg-white/5 text-muted transition hover:bg-white/10 hover:text-white"
                              onclick={() => openEditVolume(vol)}
                              title="Edit volume"
                            >
                              <Pencil size={11} />
                            </button>
                            <button
                              type="button"
                              class="grid h-7 w-7 place-items-center rounded-md bg-white/5 text-muted transition hover:bg-rose-500/20 hover:text-rose-400"
                              onclick={() => void handleDeleteVolume(vol)}
                              title="Delete volume"
                            >
                              <Trash2 size={11} />
                            </button>

                            {#if !isDone}
                              <button
                                type="button"
                                class="inline-flex h-7 items-center gap-1 rounded-md bg-emerald-500/15 px-2 text-[11px] font-semibold text-emerald-300 transition hover:bg-emerald-500/25 disabled:opacity-50"
                                disabled={Boolean(volumeBusy)}
                                onclick={() => void markVolumeComplete(vol)}
                                title={i18n.t.detail.markVolumeComplete}
                              >
                                <Check size={12} />
                              </button>
                            {:else}
                              <button
                                type="button"
                                class="inline-flex h-7 items-center gap-1 rounded-md bg-white/5 px-2 text-[11px] font-semibold text-muted transition hover:bg-white/10 hover:text-white disabled:opacity-50"
                                disabled={Boolean(volumeBusy)}
                                onclick={() => void unmarkVolumeComplete(vol)}
                                title="Unmark complete"
                              >
                                <X size={12} />
                              </button>
                            {/if}
                          </div>
                        </div>
                      </div>
                    {/each}
                  </div>
                </section>
              {:else if media.totalVolumes && media.totalVolumes > 0}
                <section class="space-y-3 rounded-xl bg-[#222634] p-5 shadow-sm border border-white/5">
                  <div class="flex items-center justify-between gap-3">
                    <div>
                      <h2 class="text-xs font-bold uppercase tracking-wider text-slate-300">{i18n.t.detail.tabVolumes}</h2>
                      <p class="text-xs text-muted mt-0.5">{media.totalVolumes} {i18n.t.detail.volumesLabel.toLowerCase()}</p>
                    </div>
                    <button
                      type="button"
                      class="inline-flex items-center gap-1.5 rounded-lg bg-[#5844e0] px-3 py-1.5 text-xs font-semibold text-white transition hover:bg-[#6854f0] disabled:opacity-50"
                      disabled={Boolean(volumeBusy)}
                      onclick={() => void handleGenerateVolumes()}
                    >
                      <Plus size={13} />
                      {i18n.t.detail.addVolume} ({media.totalVolumes})
                    </button>
                  </div>
                </section>
              {:else}
                <section class="space-y-3 rounded-xl bg-[#222634] p-5 shadow-sm border border-white/5">
                  <div class="flex items-center justify-between gap-3">
                    <div>
                      <h2 class="text-xs font-bold uppercase tracking-wider text-slate-300">{i18n.t.detail.tabVolumes}</h2>
                      <p class="text-xs text-muted mt-0.5">0 {i18n.t.detail.volumesLabel.toLowerCase()}</p>
                    </div>
                    <button
                      type="button"
                      class="inline-flex items-center gap-1.5 rounded-lg bg-[#5844e0] px-3 py-1.5 text-xs font-semibold text-white transition hover:bg-[#6854f0] disabled:opacity-50"
                      disabled={Boolean(volumeBusy)}
                      onclick={() => void handleAddVolume()}
                    >
                      <Plus size={13} />
                      {i18n.t.detail.addVolume}
                    </button>
                  </div>
                </section>
              {/if}
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
                        title={episode.watched ? i18n.t.detail.unwatchAction : i18n.t.detail.markWatched}
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

        <!-- TAB: MANGA VOLUMES -->
        {#if activeSubTab === 'volumes' && media.type === 'manga'}
          <section class="space-y-4">
            <div class="flex flex-wrap items-center justify-between gap-3 rounded-xl bg-[#222634] p-3.5">
              <div class="flex items-center gap-2">
                <Layers size={16} class="text-[#a5b4fc]" />
                <h3 class="text-sm font-bold text-white">{i18n.t.detail.tabVolumes}</h3>
                <span class="rounded-full bg-white/10 px-2.5 py-0.5 text-xs font-semibold text-[#a5b4fc]">
                  {mangaVolumes.length}
                </span>
              </div>

              <div class="flex items-center gap-2">
                {#if media.totalVolumes && mangaVolumes.length < media.totalVolumes}
                  <button
                    type="button"
                    class="inline-flex h-8 items-center gap-1.5 rounded-md bg-white/10 px-3 text-xs font-semibold text-white transition hover:bg-white/20 disabled:opacity-50"
                    disabled={Boolean(volumeBusy)}
                    onclick={() => void handleGenerateVolumes()}
                  >
                    <Plus size={13} />
                    {i18n.t.detail.addVolume} ({media.totalVolumes - mangaVolumes.length})
                  </button>
                {/if}
                <button
                  type="button"
                  class="inline-flex h-8 items-center gap-1.5 rounded-md bg-[#5844e0] px-3 text-xs font-semibold text-white transition hover:bg-[#6854f0] disabled:opacity-50"
                  disabled={Boolean(volumeBusy)}
                  onclick={() => void handleAddVolume()}
                >
                  <Plus size={13} />
                  {i18n.t.detail.addVolume}
                </button>
              </div>
            </div>

            {#if mangaVolumes.length === 0}
              <div class="rounded-xl border border-white/10 bg-[#222634]/40 p-8 text-center space-y-3">
                <Layers size={36} class="mx-auto text-muted/60" />
                <p class="text-sm text-muted">No volumes tracked yet for this manga.</p>
                <button
                  type="button"
                  class="inline-flex items-center gap-1.5 rounded-lg bg-[#5844e0] px-4 py-2 text-xs font-semibold text-white transition hover:bg-[#6854f0]"
                  disabled={Boolean(volumeBusy)}
                  onclick={() => void handleAddVolume()}
                >
                  <Plus size={14} />
                  {i18n.t.detail.addVolume}
                </button>
              </div>
            {:else}
              <div class="grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-3 gap-4">
                {#each mangaVolumes as vol (vol.id)}
                  {@const isDone = vol.totalPages > 0 && vol.currentPage >= vol.totalPages}
                  {@const percent = vol.totalPages > 0 ? Math.min((vol.currentPage / vol.totalPages) * 100, 100) : 0}
                  <div class="rounded-xl border border-white/10 bg-[#222634] p-4 space-y-3 shadow-sm hover:border-white/20 transition">
                    <div class="flex items-start justify-between gap-2">
                      <div class="min-w-0">
                        <h4 class="text-sm font-bold text-white truncate">{vol.title || `Volume ${vol.volumeNumber}`}</h4>
                        {#if vol.totalChapters > 0}
                          <p class="text-xs text-muted mt-0.5">{i18n.t.card.chapters(vol.currentChapter, vol.totalChapters)}</p>
                        {/if}
                      </div>
                      {#if isDone}
                        <span class="inline-flex items-center gap-1 rounded bg-emerald-500/15 px-2 py-0.5 text-xs font-bold text-emerald-300">
                          <Check size={12} stroke-width={2.5} />
                          {i18n.t.status.completed}
                        </span>
                      {:else}
                        <span class="text-xs font-semibold tabular-nums text-white">
                          {vol.currentPage} / {vol.totalPages > 0 ? vol.totalPages : 200} pp.
                        </span>
                      {/if}
                    </div>

                    <!-- Progress Bar -->
                    <div class="space-y-1">
                      <div class="flex justify-between text-[11px] text-muted">
                        <span>{i18n.t.detail.volumeProgress}</span>
                        <span>{percent.toFixed(0)}%</span>
                      </div>
                      <div class="h-2 w-full overflow-hidden rounded-full bg-black/40">
                        <div class="h-full rounded-full bg-gradient-to-r from-[#5844e0] to-[#7dd3fc] transition-all duration-300" style={`width: ${percent}%`}></div>
                      </div>
                    </div>

                    <!-- Stepper & Actions -->
                    <div class="flex items-center justify-between gap-2 pt-1 border-t border-white/5">
                      <div class="flex h-8 items-center rounded-lg bg-[#13151b] border border-white/10">
                        <button
                          type="button"
                          class="grid h-full w-8 place-items-center text-muted transition hover:text-white disabled:opacity-30"
                          disabled={vol.currentPage <= 0 || Boolean(volumeBusy)}
                          onclick={() => void stepVolumePage(vol, -1)}
                        >
                          <Minus size={13} />
                        </button>
                        <span class="px-2.5 text-xs font-semibold tabular-nums text-white">{vol.currentPage}</span>
                        <button
                          type="button"
                          class="grid h-full w-8 place-items-center text-muted transition hover:text-white disabled:opacity-30"
                          disabled={(vol.totalPages > 0 && vol.currentPage >= vol.totalPages) || Boolean(volumeBusy)}
                          onclick={() => void stepVolumePage(vol, 1)}
                        >
                          <Plus size={13} />
                        </button>
                      </div>

                      <div class="flex items-center gap-1.5">
                        <button
                          type="button"
                          class="inline-flex h-8 items-center gap-1 rounded-lg bg-white/5 border border-white/10 px-2 text-xs font-semibold text-muted hover:bg-white/10 hover:text-white transition"
                          onclick={() => openEditVolume(vol)}
                          title="Edit volume"
                        >
                          <Pencil size={12} />
                        </button>
                        <button
                          type="button"
                          class="inline-flex h-8 items-center gap-1 rounded-lg bg-white/5 border border-white/10 px-2 text-xs font-semibold text-muted hover:bg-rose-500/20 hover:text-rose-400 transition"
                          onclick={() => void handleDeleteVolume(vol)}
                          title="Delete volume"
                        >
                          <Trash2 size={12} />
                        </button>

                        {#if !isDone}
                          <button
                            type="button"
                            class="inline-flex h-8 items-center gap-1 rounded-lg bg-emerald-500/15 border border-emerald-500/25 px-2.5 text-xs font-semibold text-emerald-300 transition hover:bg-emerald-500/25 disabled:opacity-50"
                            disabled={Boolean(volumeBusy)}
                            onclick={() => void markVolumeComplete(vol)}
                          >
                            <Check size={13} />
                            {i18n.t.detail.watchAction}
                          </button>
                        {:else}
                          <button
                            type="button"
                            class="inline-flex h-8 items-center gap-1 rounded-lg bg-white/5 border border-white/10 px-2.5 text-xs font-semibold text-muted transition hover:bg-white/10 hover:text-white disabled:opacity-50"
                            disabled={Boolean(volumeBusy)}
                            onclick={() => void unmarkVolumeComplete(vol)}
                          >
                            <X size={13} />
                            Unmark
                          </button>
                        {/if}
                      </div>
                    </div>
                  </div>
                {/each}
              </div>
            {/if}
          </section>
        {/if}

        <!-- TAB 3: RELATED MEDIA -->
        {#if activeSubTab === 'related'}
          <section class="space-y-6">
            <div class="flex flex-col gap-3 sm:flex-row sm:items-center sm:justify-between">
              <div>
                <h2 class="text-sm font-bold uppercase tracking-wider text-slate-300">{i18n.t.detail.relatedTitle}</h2>
                <p class="text-xs text-muted">{i18n.t.detail.relatedSubtitle}</p>
              </div>

              <!-- View Switchers (Items 2, 4) - Compact icon-only square buttons with hover tooltip -->
              {#if related.length > 0}
                <div class="inline-flex items-center rounded-lg border border-white/10 bg-[#171a23] p-1 self-start sm:self-auto gap-1">
                  <button
                    type="button"
                    class={`grid h-8 w-8 place-items-center rounded-md transition cursor-pointer ${
                      relatedViewMode === 'grouped'
                        ? 'bg-accent text-white shadow'
                        : 'text-slate-400 hover:bg-white/5 hover:text-white'
                    }`}
                    title={i18n.t.detail.viewGrouped}
                    aria-label={i18n.t.detail.viewGrouped}
                    onclick={() => (relatedViewMode = 'grouped')}
                  >
                    <Layers size={17} />
                  </button>

                  <button
                    type="button"
                    class={`grid h-8 w-8 place-items-center rounded-md transition cursor-pointer ${
                      relatedViewMode === 'timeline'
                        ? 'bg-accent text-white shadow'
                        : 'text-slate-400 hover:bg-white/5 hover:text-white'
                    }`}
                    title={i18n.t.detail.viewTimeline}
                    aria-label={i18n.t.detail.viewTimeline}
                    onclick={() => (relatedViewMode = 'timeline')}
                  >
                    <GitBranch size={17} />
                  </button>

                  <button
                    type="button"
                    class={`grid h-8 w-8 place-items-center rounded-md transition cursor-pointer ${
                      relatedViewMode === 'grid'
                        ? 'bg-accent text-white shadow'
                        : 'text-slate-400 hover:bg-white/5 hover:text-white'
                    }`}
                    title={i18n.t.detail.viewGrid}
                    aria-label={i18n.t.detail.viewGrid}
                    onclick={() => (relatedViewMode = 'grid')}
                  >
                    <LayoutGrid size={17} />
                  </button>
                </div>
              {/if}
            </div>

            {#if relatedLoading}
              <div class="grid grid-cols-2 gap-3 sm:grid-cols-3 md:grid-cols-4 lg:grid-cols-5">
                {#each Array(5) as _, idx (idx)}
                  <div class="space-y-2">
                    <div class="aspect-[2/3] w-full animate-pulse rounded-xl bg-[#222634]"></div>
                    <div class="h-3 w-3/4 animate-pulse rounded bg-[#222634]"></div>
                  </div>
                {/each}
              </div>
            {:else if relatedError}
              <div class="flex flex-col items-start gap-2 rounded-xl bg-rose-400/5 p-4">
                <p class="text-sm text-rose-200" role="alert">{errorMessage(relatedError)}</p>
                <button
                  type="button"
                  class="inline-flex items-center gap-2 rounded-md bg-accent px-3 py-1.5 text-xs font-medium text-white transition hover:bg-accent-hover cursor-pointer"
                  onclick={() => { if (media) void loadRelated(media, true) }}
                >
                  <RefreshCw size={14} aria-hidden="true" />
                  {i18n.t.common.retry}
                </button>
              </div>
            {:else if related.length === 0}
              <p class="rounded-xl bg-[#222634] p-5 text-sm text-muted">{i18n.t.detail.relatedEmpty}</p>
            {:else}
              <!-- Snippet for related card with bottom gradient & status/rating badges -->
              {#snippet relatedCard(rel: RelatedEntry)}
                <button
                  type="button"
                  class="group relative flex flex-col aspect-[2/3] w-full overflow-hidden rounded-xl border border-white/5 bg-[#1e2230] text-left transition duration-300 hover:border-accent/50 hover:shadow-xl hover:shadow-accent/10 cursor-pointer"
                  onclick={() => handleRelatedClick(rel)}
                >
                  <!-- Poster image -->
                  {#if rel.coverUrl}
                    <img
                      src={rel.coverUrl}
                      alt={rel.title}
                      class="h-full w-full object-cover transition duration-500 group-hover:scale-105"
                      loading="lazy"
                    />
                  {:else}
                    <div class="grid h-full w-full place-items-center bg-[#13151b] text-muted">
                      <ImageIcon size={32} stroke-width={1.25} aria-hidden="true" />
                    </div>
                  {/if}

                  <!-- Top-left Status & Rating overlay (matching main window) -->
                  {#if rel.localItem}
                    <div class="absolute left-2.5 top-2.5 z-20 flex items-center">
                      <!-- Status circle -->
                      <div
                        class={`relative z-10 flex h-7 w-7 items-center justify-center rounded-full shadow-lg backdrop-blur ${statusBadgeClasses(rel.localItem.status)}`}
                        title={statusLabel(rel.localItem.status)}
                      >
                        {#if rel.localItem.status === 0}
                          <Bookmark size={13} stroke-width={2.2} />
                        {:else if rel.localItem.status === 1}
                          <Play size={12} fill="currentColor" class="translate-x-0.5" />
                        {:else if rel.localItem.status === 2}
                          <Check size={14} stroke-width={3} />
                        {:else if rel.localItem.status === 3}
                          <Pause size={12} stroke-width={2.5} />
                        {:else if rel.localItem.status === 4}
                          <X size={13} stroke-width={2.5} />
                        {/if}
                      </div>

                      <!-- Rating circle -->
                      {#if rel.localItem.score !== null && rel.localItem.score > 0}
                        <div
                          class="relative z-20 -ml-2 flex h-7 w-7 items-center justify-center rounded-full bg-[#2a3cb8] text-white shadow-lg border-2 border-[#7786ee]/80 ring-2 ring-[#7786ee]/30 font-black text-xs select-none"
                          title={`${i18n.t.createModal.fields.score}: ${rel.localItem.score}`}
                        >
                          {rel.localItem.score}
                        </div>
                      {/if}
                    </div>
                  {/if}

                  <!-- Bottom overlay with strong dark gradient and readable typography -->
                  <div class="absolute inset-x-0 bottom-0 bg-gradient-to-t from-black/95 via-black/85 to-transparent p-3 pt-12 flex flex-col justify-end pointer-events-none">
                    <span class="line-clamp-2 text-sm font-bold leading-snug text-white transition group-hover:text-accent-soft drop-shadow-md">
                      {rel.title}
                    </span>
                    <div class="mt-1.5 flex items-center justify-between gap-1 text-xs">
                      {#if rel.relationType}
                        <span class="rounded bg-accent/25 border border-accent/40 px-2 py-0.5 text-[11px] font-semibold text-accent-soft backdrop-blur-sm">
                          {rel.relationType}
                        </span>
                      {:else}
                        <span class="text-[11px] text-slate-300">{formatMediaDisplayType(rel)}</span>
                      {/if}
                      <span class="font-medium text-slate-300 text-[11px]">
                        {[rel.year, formatMediaDisplayType(rel)].filter(Boolean).join(' · ')}
                      </span>
                    </div>
                  </div>
                </button>
              {/snippet}

              <!-- 1. GROUPED VIEW -->
              {#if relatedViewMode === 'grouped'}
                <div class="space-y-8">
                  {#each relatedGroups as group (group.id)}
                    <div class="space-y-3">
                      <div class="flex items-center gap-2.5 border-b border-white/10 pb-2.5">
                        <h3 class="text-base sm:text-lg font-bold text-white tracking-tight">{group.title}</h3>
                        <span class="rounded-full bg-white/10 px-2.5 py-0.5 text-xs font-bold text-muted">
                          {group.items.length}
                        </span>
                      </div>
                      <div class="grid grid-cols-2 gap-3 sm:grid-cols-3 md:grid-cols-4 lg:grid-cols-5">
                        {#each group.items as rel (rel.id)}
                          {@render relatedCard(rel)}
                        {/each}
                      </div>
                    </div>
                  {/each}
                </div>

              <!-- 2. TIMELINE / CHRONOLOGY VIEW -->
              {:else if relatedViewMode === 'timeline'}
                <div class="relative pl-6 sm:pl-8 space-y-4 before:absolute before:bottom-3 before:left-[11px] sm:before:left-[15px] before:top-3 before:w-0.5 before:bg-gradient-to-b before:from-accent before:via-accent/40 before:to-transparent">
                  {#each timelineEntries as item (item.id)}
                    <div class="relative flex items-center gap-4 group">
                      <!-- Node circle marker on the timeline line -->
                      <div class={`absolute -left-6 sm:-left-8 flex h-6 w-6 items-center justify-center rounded-full border-2 transition-transform duration-300 group-hover:scale-110 ${
                        item.isCurrent
                          ? 'border-accent bg-accent text-white shadow-lg shadow-accent/50 ring-4 ring-accent/20'
                          : item.localItem
                            ? 'border-emerald-500 bg-[#13151b] text-emerald-400'
                            : 'border-white/20 bg-[#13151b] text-slate-400'
                      }`}>
                        {#if item.isCurrent}
                          <div class="h-2 w-2 rounded-full bg-white"></div>
                        {:else if item.localItem}
                          <Check size={12} stroke-width={3} />
                        {:else}
                          <div class="h-1.5 w-1.5 rounded-full bg-white/40"></div>
                        {/if}
                      </div>

                      <!-- Timeline row card -->
                      <button
                        type="button"
                        class={`flex flex-1 items-center gap-3.5 rounded-xl border p-2.5 transition text-left cursor-pointer ${
                          item.isCurrent
                            ? 'border-accent/60 bg-accent/10 shadow-md ring-1 ring-accent/30'
                            : 'border-white/5 bg-[#222634] hover:border-white/20 hover:bg-[#282d3d]'
                        }`}
                        onclick={() => {
                          if (item.isCurrent) return
                          if (item.rawItem) handleRelatedClick(item.rawItem)
                        }}
                      >
                        <!-- Mini poster -->
                        <div class="relative aspect-[2/3] h-16 shrink-0 overflow-hidden rounded-lg bg-[#13151b]">
                          {#if item.coverUrl}
                            <img src={item.coverUrl} alt={item.title} class="h-full w-full object-cover" />
                          {:else}
                            <div class="grid h-full place-items-center text-muted"><ImageIcon size={18} /></div>
                          {/if}

                          {#if item.localItem}
                            <div class="absolute left-1 top-1 flex items-center">
                              <div class={`h-4 w-4 rounded-full flex items-center justify-center ${statusBadgeClasses(item.localItem.status)}`}>
                                {#if item.localItem.status === 2}
                                  <Check size={8} stroke-width={3} />
                                {/if}
                              </div>
                            </div>
                          {/if}
                        </div>

                        <div class="min-w-0 flex-1">
                          <div class="flex flex-wrap items-center gap-2">
                            {#if item.year}
                              <span class="rounded bg-white/10 px-1.5 py-0.5 text-[11px] font-bold text-accent-soft">
                                {item.year}
                              </span>
                            {/if}
                            <span class={`rounded px-1.5 py-0.5 text-[10px] font-semibold ${
                              item.isCurrent
                                ? 'bg-accent text-white'
                                : 'bg-white/5 text-slate-300 border border-white/10'
                            }`}>
                              {item.relationType}
                            </span>
                            <span class="text-[11px] text-muted">{item.formatDisplay}</span>
                          </div>

                          <h3 class={`mt-1 truncate text-sm font-bold ${item.isCurrent ? 'text-accent-soft' : 'text-white group-hover:text-accent-soft'}`}>
                            {item.title}
                          </h3>
                        </div>

                        <!-- Rating / Action on right -->
                        <div class="shrink-0 pr-2">
                          {#if item.localItem?.score}
                            <span class="rounded-full bg-[#2a3cb8] border border-[#7786ee]/80 px-2.5 py-0.5 text-xs font-black text-white">
                              {item.localItem.score}
                            </span>
                          {:else if !item.localItem && !item.isCurrent}
                            <span class="rounded-md border border-white/10 bg-white/5 px-2.5 py-1 text-xs font-medium text-slate-300 group-hover:border-accent/40 group-hover:text-accent-soft">
                              {i18n.t.detail.overviewBadge}
                            </span>
                          {/if}
                        </div>
                      </button>
                    </div>
                  {/each}
                </div>

              <!-- 3. FLAT GRID VIEW -->
              {:else}
                <div class="grid grid-cols-2 gap-3 sm:grid-cols-3 md:grid-cols-4 lg:grid-cols-5">
                  {#each related as rel (rel.id)}
                    {@render relatedCard(rel)}
                  {/each}
                </div>
              {/if}
            {/if}
          </section>

          <!-- PREVIEW MODAL FOR UNADDED RELATED ITEMS (Items 3, 5 - Identical to SearchModal preview) -->
          {#if previewRelatedItem}
            <div
              class="fixed inset-0 z-[60] flex items-center justify-center overflow-y-auto bg-black/75 p-4 backdrop-blur-md"
              role="presentation"
              onclick={() => (previewRelatedItem = null)}
            >
              <!-- svelte-ignore a11y_click_events_have_key_events -->
              <!-- svelte-ignore a11y_no_noninteractive_element_interactions -->
              <div
                class="relative flex max-h-[85vh] w-full max-w-2xl flex-col overflow-hidden rounded-xl border border-border bg-surface p-6 shadow-2xl"
                role="dialog"
                aria-modal="true"
                tabindex="-1"
                onclick={(e) => e.stopPropagation()}
              >
                <button
                  type="button"
                  class="absolute right-4 top-4 grid h-8 w-8 place-items-center rounded-lg text-muted transition hover:bg-elevated hover:text-ink cursor-pointer"
                  title={i18n.t.common.close}
                  aria-label={i18n.t.common.close}
                  onclick={() => (previewRelatedItem = null)}
                >
                  <X size={18} aria-hidden="true" />
                </button>

                <div class="overflow-y-auto pr-1">
                  <div class="flex flex-col gap-5 sm:flex-row">
                    <div class="mx-auto aspect-[2/3] w-40 shrink-0 overflow-hidden rounded-lg bg-canvas sm:mx-0">
                      {#if previewRelatedItem.coverUrl}
                        <img src={previewRelatedItem.coverUrl} alt={previewRelatedItem.title} class="h-full w-full object-cover" />
                      {:else}
                        <div class="grid h-full place-items-center text-muted"><ImageIcon size={32} stroke-width={1.25} aria-hidden="true" /></div>
                      {/if}
                    </div>

                    <div class="min-w-0 flex-1 space-y-3">
                      <div class="flex flex-wrap items-center gap-2">
                        <span class="rounded-full bg-elevated px-2.5 py-0.5 text-[11px] font-semibold uppercase tracking-wider text-accent-soft">
                          {formatMediaDisplayType(previewRelatedItem)}
                        </span>
                        {#if previewRelatedItem.relationType}
                          <span class="rounded-full bg-accent/20 border border-accent/40 px-2.5 py-0.5 text-[11px] font-semibold text-accent-soft">
                            {previewRelatedItem.relationType}
                          </span>
                        {/if}
                        <span class="rounded-full border border-border bg-elevated px-2.5 py-0.5 text-[11px] font-semibold text-muted">
                          AniList
                        </span>
                      </div>

                      <div>
                        <h3 class="mt-1 text-lg font-bold text-ink">{previewRelatedItem.title}</h3>
                        {#if previewRelatedItem.originalTitle}
                          <p class="text-xs text-muted">{previewRelatedItem.originalTitle}</p>
                        {/if}
                      </div>

                      <!-- Ratings -->
                      {#if previewRelatedItem.ratings && previewRelatedItem.ratings.length > 0}
                        <div class="flex flex-wrap items-center gap-2">
                          {#each previewRelatedItem.ratings as r}
                            <div class="inline-flex items-center gap-1 rounded-md border border-border bg-elevated px-2 py-0.5 text-xs">
                              <span class="font-medium text-muted">{r.source}:</span>
                              <span class="flex items-center gap-0.5 font-bold text-star">
                                <Star size={11} fill="currentColor" />
                                {(r.rating ?? 0).toFixed(1)}
                              </span>
                            </div>
                          {/each}
                        </div>
                      {:else if previewRelatedItem.score}
                        <div class="flex flex-wrap items-center gap-2">
                          <div class="inline-flex items-center gap-1 rounded-md border border-border bg-elevated px-2 py-0.5 text-xs">
                            <span class="font-medium text-muted">{previewRelatedItem.externalSource || 'AniList'}:</span>
                            <span class="flex items-center gap-0.5 font-bold text-star">
                              <Star size={11} fill="currentColor" />
                              {previewRelatedItem.score.toFixed(1)}
                            </span>
                          </div>
                        </div>
                      {:else}
                        <div class="inline-flex items-center gap-1 rounded-md border border-border bg-elevated px-2 py-0.5 text-xs text-muted">
                          <span>{i18n.t.detail.previewModal.noRatings}</span>
                        </div>
                      {/if}

                      <div class="space-y-1 text-xs text-muted">
                        <div>
                          <span class="font-medium text-ink">{i18n.t.detail.previewModal.year}:</span>
                          {previewRelatedItem.year ?? i18n.t.detail.previewModal.noData}
                        </div>
                        {#if previewRelatedItem.type === 'manga' || previewRelatedItem.format === 'NOVEL' || previewRelatedItem.format === 'MANGA'}
                          <div>
                            <span class="font-medium text-ink">{i18n.t.detail.previewModal.author}:</span>
                            {previewRelatedItem.author ?? i18n.t.detail.previewModal.noData}
                          </div>
                        {:else}
                          <div>
                            <span class="font-medium text-ink">{i18n.t.detail.previewModal.studio}:</span>
                            {previewRelatedItem.studio ?? i18n.t.detail.previewModal.noData}
                          </div>
                        {/if}
                        <div>
                          <span class="font-medium text-ink">{i18n.t.detail.previewModal.count}:</span>
                          {#if previewRelatedItem.episodes}
                            {previewRelatedItem.episodes} {i18n.t.searchModal.countUnits.anime}
                          {:else if previewRelatedItem.chapters}
                            {previewRelatedItem.chapters} {i18n.t.searchModal.countUnits.manga}
                          {:else if previewRelatedItem.volumes}
                            {previewRelatedItem.volumes} {i18n.t.searchModal.countUnits.manga}
                          {:else}
                            {i18n.t.detail.previewModal.noData}
                          {/if}
                        </div>
                      </div>

                      <div class="pt-2 flex flex-wrap items-center gap-3">
                        <div class="flex items-center gap-2">
                          <label for="preview-status" class="text-xs font-medium text-muted">
                            {i18n.t.detail.previewModal.initialStatus}:
                          </label>
                          <select
                            id="preview-status"
                            bind:value={previewStatus}
                            class="rounded-md border border-border bg-elevated px-2.5 py-1.5 text-xs font-medium text-ink outline-none focus:border-accent"
                          >
                            {#each statusOptions as opt}
                              <option value={opt}>{statusLabel(opt)}</option>
                            {/each}
                          </select>
                        </div>

                        <button
                          type="button"
                          class="inline-flex items-center gap-2 rounded-lg border border-border bg-elevated px-4 py-2 text-xs font-semibold text-ink transition hover:border-accent hover:bg-panel disabled:cursor-wait disabled:opacity-70 cursor-pointer"
                          disabled={previewAddingBusy}
                          onclick={() => {
                            if (previewRelatedItem) void addRelatedToLibrary(previewRelatedItem, previewStatus)
                          }}
                        >
                          {#if previewAddingBusy}
                            <div class="h-4 w-4 animate-spin rounded-full border-2 border-accent border-t-transparent"></div>
                            <span>{i18n.t.detail.previewModal.addingToLibrary}</span>
                          {:else}
                            <Plus size={16} aria-hidden="true" />
                            <span>{i18n.t.detail.previewModal.addToLibrary}</span>
                          {/if}
                        </button>
                      </div>
                    </div>
                  </div>

                  <div class="mt-5 border-t border-border pt-4">
                    <h4 class="text-xs font-semibold uppercase tracking-wider text-muted">{i18n.t.detail.previewModal.description}</h4>
                    {#if previewRelatedItem.description}
                      <p class="mt-1.5 whitespace-pre-line text-xs leading-relaxed text-muted">{previewRelatedItem.description}</p>
                    {:else}
                      <p class="mt-1.5 text-xs italic text-muted/70">{i18n.t.detail.previewModal.noDescription}</p>
                    {/if}
                  </div>
                </div>
              </div>
            </div>
          {/if}
        {/if}

        <!-- TAB 4: RECOMMENDATIONS (Item 19) -->
        {#if activeSubTab === 'recommendations'}
          <section class="space-y-4">
            <div class="flex items-center justify-between">
              <h2 class="text-sm font-bold uppercase tracking-wider text-slate-300">{i18n.t.detail.tabRecommendations}</h2>
              <span class="text-xs text-muted">{i18n.t.detail.cachedForDays}</span>
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

{#if addVolumeDialogOpen}
  <div
    class="fixed inset-0 z-50 flex items-center justify-center bg-canvas/80 backdrop-blur-sm p-4"
    role="presentation"
    onclick={(e) => { if (e.target === e.currentTarget) addVolumeDialogOpen = false }}
  >
    <div class="w-full max-w-sm rounded-xl border border-white/10 bg-[#1a1d27] p-6 shadow-2xl space-y-4">
      <h3 class="text-sm font-bold text-white">Add Volume</h3>
      <div class="space-y-3">
        <div>
          <label class="block text-xs text-muted mb-1" for="add-vol-title">Title</label>
          <input
            id="add-vol-title"
            type="text"
            class="h-9 w-full rounded-md border border-white/10 bg-[#13151b] px-3 text-xs text-white outline-none focus:ring-1 focus:ring-[#5844e0]"
            bind:value={addVolumeTitle}
            onkeydown={(e) => { if (e.key === 'Enter') void confirmAddVolume() }}
          />
        </div>
        <div>
          <label class="block text-xs text-muted mb-1" for="add-vol-chapters">Chapters</label>
          <input
            id="add-vol-chapters"
            type="number"
            min="0"
            class="h-9 w-full rounded-md border border-white/10 bg-[#13151b] px-3 text-xs text-white outline-none focus:ring-1 focus:ring-[#5844e0]"
            bind:value={addVolumeChapters}
          />
        </div>
      </div>
      <div class="flex justify-end gap-2 pt-1">
        <button
          type="button"
          class="inline-flex h-8 items-center rounded-md border border-white/10 px-3 text-xs font-medium text-muted hover:text-white transition"
          onclick={() => (addVolumeDialogOpen = false)}
        >
          Cancel
        </button>
        <button
          type="button"
          class="inline-flex h-8 items-center gap-1.5 rounded-md bg-[#5844e0] px-3 text-xs font-semibold text-white transition hover:bg-[#6854f0] disabled:opacity-50"
          disabled={Boolean(volumeBusy)}
          onclick={() => void confirmAddVolume()}
        >
          <Plus size={13} />
          Add
        </button>
      </div>
    </div>
  </div>
{/if}

{#if editVolumeDialogOpen}
  <div
    class="fixed inset-0 z-50 flex items-center justify-center bg-canvas/80 backdrop-blur-sm p-4"
    role="presentation"
    onclick={(e) => { if (e.target === e.currentTarget) editVolumeDialogOpen = false }}
  >
    <div class="w-full max-w-sm rounded-xl border border-white/10 bg-[#1a1d27] p-6 shadow-2xl space-y-4">
      <h3 class="text-sm font-bold text-white">Edit Volume</h3>
      <div class="space-y-3">
        <div>
          <label class="block text-xs text-muted mb-1" for="edit-vol-title">Title</label>
          <input
            id="edit-vol-title"
            type="text"
            class="h-9 w-full rounded-md border border-white/10 bg-[#13151b] px-3 text-xs text-white outline-none focus:ring-1 focus:ring-[#5844e0]"
            bind:value={editVolumeTitle}
            onkeydown={(e) => { if (e.key === 'Enter') void confirmEditVolume() }}
          />
        </div>
        <div class="grid grid-cols-2 gap-2">
          <div>
            <label class="block text-xs text-muted mb-1" for="edit-vol-current-page">Current Page</label>
            <input
              id="edit-vol-current-page"
              type="number"
              min="0"
              class="h-9 w-full rounded-md border border-white/10 bg-[#13151b] px-3 text-xs text-white outline-none focus:ring-1 focus:ring-[#5844e0]"
              bind:value={editVolumeCurrentPage}
            />
          </div>
          <div>
            <label class="block text-xs text-muted mb-1" for="edit-vol-pages">Total Pages</label>
            <input
              id="edit-vol-pages"
              type="number"
              min="1"
              class="h-9 w-full rounded-md border border-white/10 bg-[#13151b] px-3 text-xs text-white outline-none focus:ring-1 focus:ring-[#5844e0]"
              bind:value={editVolumePages}
            />
          </div>
        </div>
        <div>
          <label class="block text-xs text-muted mb-1" for="edit-vol-chapters">Total Chapters</label>
          <input
            id="edit-vol-chapters"
            type="number"
            min="0"
            class="h-9 w-full rounded-md border border-white/10 bg-[#13151b] px-3 text-xs text-white outline-none focus:ring-1 focus:ring-[#5844e0]"
            bind:value={editVolumeChapters}
          />
        </div>
      </div>
      <div class="flex justify-end gap-2 pt-1">
        <button
          type="button"
          class="inline-flex h-8 items-center rounded-md border border-white/10 px-3 text-xs font-medium text-muted hover:text-white transition"
          onclick={() => (editVolumeDialogOpen = false)}
        >
          Cancel
        </button>
        <button
          type="button"
          class="inline-flex h-8 items-center gap-1.5 rounded-md bg-[#5844e0] px-3 text-xs font-semibold text-white transition hover:bg-[#6854f0] disabled:opacity-50"
          disabled={Boolean(volumeBusy)}
          onclick={() => void confirmEditVolume()}
        >
          <Check size={13} />
          Save
        </button>
      </div>
    </div>
  </div>
{/if}
