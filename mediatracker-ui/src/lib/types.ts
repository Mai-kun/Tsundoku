/**
 * Shared types for the MediaTracker API.
 *
 * The shapes mirror the ASP.NET Core minimal API contracts: property names are
 * camelCase and enums (`MediaStatus`) are serialized as their numeric values.
 */

/** Numeric representation of `MediaTracker.Server.Models.MediaStatus`. */
export type MediaStatus = 0 | 1 | 2 | 3 | 4

/** Library status filter: a concrete status or `all`. */
export type StatusFilter = 'all' | MediaStatus

/** Media kinds the UI knows about. The API returns the discriminator in lowercase. */
export type MediaType = 'game' | 'movie' | 'tvshow' | 'book' | 'manga' | 'media'

/** A single season of a TV show (`TvSeason`). */
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

/**
 * A media library item. The API returns the shared `MediaItem` columns plus the
 * columns of the concrete subtype, so subtype fields are optional and are
 * detected at runtime.
 */
export interface MediaItem {
  id: string
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
  /** Optional lowercase discriminator, when the API provides one. */
  type?: string
  /** `VideoGame` */
  platform?: string
  hoursPlayed?: number | null
  /** `Book` */
  author?: string
  currentPage?: number
  totalPages?: number
  /** `Manga` */
  currentChapter?: number
  totalChapters?: number | null
  currentVolume?: number
  /** `Movie` */
  durationMinutes?: number
  director?: string | null
  isAnime?: boolean
  studio?: string | null
  romajiTitle?: string | null
  /** `TvShow` */
  network?: string | null
  seasons?: TvSeason[]
}

/** Aggregated library statistics (`MediaStatsDto`). */
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

/** A search result from an external metadata provider (`ExternalMediaDto`). */
export interface ExternalMedia {
  externalId: string
  title: string
  originalTitle: string | null
  coverUrl: string | null
  description: string | null
  releaseYear: number | null
  type: string
  author: string | null
  studio: string | null
  totalCount: number | null
  platform: string | null
}

/** Query parameters accepted by `GET /api/media`. */
export interface MediaFilters {
  type?: string
  status?: string | number
  isAnime?: boolean
  search?: string
  sortBy?: string
  sortOrder?: string
}

/** Body of `POST /api/media` (`CreateMediaRequest`). */
export interface CreateMediaPayload {
  type: string
  title: string
  status: number
  score?: number | null
  coverUrl?: string | null
  notes?: string | null
  franchiseId?: string | null
  franchiseOrder?: number | null
  platform?: string | null
  hoursPlayed?: number | null
  author?: string | null
  totalPages?: number | null
  totalChapters?: number | null
  currentVolume?: number | null
  durationMinutes?: number | null
  director?: string | null
  isAnime?: boolean | null
  studio?: string | null
  network?: string | null
  seasons?: unknown[]
}