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
  MediaStats,
  AdvancedStats,
  TasteProfile,
  MediaStatus,
  SearchScope,
  SourceInfo,
  GameAchievementsResponse,
  GameRelatedItem,
  ExternalRecommendation,
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
  PendingMatchItemDto,
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

async function requestJson<T>(url: string, options: RequestInit = {}): Promise<T> {
  const response = await fetch(url, options);

  if (!response.ok) {
    return throwApiError(response);
  }

  return (await response.json()) as unknown as T;
}

async function requestVoid(url: string, options: RequestInit = {}): Promise<void> {
  const response = await fetch(url, options);

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
  return requestJson<MediaItem[]>(`${mediaEndpoint}${query ? `?${query}` : ""}`);
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

export function getStats(): Promise<MediaStats> {
  return requestJson<MediaStats>(`${mediaEndpoint}/stats`);
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

export function getGameRecommendations(params: {
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
  return requestJson<GameRelatedItem[]>(`/api/external/games/recommendations?${query.toString()}`);
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

/**
 * Recommendations for one item, fetched and stored by the server.
 *
 * The list is kept on the media row, so a call inside the 30-day window is answered from SQLite with
 * no provider request at all; `forceRefresh` is what the panel's reload button sets.
 */
export function getMediaRecommendations(
  id: string,
  source: string | null,
  forceRefresh = false,
): Promise<ExternalRecommendation[]> {
  const query = new URLSearchParams();
  if (source) query.set("source", source);
  if (forceRefresh) query.set("forceRefresh", "true");
  return requestJson<ExternalRecommendation[]>(
    `/api/media/${id}/recommendations?${query.toString()}`,
    { method: "POST" },
  );
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
  const response = await fetch("/api/settings/backup/export");
  if (!response.ok) {
    return throwApiError(response);
  }
  return response.blob();
}

export async function restoreBackup(file: File): Promise<void> {
  const formData = new FormData();
  formData.append("backupFile", file);

  const response = await fetch("/api/settings/backup/restore", {
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

