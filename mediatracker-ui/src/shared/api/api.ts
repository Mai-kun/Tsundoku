import { i18n } from "$shared/i18n/index.svelte";
import type {
  ApiTokenSummary,
  CreateApiTokenResponse,
  ConnectionTestResult,
  CreateMediaPayload,
  ExternalMedia,
  HistoryEvent,
  MediaDetail,
  MediaFilters,
  MediaItem,
  AdvancedStats,
  TasteProfile,
  MediaStatus,
  SearchScope,
  SourceInfo,
  GameAchievementsResponse,
  GameRelatedItem,
  ExternalRelation,
  UpdateMediaPayload,
  CustomListSummary,
  CustomListDetail,
  CreateListPayload,
  UpdateListPayload,
  ImportResultDto,
  SteamImportPayload,
  AniListProfilePayload,
  MangaLibProfilePayload,
  CreatorRole,
  CreatorSummaryDto,
  CalendarScheduleDto,
  BacklogDeadlineDto,
  PendingMatchItemDto,
  GoalDto,
  CreateGoalPayload,
  MediaAttachment,
  MediaGalleryItem,
  StorageSettings,
  StorageRequest,
  OfflineDatabasesSummaryDto,
  ApiRateLimitStatus,
} from "$shared/types";

const mediaEndpoint = "/api/media";
const externalEndpoint = "/api/external";

type ValidationErrors = Record<string, string[]>;

interface ProblemDetails {
  detail?: string;
  title?: string;
  errors?: ValidationErrors;
}

export class ApiError extends Error {
  readonly status: number;
  readonly detail: string;
  readonly validationErrors: ValidationErrors;

  constructor(status: number, detail = "", validationErrors: ValidationErrors = {}) {
    super(detail || "API request failed");
    this.name = "ApiError";
    this.status = status;
    this.detail = detail;
    this.validationErrors = validationErrors;
  }
}

export function errorMessage(error: unknown): string {
  if (error instanceof ApiError) {
    const validationMessage = Object.values(error.validationErrors).flat()[0];
    return validationMessage || error.detail || i18n.t.errors.requestFailed;
  }

  return i18n.t.errors.unexpected;
}

function isRecord(value: unknown): value is Record<string, unknown> {
  return typeof value === "object" && value !== null;
}

function readProblemDetails(value: unknown): ProblemDetails {
  if (!isRecord(value)) return {};

  const errors = isRecord(value.errors)
    ? Object.fromEntries(
        Object.entries(value.errors).flatMap(([key, messages]) =>
          Array.isArray(messages) && messages.every((message) => typeof message === "string")
            ? [[key, messages]]
            : [],
        ),
      )
    : {};

  return {
    detail: typeof value.detail === "string" ? value.detail : undefined,
    title: typeof value.title === "string" ? value.title : undefined,
    errors,
  };
}

async function throwApiError(response: Response): Promise<never> {
  const payload: unknown = await response.json().catch(() => null);
  const problem = readProblemDetails(payload);
  throw new ApiError(response.status, problem.detail || problem.title || "", problem.errors);
}

import { networkActivity } from "./networkActivity.svelte";
export { networkActivity };

export async function apiFetch(input: RequestInfo | URL, init?: RequestInit): Promise<Response> {
  networkActivity.begin();
  try {
    return await fetch(input, init);
  } finally {
    networkActivity.end();
  }
}

async function requestJson<T>(url: string, options: RequestInit = {}): Promise<T> {
  const response = await apiFetch(url, options);

  if (!response.ok) {
    return throwApiError(response);
  }

  return (await response.json()) as unknown as T;
}

async function requestVoid(url: string, options: RequestInit = {}): Promise<void> {
  const response = await apiFetch(url, options);

  if (!response.ok) {
    return throwApiError(response);
  }
}

function jsonOptions(method: "POST" | "PUT", payload: object): RequestInit {
  return {
    method,
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify(payload),
  };
}

export function getMedia(filters: MediaFilters = {}): Promise<MediaItem[]> {
  return getMediaWithCount(filters).then((page) => page.items);
}

