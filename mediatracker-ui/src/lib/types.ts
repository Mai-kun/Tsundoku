export const MEDIA_STATUS = {
  planned: 0,
  inProgress: 1,
  completed: 2,
  onHold: 3,
  dropped: 4,
} as const

export type MediaStatus = (typeof MEDIA_STATUS)[keyof typeof MEDIA_STATUS]
export type StatusFilter = 'all' | MediaStatus
export type MediaType = 'game' | 'movie' | 'tvshow' | 'book' | 'manga'
export type SearchMediaType = MediaType | 'anime'
export type SearchScope = SearchMediaType | 'all'
export type AppView = 'home' | MediaType | 'anime' | 'stats' | 'lists' | 'calendar' | 'seasons' | 'detail'
export type SortBy = 'createdAt' | 'score' | 'title'
export type SortOrder = 'asc' | 'desc'

export interface MediaBase {
  id: string
  type: MediaType
  title: string
  status: MediaStatus
  score: number | null
  startedAt: string | null
  finishedAt: string | null
  notes: string | null
  coverUrl: string | null
  createdAt: string
  franchiseId: string | null
  franchiseOrder: number | null
  externalRating?: number | null
  externalRatingVotes?: number | null
}

export interface GameMedia extends MediaBase {
  type: 'game'
  platform: string
  hoursPlayed: number | null
}

export interface BookMedia extends MediaBase {
  type: 'book'
  author: string
  currentPage: number
  totalPages: number
}

export interface MangaMedia extends MediaBase {
  type: 'manga'
  currentChapter: number
  totalChapters: number | null
  currentVolume: number
}

export interface MovieMedia extends MediaBase {
  type: 'movie'
  durationMinutes: number
  director: string | null
  isAnime: boolean
  studio: string | null
  romajiTitle: string | null
}

export interface TvShowMedia extends MediaBase {
  type: 'tvshow'
  isAnime: boolean
  studio: string | null
  romajiTitle: string | null
  network: string | null
  totalEpisodesCount: number
  totalEpisodesWatched: number
  seasonsCount: number
}

export interface TvSeason {
  id: string
  seasonNumber: number
  title: string
  coverUrl: string | null
  currentEpisode: number
  totalEpisodes: number
  status: MediaStatus
  score: number | null
  notes: string | null
  airDate: string | null
  tvShowId: string
}

export interface TvShowDetail extends TvShowMedia {
  seasons: TvSeason[]
}

export type MediaItem = GameMedia | BookMedia | MangaMedia | MovieMedia | TvShowMedia
export type MediaDetail = Exclude<MediaItem, TvShowMedia> | TvShowDetail

export interface MediaStats {
  totalItems: number
  completedItems: number
  inProgressItems: number
  plannedItems: number
  totalHoursPlayed: number
  totalPagesRead: number
  totalChaptersRead: number
  totalEpisodesWatched: number
  completedGamesCount: number
  completedBooksCount: number
  completedMoviesCount: number
}

export interface ExternalMedia {
  externalId: string
  title: string
  originalTitle: string | null
  coverUrl: string | null
  description: string | null
  releaseYear: number | null
  type: SearchMediaType
  author: string | null
  studio: string | null
  totalCount: number | null
  platform: string | null
}

export interface MediaFilters {
  type?: MediaType
  status?: MediaStatus
  isAnime?: boolean
  search?: string
  sortBy?: SortBy
  sortOrder?: SortOrder
}

interface CreateMediaBase {
  title: string
  status: MediaStatus
  score?: number | null
  coverUrl?: string | null
  notes?: string | null
  franchiseId?: string | null
  franchiseOrder?: number | null
}

export interface CreateGamePayload extends CreateMediaBase {
  type: 'game'
  platform: string
  hoursPlayed?: number | null
}

export interface CreateBookPayload extends CreateMediaBase {
  type: 'book'
  author: string
  totalPages?: number | null
}

export interface CreateMangaPayload extends CreateMediaBase {
  type: 'manga'
  totalChapters?: number | null
  currentVolume?: number | null
}

export interface CreateMoviePayload extends CreateMediaBase {
  type: 'movie'
  durationMinutes?: number | null
  director?: string | null
  isAnime?: boolean | null
  studio?: string | null
}

export interface CreateSeasonPayload {
  seasonNumber: number
  title: string
  coverUrl?: string | null
  totalEpisodes: number
  status?: MediaStatus
  score?: number | null
  notes?: string | null
  airDate?: string | null
}

export interface CreateTvShowPayload extends CreateMediaBase {
  type: 'tvshow'
  isAnime?: boolean | null
  studio?: string | null
  network?: string | null
  seasons?: CreateSeasonPayload[]
}

export type CreateMediaPayload =
  | CreateGamePayload
  | CreateBookPayload
  | CreateMangaPayload
  | CreateMoviePayload
  | CreateTvShowPayload

export interface UpdateMediaPayload {
  title?: string
  score?: number | null
  status?: MediaStatus
  notes?: string | null
  coverUrl?: string | null
  startedAt?: string | null
  finishedAt?: string | null
}

export function clampProgress(current: number, total: number | null | undefined): number {
  const safeCurrent = Math.max(current, 0)
  return total !== null && total !== undefined && total > 0 ? Math.min(safeCurrent, total) : safeCurrent
}

export function isTvShowDetail(item: MediaDetail): item is TvShowDetail {
  return item.type === 'tvshow' && 'seasons' in item
}
