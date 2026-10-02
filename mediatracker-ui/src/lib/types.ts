export const MEDIA_STATUS = {
  planned: 0,
  inProgress: 1,
  completed: 2,
  onHold: 3,
  dropped: 4,
} as const;

export type MediaStatus = (typeof MEDIA_STATUS)[keyof typeof MEDIA_STATUS];
export type StatusFilter = "all" | MediaStatus;
export type MediaType = "game" | "movie" | "tvshow" | "book" | "manga";
export type SearchMediaType = MediaType | "anime";
export type SearchScope = SearchMediaType | "all";
export type AppView =
  | "home"
  | MediaType
  | "anime"
  | "stats"
  | "lists"
  | "history"
  | "calendar"
  | "seasons"
  | "detail";
export type SortBy = "createdAt" | "score" | "title";
export type SortOrder = "asc" | "desc";

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

export interface MediaBase {
  id: string;
  type: MediaType;
  title: string;
  status: MediaStatus;
  score: number | null;
  startedAt: string | null;
  finishedAt: string | null;
  notes: string | null;
  coverUrl: string | null;
  createdAt: string;
  franchiseId: string | null;
  franchiseName?: string | null;
  franchiseOrder: number | null;
  externalId?: string | null;
  externalSource?: string | null;
  externalRating?: number | null;
  externalRatingVotes?: number | null;
  externalRatingsJson?: string | null;
  translatedSynopsis?: string | null;
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
  unlockedAchievements?: string | null;
  userPlatform?: string | null;
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

export interface MangaDetail extends MangaMedia {
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

export interface TvShowDetail extends TvShowMedia {
  seasons: TvSeason[];
}

export type MediaItem =
  GameMedia | BookMedia | MangaMedia | MovieMedia | TvShowMedia;
export type MediaDetail =
  Exclude<MediaItem, TvShowMedia | MangaMedia> | TvShowDetail | MangaDetail;

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

interface CreateMediaBase {
  title: string;
  status: MediaStatus;
  score?: number | null;
  coverUrl?: string | null;
  notes?: string | null;
  franchiseId?: string | null;
  franchiseName?: string | null;
  franchiseOrder?: number | null;
  externalId?: string | null;
  externalSource?: string | null;
  externalRating?: number | null;
  externalRatingVotes?: number | null;
  externalRatingsJson?: string | null;
  releaseDate?: string | null;
  endDate?: string | null;
  releaseStatus?: string | null;
  genres?: string[] | string | null;
  tags?: string[] | string | null;
  unlockedAchievements?: string | null;
  userPlatform?: string | null;
}

export interface CreateGamePayload extends CreateMediaBase {
  type: "game";
  platform: string;
  hoursPlayed?: number | null;
}

export interface CreateBookPayload extends CreateMediaBase {
  type: "book";
  author: string;
  totalPages?: number | null;
}

export interface CreateVolumePayload {
  volumeNumber: number;
  title: string;
  coverUrl?: string | null;
  totalPages?: number;
  currentPage?: number;
  totalChapters?: number;
  currentChapter?: number;
  status?: MediaStatus;
  score?: number | null;
  notes?: string | null;
  releaseDate?: string | null;
}

export interface UpdateVolumePayload {
  title?: string | null;
  coverUrl?: string | null;
  totalPages?: number | null;
  currentPage?: number | null;
  totalChapters?: number | null;
  currentChapter?: number | null;
  status?: MediaStatus | null;
  score?: number | null;
  notes?: string | null;
}

export interface CreateMangaPayload extends CreateMediaBase {
  type: "manga";
  author?: string | null;
  romajiTitle?: string | null;
  totalVolumes?: number | null;
  totalChapters?: number | null;
  currentVolume?: number | null;
  volumes?: CreateVolumePayload[];
}

export interface CreateMoviePayload extends CreateMediaBase {
  type: "movie";
  durationMinutes?: number | null;
  director?: string | null;
  isAnime?: boolean | null;
  studio?: string | null;
  romajiTitle?: string | null;
}

export interface CreateSeasonPayload {
  seasonNumber: number;
  title: string;
  coverUrl?: string | null;
  totalEpisodes: number;
  status?: MediaStatus;
  score?: number | null;
  notes?: string | null;
  airDate?: string | null;
  episodesData?: string | null;
}

export interface CreateTvShowPayload extends CreateMediaBase {
  type: "tvshow";
  isAnime?: boolean | null;
  studio?: string | null;
  romajiTitle?: string | null;
  network?: string | null;
  durationMinutes?: number | null;
  episodeDurationMinutes?: number | null;
  seasons?: CreateSeasonPayload[];
}

export type CreateMediaPayload =
  | CreateGamePayload
  | CreateBookPayload
  | CreateMangaPayload
  | CreateMoviePayload
  | CreateTvShowPayload;

export interface UpdateMediaPayload {
  title?: string;
  score?: number | null;
  status?: MediaStatus;
  notes?: string | null;
  coverUrl?: string | null;
  startedAt?: string | null;
  finishedAt?: string | null;
  franchiseId?: string | null;
  franchiseName?: string | null;
  franchiseOrder?: number | null;
  author?: string | null;
  romajiTitle?: string | null;
  totalVolumes?: number | null;
  currentVolume?: number | null;
  totalChapters?: number | null;
  currentChapter?: number | null;
  totalPages?: number | null;
  currentPage?: number | null;
  translatedSynopsis?: string | null;
  translationLanguage?: string | null;
  platform?: string | null;
  userPlatform?: string | null;
  /** Explicit null means "not supplied"; these flags are what actually clear the value. */
  clearUserPlatform?: boolean;
  clearWatchedOn?: boolean;
  watchedOn?: string | null;
  releaseYear?: number | null;
  genres?: string | null;
  tags?: string | null;
  unlockedAchievements?: string | null;
}

export interface SourceInfo {
  id: string;
  name: string;
  description: string;
  mediaTypes: string[];
  requiresApiKey: boolean;
  isConfigured: boolean;
  hasKey: boolean;
  maskedKey: string | null;
  isEnabled: boolean;
}

export interface ConnectionTestResult {
  success: boolean;
  latencyMs: number;
  message: string;
}

export function clampProgress(
  current: number,
  total: number | null | undefined,
): number {
  const safeCurrent = Math.max(current, 0);
  return total !== null && total !== undefined && total > 0
    ? Math.min(safeCurrent, total)
    : safeCurrent;
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
export type HistoryEventType =
  | "Added"
  | "StatusChanged"
  | "ScoreChanged"
  | "ProgressChanged"
  | "Deleted"
  | "AchievementUnlocked";

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