export interface MediaListPage {
  items: MediaItem[];
  /** True DB-side total behind the server's limit window (X-Total-Count). */
  totalCount: number;
}

export async function getMediaWithCount(filters: MediaFilters = {}): Promise<MediaListPage> {
  const params = new URLSearchParams();
  const queryFilters = {
    sortBy: "createdAt" as const,
    sortOrder: "desc" as const,
    ...filters,
  };

  for (const [key, value] of Object.entries(queryFilters)) {
    if (value !== undefined && value !== null && value !== "") {
      params.set(key, String(value));
    }
  }

  const query = params.toString();
  const response = await apiFetch(`${mediaEndpoint}${query ? `?${query}` : ""}`);
  if (!response.ok) {
    return throwApiError(response);
  }

  const items = (await response.json()) as MediaItem[];
  const header = Number(response.headers.get("X-Total-Count"));
  return {
    items,
    totalCount: Number.isFinite(header) && header > 0 ? header : items.length,
  };
}

export function getMediaItem(id: string): Promise<MediaDetail> {
  return requestJson<MediaDetail>(`${mediaEndpoint}/${id}`);
}

export function getCreatorSummary(
  name: string,
  role: CreatorRole,
  excludeId?: string,
): Promise<CreatorSummaryDto | null> {
  const params = new URLSearchParams({ name, role });
  if (excludeId) params.set("excludeId", excludeId);
  return requestJson<CreatorSummaryDto | null>(
    `${mediaEndpoint}/creator-summary?${params.toString()}`,
  );
}

export function getAdvancedStats(
  scope: string = "completed",
  signal?: AbortSignal,
): Promise<AdvancedStats> {
  const query = scope ? `?scope=${encodeURIComponent(scope)}` : "";
  return requestJson<AdvancedStats>(`${mediaEndpoint}/stats/advanced${query}`, { signal });
}
export function getTasteProfile(
  scope: string = "completed",
  signal?: AbortSignal,
): Promise<TasteProfile> {
  const query = scope ? `?scope=${encodeURIComponent(scope)}` : "";
  return requestJson<TasteProfile>(`${mediaEndpoint}/stats/taste-profile${query}`, { signal });
}

export function searchExternal(
  type: SearchScope,
  query: string,
  signal?: AbortSignal,
  source?: string,
  byCreator?: boolean,
): Promise<ExternalMedia[]> {
  const params = new URLSearchParams({
    type,
    query: query.trim(),
  });
  if (source) params.set("source", source);
  if (byCreator) params.set("byCreator", "true");
  return requestJson<ExternalMedia[]>(`${externalEndpoint}/search?${params.toString()}`, {
    signal,
  });
}

export function getExternalDetails(
  type: string,
  id: string,
  title: string,
  source?: string,
  signal?: AbortSignal,
): Promise<ExternalMedia | null> {
  const params = new URLSearchParams({ type, id, title });
  if (source) params.set("source", source);
  return requestJson<ExternalMedia>(`${externalEndpoint}/details?${params}`, {
    signal,
  }).catch(() => null);
}

export function createMedia(payload: CreateMediaPayload): Promise<MediaDetail> {
  return requestJson<MediaDetail>(mediaEndpoint, jsonOptions("POST", payload));
}

export interface TitleDuplicateCandidate {
  id: string;
  title: string;
  type: string;
  isAnime: boolean;
  externalSource: string | null;
  externalId: string | null;
  releaseYear: number | null;
  coverUrl: string | null;
  matchReason: string;
}

/** Duplicate guard for the add flow: same title may already exist under another provider's name. */
export function findTitleDuplicates(params: {
  title: string;
  externalSource?: string | null;
  externalId?: string | null;
  romajiTitle?: string | null;
  originalTitle?: string | null;
  synonyms?: string[] | null;
  releaseYear?: number | null;
}): Promise<TitleDuplicateCandidate[]> {
  return requestJson<TitleDuplicateCandidate[]>(`${mediaEndpoint}/duplicates/check`, {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify({
      title: params.title,
      externalSource: params.externalSource ?? null,
      externalId: params.externalId ?? null,
      romajiTitle: params.romajiTitle ?? null,
      originalTitle: params.originalTitle ?? null,
      synonyms: params.synonyms ?? null,
      releaseYear: params.releaseYear ?? null,
    }),
  });
}

