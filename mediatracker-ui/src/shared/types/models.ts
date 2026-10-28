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

export interface MediaQuote {
  id: string;
  text: string;
  pageOrContext?: string; // например: "стр. 142" или "Гл. 5"
  createdAt: string;
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
  /** 1 while the background enrichment of a search hit is still filling this row in; 3 when it found ambiguous matches and parked the row for review. */
  syncStatus?: SyncStatus;
  score: number | null;
  startedAt: string | null;
  finishedAt: string | null;
  lastActivityAt?: string | null;
  dropReason?: string | null;
  dropNotes?: string | null;
  coverUrl: string | null;
  createdAt: string;
  /** Feeds the cover cache-buster on the server side. */
  updatedAt?: string;
  franchiseId: string | null;
  franchiseName?: string | null;
  franchiseOrder: number | null;
  externalId?: string | null;
  externalSource?: string | null;
  importSource?: string | null;
  externalRating?: number | null;
  externalRatingVotes?: number | null;
  translationLanguage?: string | null;
  releaseDate?: string | null;
  releaseYear?: number | null;
  /** Where the user watched it: a known site or free text. */
  watchedOn?: string | null;
  endDate?: string | null;
  releaseStatus?: string | null;
  originalLanguage?: string | null;
  countryOfOrigin?: string | null;
  durationMinutes?: number | null;
  genres?: string[] | string | null;
  tags?: string[] | string | null;
  userPlatform?: string | null;
  /** Next scheduled background content check, so the UI can show when an ongoing is polled. */
  nextAutoRefreshAt?: string | null;
  /** Current adaptive interval between auto-refresh checks, in days. */
  autoRefreshIntervalDays?: number | null;
  /** When the last background check ran; null until the first one happened. */
  lastAutoRefreshedAt?: string | null;
}

export interface MediaCoverItem {
  id: string;
  thumbUrl: string;
  originalUrl: string;
  source?: string | null;
  addedAt: string;
}

/**
 * Payload the list endpoint deliberately omits: these are only read by the detail screen, so
 * carrying them for every item in the library was the bulk of the JSON list response.
 */
export interface MediaDetailFields {
  covers?: MediaCoverItem[];
  notes: string | null;
  detailedScoreJson?: string | null;
  quotesJson?: string | null;
  description?: string | null;
  trailerVideoId?: string | null;
  cast?: CastMember[];
  /** Native/romanized title; rendered under the main headline on the detail screen. */
  originalTitle?: string | null;
  staffJson?: string | null;
  /** Key crew, already parsed by the server (like recommendations). */
  staff?: StaffMember[];
  /** Director photo or studio logo, when a provider supplied one. */
  creatorImageUrl?: string | null;
  externalRatingsJson?: string | null;
  translatedSynopsis?: string | null;
  unlockedAchievements?: string | null;
  /** Cached related titles, so the Related tab is populated on a reload. */
  relatedMediaJson?: string | null;
  /** The provider relatedMediaJson was fetched from. */
  relatedSource?: string | null;
  /** Cached achievements / recommendations: written once, replayed on F5. */
  achievementsJson?: string | null;
  recommendationsJson?: string | null;
  recommendationsUpdatedAt?: string | null;
  /**
   * Ambiguous candidates the import enrichment could not decide between (NeedsReview). The user's
   * verdict lands through resolve-match / dismiss-match and clears this list.
   */
  pendingMatchesJson?: string | null;
  /** The same candidates, already parsed by the server. */
  pendingMatches?: ExternalMedia[] | null;
  /**
   * The cached recommendations, already parsed by the server. The tab renders this, so a reload shows
   * the list straight away instead of the panel having to issue a request of its own.
   */
  recommendations?: ExternalRecommendation[];
  /** The user hand-edited this row, so a refresh has to ask instead of overwriting silently. */
  isCustomEdited?: boolean;
  /** Auto-refresh cadence the calendar and the detail status block render. */
  nextAutoRefreshAt?: string | null;
  autoRefreshIntervalDays?: number | null;
  lastAutoRefreshedAt?: string | null;
}

