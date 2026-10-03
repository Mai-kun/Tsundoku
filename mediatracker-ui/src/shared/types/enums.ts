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