/**
 * Binds an external source onto an EXISTING entry — the "Дополнить" half of the duplicate
 * dialog. The backend binds and immediately fills missing fields from the new source.
 */
export function linkSourceToMedia(
  id: string,
  payload: { source: string; externalId: string; title?: string | null },
): Promise<void> {
  return requestJson<unknown>(`/api/media/${id}/linked-sources`, {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify({
      source: payload.source,
      externalId: payload.externalId,
      title: payload.title ?? null,
    }),
  }).then(() => undefined);
}

export function updateMedia(id: string, payload: UpdateMediaPayload): Promise<MediaDetail> {
  return requestJson<MediaDetail>(`${mediaEndpoint}/${id}`, jsonOptions("PUT", payload));
}

/**
 * "Дополнить": fills only the empty fields, from `source` when the user picked one in the dialog.
 * Never overwrites a value that is already there.
 */
export function enrichMedia(id: string, source?: string): Promise<MediaDetail> {
  return requestJson<MediaDetail>(`${mediaEndpoint}/${id}/enrich`, {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify({ source: source ?? null }),
  });
}

export function setProgress(id: string, currentProgress: number): Promise<void> {
  return requestVoid(`${mediaEndpoint}/${id}/progress`, jsonOptions("PUT", { currentProgress }));
}

export function setSeasonProgress(id: string, currentEpisode: number): Promise<void> {
  return requestVoid(`/api/seasons/${id}/progress`, jsonOptions("PUT", { currentEpisode }));
}

export function updateStatus(
  id: string,
  payload:
    MediaStatus | { status: MediaStatus; dropReason?: string | null; dropNotes?: string | null },
): Promise<void> {
  const body = typeof payload === "number" ? { status: payload } : payload;
  return requestVoid(`${mediaEndpoint}/${id}/status`, jsonOptions("PUT", body));
}

export function deleteMedia(id: string): Promise<void> {
  return requestVoid(`${mediaEndpoint}/${id}`, { method: "DELETE" });
}

export function addCoverByUrl(
  id: string,
  url: string,
  source?: string | null,
  setAsActive: boolean = false,
): Promise<MediaDetail> {
  return requestJson<MediaDetail>(
    `${mediaEndpoint}/${id}/covers`,
    jsonOptions("POST", { url, source: source ?? null, setAsActive }),
  );
}

export function addCoverByFile(
  id: string,
  file: File | Blob,
  source?: string | null,
  setAsActive: boolean = false,
): Promise<MediaDetail> {
  const formData = new FormData();
  formData.append("file", file);
  if (source) formData.append("source", source);
  if (setAsActive) formData.append("setAsActive", "true");
  return requestJson<MediaDetail>(`${mediaEndpoint}/${id}/covers`, {
    method: "POST",
    body: formData,
  });
}

export function selectCover(id: string, coverId: string): Promise<MediaDetail> {
  return requestJson<MediaDetail>(`${mediaEndpoint}/${id}/covers/${coverId}/select`, {
    method: "PUT",
  });
}

export function deleteCover(id: string, coverId: string): Promise<MediaDetail> {
  return requestJson<MediaDetail>(`${mediaEndpoint}/${id}/covers/${coverId}`, {
    method: "DELETE",
  });
}

export function fetchVolumeCovers(id: string): Promise<MediaDetail> {
  return requestJson<MediaDetail>(`${mediaEndpoint}/${id}/covers/fetch-volumes`, {
    method: "POST",
  });
}

/** Attaches a file (book, archive, save) to the title; returns the refreshed attachment list. */
export function attachMediaFile(id: string, file: File): Promise<MediaAttachment[]> {
  const formData = new FormData();
  formData.append("file", file);
  return requestJson<MediaAttachment[]>(`${mediaEndpoint}/${id}/files`, {
    method: "POST",
    body: formData,
  });
}

/** Removes one attachment from disk and from the index; returns the refreshed list. */
export function detachMediaFile(id: string, fileId: string): Promise<MediaAttachment[]> {
  return requestJson<MediaAttachment[]>(
    `${mediaEndpoint}/${id}/files/${encodeURIComponent(fileId)}`,
    {
      method: "DELETE",
    },
  );
}

