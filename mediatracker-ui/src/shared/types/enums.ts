export const SYNC_STATUS = {
  ready: 0,
  syncing: 1,
  failed: 2,
} as const;

export type SyncStatus = (typeof SYNC_STATUS)[keyof typeof SYNC_STATUS];

/** Mirrors JobStatus on the server, which serialises the enum by name. */
export type JobStatus = "Queued" | "Running" | "Completed" | "Failed" | "Cancelled";

export interface JobProgress {
  jobId: string;
  mediaId: string | null;
  title: string;
  progressPercent: number;
  currentStep: string;
  status: JobStatus;
  startedAt: string;
  errorMessage: string | null;
}

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

export type HistoryEventType =
  | "Added"
  | "StatusChanged"
  | "ScoreChanged"
  | "ProgressChanged"
  | "Deleted"
  | "AchievementUnlocked";