export interface GameMedia extends MediaBase {
  type: "game";
  platform: string;
  hoursPlayed: number | null;
  /** Developer reported by RAWG/Steam; drives the overview's creator card. */
  studio?: string | null;
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
  volumes?: MangaVolume[];
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
  durationMinutes?: number | null;
  episodeDurationMinutes?: number | null;
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
export type MediaItem = GameMedia | BookMedia | MangaMedia | MovieMedia | TvShowMedia;

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

export type CreatorRole = "director" | "author" | "studio";

export interface CreatorSummaryDto {
  name: string;
  role: CreatorRole;
  totalCount: number;
  completedCount: number;
  averageScore: number | null;
  otherItems: MediaItem[];
}

export interface CastMember {
  name: string;
  character: string | null;
  photoUrl: string | null;
  /** MAIN / SUPPORTING, as the source spelled it. */
  characterRole?: string | null;
  characterImageUrl?: string | null;
  /** Japanese voice actor; absent for manga entries and legacy flat cast. */
  voiceActorName?: string | null;
  voiceActorImageUrl?: string | null;
}

export interface StaffMember {
  name: string;
  role: string | null;
  imageUrl: string | null;
}

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

export interface AdvancedStats {
  totalTitles: number;
  completedTitles: number;
  completionRatePercent: number;
  totalHours: number;
  totalDays: number;
  gameHours: number;
  movieHours: number;
  seriesHours: number;
  animeHours: number;
  bookHours: number;
  mangaHours: number;
  totalPagesRead: number;
  totalChaptersRead: number;
  totalEpisodesWatched: number;
  seriesEpisodesWatched?: number;
  animeEpisodesWatched?: number;
  averageScore: number;
  scoreDistribution: Record<number, number>;
  averageScoreByType: Record<string, number>;
  currentStreakDays: number;
  monthlyCompletions: Array<{ monthYear: string; count: number }>;
  topGenres: Array<{ genre: string; count: number; percentage: number }>;
  topGenresByType: Record<string, Array<{ genre: string; count: number; percentage: number }>>;
  dailyActivity: Record<string, number>;
}

export interface TastePersona {
  title: string;
  description: string;
  icon: string;
  traits: string[];
}

export interface SunkCost {
  lowScoreHours: number;
  percentageOfTotal: number;
  titlesCount: number;
  categoryBreakdown: Record<string, number>;
}

export interface DivergenceItem {
  id: string;
  title: string;
  type: string;
  coverUrl: string | null;
  userScore: number;
  worldRating: number;
  delta: number;
}

export interface CriticalDivergence {
  hiddenGem: DivergenceItem | null;
  disappointment: DivergenceItem | null;
}

export interface GenreCompletionStat {
  genre: string;
  total: number;
  completed: number;
  dropped: number;
  completionRate: number;
  dropRate: number;
}

export interface EraAffinityStat {
  era: string;
  count: number;
  percentage: number;
}

export interface RadarAxis {
  genre: string;
  volumeScore: number;
  averageScore: number;
}

export interface DropReasonStat {
  reason: string;
  count: number;
  percentage: number;
}

export interface DropAnalytics {
  totalDropped: number;
  averageDropProgressPercent: number;
  earlyDropCount: number;
  midDropCount: number;
  lateDropCount: number;
  topReasons: DropReasonStat[];
}

export interface TasteProfile {
  persona: TastePersona;
  sunkCost: SunkCost;
  divergence: CriticalDivergence;
  genreParadox: GenreCompletionStat[];
  eraAffinity: EraAffinityStat[];
  genreRadar: RadarAxis[];
  dropAnalytics?: DropAnalytics;
}

export interface ExternalMedia {
  externalId: string;
  externalSource?: string | null;
  title: string;
  originalTitle: string | null;
  romajiTitle?: string | null;
  coverUrl: string | null;
  description: string | null;
  trailerVideoId?: string | null;
  releaseYear: number | null;
  releaseDate?: string | null;
  endDate?: string | null;
  releaseStatus?: string | null;
  /** Provider's own format label (MANGA, NOVEL, TV, MOVIE...). */
  format?: string | null;
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

export function isTvShowDetail(item: MediaItem | MediaDetail): item is TvShowDetail {
  return item.type === "tvshow" && "seasons" in item;
}

export function isMangaDetail(item: MediaItem | MediaDetail): item is MangaDetail {
  return item.type === "manga";
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

/** One recommended title, normalised server-side across AniList and TMDb. */
export interface ExternalRecommendation {
  id: string;
  title: string;
  coverUrl: string | null;
  rating: number | null;
  source: string;
}

/**
 * A related title plus the relationship that produced it. Every source answers the relations endpoint
 * in this one shape, so the Related tab maps a single type instead of branching per provider.
 */
export interface ExternalRelation {
  relationType: string;
  media: ExternalMedia;
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

export interface StorageSettings {
  mode: "default" | "portable" | "custom";
  defaultDirectory: string;
  portableDirectory: string;
  customPath: string;
  isFirstRunSetupRequired: boolean;
}

export interface StorageRequest {
  mode: "default" | "portable" | "custom";
  customPath: string;
  migrateExistingData: boolean;
}