/** Browser-native download of a stored attachment (Content-Disposition is set server-side). */
export function mediaFileDownloadUrl(id: string, fileId: string): string {
  return `${mediaEndpoint}/${id}/files/${encodeURIComponent(fileId)}/download`;
}

/** Browser renders the file itself (PDF, TXT, images): Content-Disposition: inline. */
export function mediaFileViewUrl(id: string, fileId: string): string {
  return `${mediaEndpoint}/${id}/files/${encodeURIComponent(fileId)}/view`;
}

/** Opens the stored file in the OS program associated with its type (xdg-open / shell). */
export function openMediaFile(id: string, fileId: string): Promise<void> {
  return requestVoid(`${mediaEndpoint}/${id}/files/${encodeURIComponent(fileId)}/open`, {
    method: "POST",
  });
}

/** Reveals a server-side path (relative to the data dir) in the platform file manager. */
export async function revealInExplorer(relativePath: string): Promise<void> {
  return requestVoid("/api/system/reveal-in-explorer", {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify({ path: relativePath }),
  });
}

/** Adds a screenshot to the title's gallery; accepts a File or a pasted Clipboard blob. */
export function uploadGalleryImage(
  id: string,
  image: Blob,
  title?: string,
): Promise<MediaGalleryItem> {
  const formData = new FormData();
  formData.append("image", image, title ?? "screenshot.png");
  if (title) formData.append("title", title);
  return requestJson<MediaGalleryItem>(`${mediaEndpoint}/${id}/gallery`, {
    method: "POST",
    body: formData,
  });
}

/** Removes one gallery screenshot (folder on disk + index entry). */
export function deleteGalleryImage(id: string, imgId: string): Promise<void> {
  return requestVoid(`${mediaEndpoint}/${id}/gallery/${encodeURIComponent(imgId)}`, {
    method: "DELETE",
  });
}

/** Makes a gallery screenshot the title's active cover; returns the updated card. */
export function setGalleryAsCover(id: string, imgId: string): Promise<MediaDetail> {
  return requestJson<MediaDetail>(
    `${mediaEndpoint}/${id}/gallery/${encodeURIComponent(imgId)}/set-as-cover`,
    { method: "POST" },
  );
}

export function importFile(formData: FormData): Promise<ImportResultDto> {
  return requestJson<ImportResultDto>(`${mediaEndpoint}/import/file`, {
    method: "POST",
    body: formData,
  });
}

export function importSteamProfile(payload: SteamImportPayload): Promise<ImportResultDto> {
  return requestJson<ImportResultDto>(
    `${mediaEndpoint}/import/steam`,
    jsonOptions("POST", payload),
  );
}

export function importAniListProfile(payload: AniListProfilePayload): Promise<ImportResultDto> {
  return requestJson<ImportResultDto>(
    `${mediaEndpoint}/import/anilist-profile`,
    jsonOptions("POST", payload),
  );
}

export function importMangaLibProfile(payload: MangaLibProfilePayload): Promise<ImportResultDto> {
  return requestJson<ImportResultDto>(
    `${mediaEndpoint}/import/mangalib-profile`,
    jsonOptions("POST", payload),
  );
}

export function getLists(): Promise<CustomListSummary[]> {
  return requestJson<CustomListSummary[]>("/api/lists");
}

export function getListDetail(id: string): Promise<CustomListDetail> {
  return requestJson<CustomListDetail>(`/api/lists/${id}`);
}

export function createList(payload: CreateListPayload): Promise<{ id: string }> {
  return requestJson<{ id: string }>("/api/lists", jsonOptions("POST", payload));
}

export function updateList(id: string, payload: UpdateListPayload): Promise<void> {
  return requestVoid(`/api/lists/${id}`, jsonOptions("PUT", payload));
}

export function deleteList(id: string): Promise<void> {
  return requestVoid(`/api/lists/${id}`, { method: "DELETE" });
}

