import type { MediaStatus } from "./enums";

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
  /** Cached Related-tab payload plus the source it came from; written after a successful load. */
  relatedMediaJson?: string | null;
  relatedSource?: string | null;
  achievementsJson?: string | null;
  recommendationsJson?: string | null;
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

