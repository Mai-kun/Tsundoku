import type { MediaStatus } from "./enums";
import type { ExternalMedia, MediaItem } from "./models";

/**
 * Marker of a duplicate conflict (`PendingMatchesJson` object shape on the server): the row was
 * parked in review because the title being added matches one already in the library, and the
 * verdict — merge the sources or keep both — is the user's to make.
 */
export interface DuplicateConflictDto {
  conflictType: string;
  existingMediaId: string;
  existingTitle: string;
  incomingSource?: string | null;
  incomingExternalId?: string | null;
  incomingTitle?: string | null;
}

/**
 * One row of the "review ambiguous matches" screen (`GET /api/media/pending-matches`): the library
 * title the user imported plus the candidates the scorer could not decide between. Mirrors
 * `PendingMatchReviewDto` on the server.
 */
export interface PendingMatchItemDto {
  id: string;
  title: string;
  romajiTitle?: string | null;
  originalTitle?: string | null;
  altTitles?: string[] | null;
  type: string;
  isAnime?: boolean;
  releaseYear?: number | null;
  author?: string | null;
  currentProgress?: number | null;
  totalCount?: number | null;
  countryOfOrigin?: string | null;
  mangaFormat?: string | null;
  candidates: ExternalMedia[];
  /** Set when the row is a duplicate-conflict verdict instead of a candidate list. */
  duplicate?: DuplicateConflictDto | null;
}

export interface CustomListSummary {
  id: string;
  name: string;
  description: string | null;
  icon: string | null;
  color: string | null;
  itemsCount: number;
  updatedAt: string;
  previewCovers: (string | null)[];
  isSmart: boolean;
  smartQueryJson: string | null;
}

export interface CustomListDetail extends Omit<CustomListSummary, "itemsCount" | "previewCovers"> {
  createdAt: string;
  items: MediaItem[];
  isSmart: boolean;
  smartQueryJson: string | null;
}

export interface CreateListPayload {
  name: string;
  description?: string | null;
  icon?: string | null;
  color?: string | null;
  smartQueryJson?: string | null;
}

export type UpdateListPayload = CreateListPayload;

export interface SmartListQuery {
  categories?: string[] | null;
  statuses?: number[] | null;
  minScore?: number | null;
  maxScore?: number | null;
  onlyUnrated?: boolean | null;
  minExternalRating?: number | null;
  genres?: string[] | null;
  releaseYearFrom?: number | null;
  releaseYearTo?: number | null;
  maxDurationMinutes?: number | null;
  maxEpisodes?: number | null;
  maxPages?: number | null;
  maxChapters?: number | null;
  creatorContains?: string | null;
  /** Release status of the work itself: "FINISHED" | "RELEASING" | "NOT_YET_RELEASED". */
  releaseStatus?: string | null;
  sortBy?: string | null;
  sortOrder?: string | null;
  limit?: number | null;
}

export interface ImportResultDto {
  totalFound: number;
  importedCount: number;
  skippedDuplicates: number;
  targetListId: string | null;
  targetListName: string | null;
  skippedTitles?: string[];
  dumpUrl?: string | null;
  dumpFileName?: string | null;
}

export interface SteamImportPayload {
  steamId?: string;
  profileUrl?: string;
  steamApiKey?: string;
  skipDuplicates: boolean;
  targetListId?: string;
  newListName?: string;
  /** Drop games under this many played minutes (random launches, refund-bait). */
  minPlaytimeMinutes?: number;
  /** Pull the player's unlocked achievements per game (needs the Steam Web API key). */
  syncAchievements?: boolean;
}

export interface AniListProfilePayload {
  username: string;
  createList?: boolean;
  targetListId?: string;
  newListName?: string;
  skipDuplicates?: boolean;
}

export interface MangaLibProfilePayload {
  profileUrlOrId: string;
  siteIds?: number[];
  bearerToken?: string;
  /** Standard SocialLib folder ids (1..6) to import; omitted means all. */
  statusIds?: number[];
  /** Include the user's custom folder ids returned by bookmarks/folder/{userId}. */
  includeCustomFolders?: boolean;
  skipDuplicates?: boolean;
  targetListId?: string;
  newListName?: string;
}