export function addMediaToList(listId: string, mediaId: string): Promise<void> {
  return requestVoid(`/api/lists/${listId}/items`, jsonOptions("POST", { mediaId }));
}

export function removeMediaFromList(listId: string, mediaId: string): Promise<void> {
  return requestVoid(`/api/lists/${listId}/items/${mediaId}`, { method: "DELETE" });
}

export function getListsForMedia(mediaId: string): Promise<string[]> {
  return requestJson<string[]>(`/api/media/${mediaId}/lists`);
}

/**
 * Re-reads the provider. `fillMissing` turns the overwrite into a gap fill, which is what the
 * "keep my edits" branch of the refresh dialog sends.
 */
export function refreshMetadata(id: string, fillMissing = false): Promise<MediaDetail> {
  return requestJson<MediaDetail>(`${mediaEndpoint}/${id}/refresh`, {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify({ fillMissing }),
  });
}

/**
 * Re-points an item at another provider's entity. Unlike refresh, which re-reads the id the row
 * already stores, this takes a new id from a source the user picked explicitly.
 */
export function relinkMedia(
  id: string,
  payload: {
    externalId: string;
    source: string;
    type: string;
    title?: string;
  },
): Promise<MediaDetail> {
  return requestJson<MediaDetail>(`${mediaEndpoint}/${id}/relink`, {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify(payload),
  });
}

let sourcesCachePromise: Promise<SourceInfo[]> | null = null;

export function getSources(forceRefresh = false): Promise<SourceInfo[]> {
  if (!forceRefresh && sourcesCachePromise) return sourcesCachePromise;
  sourcesCachePromise = requestJson<SourceInfo[]>("/api/settings/sources").catch((err) => {
    sourcesCachePromise = null;
    throw err;
  });
  return sourcesCachePromise;
}

export function invalidateSourcesCache(): void {
  sourcesCachePromise = null;
}

export function toggleSourceEnabled(
  sourceId: string,
  enabled: boolean,
): Promise<{ success: boolean; isEnabled: boolean }> {
  invalidateSourcesCache();
  return requestJson(`/api/settings/sources/${sourceId}/toggle`, jsonOptions("PUT", { enabled }));
}

export function testSourceConnection(sourceId: string): Promise<ConnectionTestResult> {
  return requestJson<ConnectionTestResult>(`/api/settings/sources/${sourceId}/test`, {
    method: "POST",
  });
}

export function saveSourceKey(
  sourceId: string,
  apiKey: string,
): Promise<{ success: boolean; hasKey: boolean; maskedKey: string | null }> {
  invalidateSourcesCache();
  return requestJson(`/api/settings/sources/${sourceId}/key`, jsonOptions("PUT", { apiKey }));
}

export function getSourceKeyStatus(
  sourceId: string,
): Promise<{ success: boolean; hasKey: boolean; maskedKey: string | null }> {
  return requestJson(`/api/settings/sources/${sourceId}/key`);
}

export interface MangalibDetectResult {
  success: boolean;
  userId: number | null;
  username: string | null;
  /** Where the session was found (browser profile), for the confirmation toast. */
  source: string | null;
  message: string | null;
}

/**
 * Picks up the SocialLib session from the user's own browsers (Zen / Firefox /
 * the isolated Tsundoku Chromium profile). Returns null when no session exists
 * (HTTP 404) — the caller shows the "open login page" fallback.
 */
export async function detectMangalibBrowserSession(): Promise<MangalibDetectResult | null> {
  const response = await apiFetch("/api/settings/sources/mangalib/detect-token", {
    method: "POST",
  });
  if (response.status === 404) return null;
  if (!response.ok) {
    await throwApiError(response);
  }
  invalidateSourcesCache();
  return (await response.json()) as MangalibDetectResult;
}

/** Opens the MangaLib login page in the system browser. */
export function openMangalibLoginPage(): Promise<void> {
  return requestVoid("/api/settings/sources/mangalib/open-login", { method: "POST" });
}

/** Asks the Tsundoku server (tray + web) to shut down gracefully. */
export function shutdownApp(): Promise<void> {
  return requestVoid("/api/system/shutdown", { method: "POST" });
}

