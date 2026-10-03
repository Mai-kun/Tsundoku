import type {
  HistoryEventType,
  MediaStatus,
  MediaType,
  SearchMediaType,
  SortBy,
  SortOrder,
  SyncStatus,
} from "./enums";

export interface ExternalRating {
  source: string;
  rating: number;
  score?: number;
  votes?: number | null;
}

export interface ExternalEpisode {
  number: number;
  title: string;
  airDate?: string | null;
}

/**
 * The card/list shape. The library screen fetches every item in one request, so free-text fields
 * that only the detail screen renders live in MediaDetailFields instead of here.
 */
export interface MediaBase {
  id: string;
  type: MediaType;
  title: string;
  status: MediaStatus;
  /** 1 while the background enrichment of a search hit is still filling this row in. */
  syncStatus?: SyncStatus;
  score: number | null;
  startedAt: string | null;
  finishedAt: string | null;
  coverUrl: string | null;
  createdAt: string;
  /** Feeds the cover cache-buster on the server side. */
  updatedAt?: string;
  franchiseId: string | null;
  franchiseName?: string | null;
  franchiseOrder: number | null;
  externalId?: string | null;
  externalSource?: string | null;
  externalRating?: number | null;
  externalRatingVotes?: number | null;
  translationLanguage?: string | null;
  releaseDate?: string | null;
  releaseYear?: number | null;
  /** Where the user watched it: a known site or free text. */
  watchedOn?: string | null;
  endDate?: string | null;
  releaseStatus?: string | null;
  durationMinutes?: number | null;
  genres?: string[] | string | null;
  tags?: string[] | string | null;
  userPlatform?: string | null;
}

/**
 * Payload the list endpoint deliberately omits: these are only read by the detail screen, so
 * carrying them for every item in the library was the bulk of the JSON list response.
 */
export interface MediaDetailFields {
  notes: string | null;
  externalRatingsJson?: string | null;
  translatedSynopsis?: string | null;
  unlockedAchievements?: string | null;
  /** Cached related titles, so the Related tab is populated on a reload. */
  relatedMediaJson?: string | null;
  /** The provider relatedMediaJson was fetched from. */
  relatedSource?: string | null;
}

export interface GameMedia extends MediaBase {
  type: "game";
  platform: string;
  hoursPlayed: number | null;
}

export interface BookMedia extends MediaBase {
  type: "book";
  author: string;
  currentPage: number;
  totalPages: number;
}

export interface MangaMedia extends MediaBase {
  type: "manga";
  currentChapter: number;
  totalChapters: number | null;
  currentVolume: number;
  totalVolumes?: number | null;
  author?: string | null;
  romajiTitle?: string | null;
  /** manga / manhwa / manhua / oel, derived from the external source. */
  mangaFormat?: string | null;
  totalPages?: number | null;
}

export interface MangaVolume {
  id: string;
  volumeNumber: number;
  title: string;
  coverUrl: string | null;
  currentPage: number;
  totalPages: number;
  currentChapter: number;
  totalChapters: number;
  status: MediaStatus;
  score: number | null;
  notes: string | null;
  releaseDate: string | null;
  mangaId: string;
}

export interface MangaDetail extends MangaMedia, MediaDetailFields {
  volumes: MangaVolume[];
}

export interface MovieMedia extends MediaBase {
  type: "movie";
  durationMinutes: number;
  director: string | null;
  isAnime: boolean;
  studio: string | null;
  romajiTitle: string | null;
}

export interface TvShowMedia extends MediaBase {
  type: "tvshow";
  isAnime: boolean;
  studio: string | null;
  romajiTitle: string | null;
  network: string | null;
  totalEpisodesCount: number;
  totalEpisodesWatched: number;
  seasonsCount: number;
}

export interface TvSeason {
  id: string;
  seasonNumber: number;
  title: string;
  coverUrl: string | null;
  currentEpisode: number;
  totalEpisodes: number;
  status: MediaStatus;
  score: number | null;
  notes: string | null;
  airDate: string | null;
  episodesData?: string | null;
  tvShowId: string;
}

export interface TvShowDetail extends TvShowMedia, MediaDetailFields {
  seasons: TvSeason[];
}

/** What GET /api/media returns: the light card shape. */
export type MediaItem =
  GameMedia | BookMedia | MangaMedia | MovieMedia | TvShowMedia;

/**
 * What GET /api/media/{id} returns. Spelling out the four variants (instead of deriving them from
 * MediaItem with Exclude) keeps the detail-only fields visible on the type, which is what the detail
 * screen reads.
 */
export type MediaDetail =
  | (GameMedia & MediaDetailFields)
  | (BookMedia & MediaDetailFields)
  | MovieDetail
  | TvShowDetail
  | MangaDetail;

/** A movie/book/game opened on the detail screen carries the detail-only fields too. */
export type MovieDetail = MovieMedia & MediaDetailFields;

export interface MediaStats {
  totalItems: number;
  completedItems: number;
  inProgressItems: number;
  plannedItems: number;
  totalHoursPlayed: number;
  totalPagesRead: number;
  totalChaptersRead: number;
  totalEpisodesWatched: number;
  completedGamesCount: number;
  completedBooksCount: number;
  completedMoviesCount: number;
}

export interface ExternalMedia {
  externalId: string;
  externalSource?: string | null;
  title: string;
  originalTitle: string | null;
  romajiTitle?: string | null;
  coverUrl: string | null;
  description: string | null;
  releaseYear: number | null;
  releaseDate?: string | null;
  endDate?: string | null;
  releaseStatus?: string | null;
  runtimeMinutes?: number | null;
  type: SearchMediaType;
  author: string | null;
  studio: string | null;
  totalCount: number | null;
  chapters?: number | null;
  volumes?: number | null;
  /** One of manga/manhwa/manhua/oel; null when no source could tell. */
  mangaFormat?: string | null;
  platform: string | null;
  rating?: number | null;
  ratingVotes?: number | null;
  ratings?: ExternalRating[] | null;
  episodes?: ExternalEpisode[] | null;
  genres?: string[] | string | null;
  tags?: string[] | string | null;
}

export interface MediaFilters {
  type?: MediaType;
  status?: MediaStatus;
  isAnime?: boolean;
  search?: string;
  sortBy?: SortBy;
  sortOrder?: SortOrder;
}

export function isTvShowDetail(
  item: MediaItem | MediaDetail,
): item is TvShowDetail {
  return item.type === "tvshow" && "seasons" in item;
}

export function isMangaDetail(
  item: MediaItem | MediaDetail,
): item is MangaDetail {
  return item.type === "manga" && "volumes" in item;
}

export interface GameAchievementItem {
  name: string;
  description?: string | null;
  iconUrl?: string | null;
}

export interface GameAchievementsResponse {
  totalCount: number;
  achievements: GameAchievementItem[];
}

export interface GameRelatedItem {
  id: string;
  title: string;
  coverUrl: string | null;
  releaseDate: string | null;
  score: number | null;
}

/** Mirrors MediaEventType on the server. */
export interface HistoryEvent {
  id: string;
  mediaId: string;
  /** Serialised by name ("StatusChanged"), matching the HistoryEventType union. */
    type: HistoryEventType;
  oldValue: string | null;
  newValue: string | null;
  createdAt: string;
  /** Null once the media is deleted. */
  title: string | null;
}