interface CreateMediaBase {
  title: string;
  status: MediaStatus;
  altTitles?: string[] | null;
  score?: number | null;
  coverUrl?: string | null;
  notes?: string | null;
  description?: string | null;
  trailerVideoId?: string | null;
  franchiseId?: string | null;
  franchiseName?: string | null;
  franchiseOrder?: number | null;
  externalId?: string | null;
  externalSource?: string | null;
  importSource?: string | null;
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
  format?: string | null;
  currentChapter?: number | null;
  totalChapters?: number | null;
  currentVolume?: number | null;
  totalVolumes?: number | null;
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
  altTitles?: string[];
  score?: number | null;
  clearScore?: boolean;
  detailedScoreJson?: string | null;
  clearDetailedScore?: boolean;
  status?: MediaStatus;
  notes?: string | null;
  quotesJson?: string | null;
  coverUrl?: string | null;
  startedAt?: string | null;
  finishedAt?: string | null;
  lastActivityAt?: string | null;
  franchiseId?: string | null;
  franchiseName?: string | null;
  franchiseOrder?: number | null;
  author?: string | null;
  format?: string | null;
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
  clearDropReason?: boolean;
  dropReason?: string | null;
  dropNotes?: string | null;
  watchedOn?: string | null;
  releaseYear?: number | null;
  genres?: string | null;
  tags?: string | null;
  unlockedAchievements?: string | null;
  /** Cached Related-tab payload plus the source it came from; written after a successful load. */
  relatedMediaJson?: string | null;
  relatedSource?: string | null;
  achievementsJson?: string | null;
  recommendationsJson?: string | null;
  /** Set once the user edits a field by hand; drives the refresh overwrite prompt. */
  isCustomEdited?: boolean;
}

export interface SourceInfo {
  id: string;
  name: string;
  description: string;
  mediaTypes: string[];
  requiresApiKey: boolean;
  /** True when the source works without a key but can still use one (Steam). */
  optionalApiKey: boolean;
  isConfigured: boolean;
  hasKey: boolean;
  maskedKey: string | null;
  isEnabled: boolean;
}

/**
 * Context the creator card passes into the search modal: the query is a studio/author name, the
 * type is the category it belongs to and byCreator asks the sources for that creator's works.
 */
export interface SearchModalContext {
  query: string;
  type?: string;
  source?: string | null;
  byCreator?: boolean;
}

export interface ConnectionTestResult {
  success: boolean;
  latencyMs: number;
  message: string;
}

export interface ApiTokenSummary {
  id: string;
  name: string;
  tokenPrefix: string;
  createdAt: string;
  lastUsedAt: string | null;
  expiresAt: string | null;
}

export interface CreateApiTokenResponse {
  id: string;
  name: string;
  tokenPrefix: string;
  rawToken: string;
}

export type CalendarEventKind = "auto_refresh" | "air_date" | "release";

export interface CalendarItemDto {
  mediaId: string;
  title: string;
  type: string;
  coverUrl: string | null;
  currentProgress: number | null;
  totalCount: number | null;
  kind: CalendarEventKind;
  details: string | null;
  episodeNumber: number | null;
  seasonNumber: number | null;
  isAnime?: boolean;
}

export interface CalendarDayDto {
  date: string; // "YYYY-MM-DD"
  items: CalendarItemDto[];
}

export interface CalendarScheduleDto {
  from: string;
  to: string;
  days: CalendarDayDto[];
}

/** A release within the next 30 days the user is behind on; see /calendar/backlog-deadlines. */
export interface BacklogDeadlineDto {
  mediaId: string;
  title: string;
  type: string;
  coverUrl: string | null;
  /** "air_date" — behind on an ongoing; "release" — franchise sequel with an unfinished previous part. */
  kind: "air_date" | "release";
  /** "YYYY-MM-DD" */
  deadlineDate: string;
  daysLeft: number;
  episodeNumber: number | null;
  seasonNumber: number | null;
  /** Episodes/chapters left to catch up; null for franchise sequels. */
  behindCount: number | null;
  /** The previous franchise part to finish first; null for ongoing catch-ups. */
  blockerTitle: string | null;
  blockerProgress: number | null;
  blockerTotalCount: number | null;
}

/** One yearly/thematic goal with its live progress; see GET /api/goals?year=. */
export interface GoalDto {
  id: string;
  title: string;
  description: string | null;
  /** Emoji or icon key shown on the card. */
  icon: string;
  year: number;
  targetCount: number;
  currentCount: number;
  isCompleted: boolean;
  /** "all" | "book" | "movie" | "anime" | "manga" | "game" | "tvshow". */
  category: string | null;
  smartQueryJson: string | null;
  /** Up to 6 most recent completed titles counting toward the goal (cover strip). */
  completedItems: MediaItem[];
}

export interface CreateGoalPayload {
  title: string;
  description?: string | null;
  icon?: string | null;
  year: number;
  targetCount: number;
  category?: string | null;
  smartQueryJson?: string | null;
}

export interface ApiRateLimitStatus {
  provider: string;
  remaining: number;
  limit: number;
  resetSecondsRemaining: number;
  updatedAt: string;
}