export function getCategoryOrder(): Promise<string[]> {
  return requestJson<string[]>("/api/settings/category-order");
}

export function saveCategoryOrder(order: string[]): Promise<string[]> {
  return requestJson<string[]>("/api/settings/category-order", {
    method: "PUT",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify(order),
  });
}

export function getSourcePriority(): Promise<Record<string, string[]>> {
  return requestJson<Record<string, string[]>>("/api/settings/source-priority");
}

export function saveSourcePriority(
  priority: Record<string, string[]>,
): Promise<Record<string, string[]>> {
  return requestJson<Record<string, string[]>>("/api/settings/source-priority", {
    method: "PUT",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify(priority),
  });
}

export interface ReadingSettings {
  bookPageMinutes: number;
  mangaChapterMinutes: number;
}

export type AppLaunchMode = "app_window" | "browser_tab";
export type AppCloseAction = "minimize_to_tray" | "exit_all";

export interface AppSettings {
  launchMode: AppLaunchMode;
  closeAction: AppCloseAction;
}

export function getAppSettings(): Promise<AppSettings> {
  return requestJson<AppSettings>("/api/settings/app");
}

export function saveAppSettings(settings: AppSettings): Promise<AppSettings> {
  return requestJson<AppSettings>("/api/settings/app", {
    method: "PUT",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify(settings),
  });
}

export function getReadingSettings(): Promise<ReadingSettings> {
  return requestJson<ReadingSettings>("/api/settings/reading");
}

export function saveReadingSettings(settings: ReadingSettings): Promise<ReadingSettings> {
  return requestJson<ReadingSettings>("/api/settings/reading", {
    method: "PUT",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify(settings),
  });
}

export function translateText(
  text: string,
  targetLanguage = "ru",
): Promise<{ translatedText: string }> {
  return requestJson<{ translatedText: string }>("/api/external/translate", {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify({ text, targetLanguage }),
  });
}

export function getGameAchievements(params: {
  steamAppId?: string | null;
  rawgId?: string | null;
  title?: string | null;
  externalSource?: string | null;
  externalId?: string | null;
}): Promise<GameAchievementsResponse> {
  const query = new URLSearchParams();
  if (params.steamAppId) query.set("steamAppId", params.steamAppId);
  if (params.rawgId) query.set("rawgId", params.rawgId);
  if (params.title) query.set("title", params.title);
  if (params.externalSource) query.set("externalSource", params.externalSource);
  if (params.externalId) query.set("externalId", params.externalId);
  return requestJson<GameAchievementsResponse>(
    `/api/external/games/achievements?${query.toString()}`,
  );
}

export function getGameRelated(params: {
  rawgId?: string | null;
  title?: string | null;
  externalSource?: string | null;
  externalId?: string | null;
}): Promise<GameRelatedItem[]> {
  const query = new URLSearchParams();
  if (params.rawgId) query.set("rawgId", params.rawgId);
  if (params.title) query.set("title", params.title);
  if (params.externalSource) query.set("externalSource", params.externalSource);
  if (params.externalId) query.set("externalId", params.externalId);
  return requestJson<GameRelatedItem[]>(`/api/external/games/related?${query.toString()}`);
}

/**
 * Related / recommended titles for one source. `kind` is "related" or "recommendations"; the
 * caller must name the source explicitly because these are only ever fetched on request.
 */
export function getExternalRelations(params: {
  type?: string | null;
  externalId?: string | null;
  title?: string | null;
  source: string;
  kind: "related" | "recommendations";
}): Promise<ExternalRelation[]> {
  const query = new URLSearchParams();
  if (params.type) query.set("type", params.type);
  if (params.externalId) query.set("externalId", params.externalId);
  if (params.title) query.set("title", params.title);
  query.set("source", params.source);
  query.set("kind", params.kind);
  return requestJson<ExternalRelation[]>(`/api/external/relations?${query.toString()}`);
}

export function getCalendar(
  from?: string,
  to?: string,
  signal?: AbortSignal,
): Promise<CalendarScheduleDto> {
  const params = new URLSearchParams();
  if (from) params.set("from", from);
  if (to) params.set("to", to);
  const query = params.toString();
  return requestJson<CalendarScheduleDto>(`${mediaEndpoint}/calendar${query ? `?${query}` : ""}`, {
    signal,
  });
}

export function triggerAutoRefresh(mediaId: string): Promise<MediaDetail> {
  return requestJson<MediaDetail>(`${mediaEndpoint}/${mediaId}/auto-refresh/trigger`, {
    method: "POST",
  });
}

/** RFC 5545 calendar feed (episodes + releases) for Apple Calendar / Google Calendar / Thunderbird. */
export async function exportCalendarIcs(): Promise<Blob> {
  const response = await apiFetch(`${mediaEndpoint}/calendar/ics`);
  if (!response.ok) {
    return throwApiError(response);
  }
  return response.blob();
}

/** Titles with a release in the next 30 days the user is behind on (ongoings + franchise sequels). */
export function getBacklogDeadlines(signal?: AbortSignal): Promise<BacklogDeadlineDto[]> {
  return requestJson<BacklogDeadlineDto[]>(`${mediaEndpoint}/calendar/backlog-deadlines`, {
    signal,
  });
}

/** Library rows the enrichment job parked in `NeedsReview`, each with its candidate matches. */
export function getPendingMatches(): Promise<PendingMatchItemDto[]> {
  return requestJson<PendingMatchItemDto[]>(`${mediaEndpoint}/pending-matches`);
}

/** Applies the candidate the user confirmed and returns the enriched row. */
export function resolvePendingMatch(
  id: string,
  payload: { externalId: string; source: string; type?: string; title?: string },
): Promise<MediaDetail> {
  return requestJson<MediaDetail>(
    `${mediaEndpoint}/${id}/resolve-match`,
    jsonOptions("POST", payload),
  );
}

/** Skips one review row: candidates are wiped, the row goes back to Ready. */
export function dismissPendingMatch(id: string): Promise<void> {
  return requestVoid(`${mediaEndpoint}/${id}/dismiss-match`, { method: "POST" });
}

/** Skips every review row at once. */
export function dismissAllPendingMatches(): Promise<void> {
  return requestVoid(`${mediaEndpoint}/dismiss-all-matches`, {
    method: "POST",
  });
}

/** Auto-picks the top candidate of every review row that scans strong enough; weak rows stay in review. */
export function resolveAllPendingMatchesByPriority(): Promise<{
  resolvedCount: number;
  skippedCount: number;
}> {
  return requestJson<{ resolvedCount: number; skippedCount: number }>(
    `${mediaEndpoint}/resolve-all-by-priority`,
    { method: "POST" },
  );
}

/**
 * Verdict "merge" on a duplicate-conflict review row: the duplicate's sources, ratings and missing
 * data join the existing title and the duplicate row is deleted, so the library keeps one card.
 */
export function mergeDuplicateSources(
  existingId: string,
  duplicateId: string,
): Promise<MediaDetail> {
  return requestJson<MediaDetail>(`${mediaEndpoint}/${existingId}/merge-duplicate/${duplicateId}`, {
    method: "POST",
  });
}

export function getHistoryEvents(params?: {
  mediaId?: string;
  date?: string;
}): Promise<HistoryEvent[]> {
  const query = new URLSearchParams();
  if (params?.mediaId) query.set("mediaId", params.mediaId);
  if (params?.date) query.set("date", params.date);
  const qs = query.toString();
  return requestJson<HistoryEvent[]>(`/api/history${qs ? `?${qs}` : ""}`);
}

export function clearAllHistory(): Promise<void> {
  return requestVoid("/api/history", { method: "DELETE" });
}

/** Removes one activity-log entry. `id` is the event id, as listed by getHistoryEvents. */
export function deleteHistoryEvent(id: string): Promise<void> {
  return requestVoid(`/api/history/${id}`, { method: "DELETE" });
}

export async function exportBackup(): Promise<Blob> {
  const response = await apiFetch("/api/settings/backup/export");
  if (!response.ok) {
    return throwApiError(response);
  }
  return response.blob();
}

/** Clean, import-compatible dump of the whole library (fields match the Custom Import parser). */
export async function exportLibraryJson(): Promise<Blob> {
  const response = await apiFetch("/api/settings/export/json");
  if (!response.ok) {
    return throwApiError(response);
  }
  return response.blob();
}

/** RFC 4180 CSV dump of the whole library, UTF-8 BOM included for Excel. */
export async function exportLibraryCsv(): Promise<Blob> {
  const response = await apiFetch("/api/settings/export/csv");
  if (!response.ok) {
    return throwApiError(response);
  }
  return response.blob();
}

export async function restoreBackup(file: File): Promise<void> {
  const formData = new FormData();
  formData.append("backupFile", file);

  const response = await apiFetch("/api/settings/backup/restore", {
    method: "POST",
    body: formData,
  });

  if (!response.ok) {
    return throwApiError(response);
  }
}

export function resetAllData(keepApiKeys: boolean = true): Promise<void> {
  return requestVoid("/api/settings/reset", jsonOptions("POST", { keepApiKeys }));
}

export function getApiTokens(): Promise<ApiTokenSummary[]> {
  return requestJson<ApiTokenSummary[]>("/api/settings/tokens");
}

export function createApiToken(
  name: string,
  expiresInDays?: number,
): Promise<CreateApiTokenResponse> {
  return requestJson<CreateApiTokenResponse>(
    "/api/settings/tokens",
    jsonOptions("POST", { name, expiresInDays }),
  );
}

export function revokeApiToken(id: string): Promise<void> {
  return requestVoid(`/api/settings/tokens/${id}`, { method: "DELETE" });
}

export interface UpdateCheckResult {
  currentVersion: string;
  latestVersion?: string;
  isUpdateAvailable: boolean;
  canSelfUpdate: boolean;
  releaseTitle?: string;
  releaseNotes?: string;
  publishedAt?: string;
  releaseUrl?: string;
  downloadUrl?: string;
  assetSizeBytes?: number;
}

export function checkAppUpdate(): Promise<UpdateCheckResult> {
  return requestJson<UpdateCheckResult>("/api/settings/update/check");
}

export function applyAppUpdate(): Promise<void> {
  return requestVoid("/api/settings/update/apply", { method: "POST" });
}

export function getStorageSettings(): Promise<StorageSettings> {
  return requestJson<StorageSettings>("/api/settings/storage");
}

export function saveStorageSettings(
  payload: StorageRequest,
): Promise<{ restartScheduled: boolean }> {
  return requestJson("/api/settings/storage", jsonOptions("POST", payload));
}

export function getGoals(year: number): Promise<GoalDto[]> {
  return requestJson<GoalDto[]>(`/api/goals?year=${year}`);
}

export function createGoal(payload: CreateGoalPayload): Promise<GoalDto> {
  return requestJson<GoalDto>("/api/goals", jsonOptions("POST", payload));
}

export function deleteGoal(id: string): Promise<void> {
  return requestVoid(`/api/goals/${id}`, { method: "DELETE" });
}

export function getRateLimits(): Promise<ApiRateLimitStatus[]> {
  return requestJson<ApiRateLimitStatus[]>("/api/system/rate-limits");
}

export function getOfflineDatabases(): Promise<OfflineDatabasesSummaryDto> {
  return requestJson<OfflineDatabasesSummaryDto>("/api/settings/offline-databases");
}

export function reindexOfflineDatabases(): Promise<void> {
  return requestVoid("/api/settings/offline-databases/reindex", { method: "POST" });
}

export interface FranchiseReindexResult {
  updatedCount: number;
}

export function reindexFranchises(): Promise<FranchiseReindexResult> {
  return requestJson<FranchiseReindexResult>("/api/settings/franchises/reindex", {
    method: "POST",
  });
}

export interface OfflineModeResponse {
  offlineMode: boolean;
  hasDatabases: boolean;
}

export function getOfflineMode(): Promise<OfflineModeResponse> {
  return requestJson<OfflineModeResponse>("/api/settings/offline-mode");
}

export function setOfflineMode(offlineMode: boolean): Promise<{ offlineMode: boolean }> {
  return requestJson<{ offlineMode: boolean }>(
    "/api/settings/offline-mode",
    jsonOptions("PUT", { offlineMode }),
  );
}
