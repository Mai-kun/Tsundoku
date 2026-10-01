import { i18n } from "$lib/i18n/index.svelte";
import type {
  ConnectionTestResult,
  CreateMediaPayload,
  CreateVolumePayload,
  ExternalMedia,
  MangaVolume,
  MediaDetail,
  MediaFilters,
  MediaItem,
  MediaStats,
  MediaStatus,
  SearchScope,
  SourceInfo,
  GameAchievementsResponse,
  GameRelatedItem,
  UpdateMediaPayload,
  UpdateVolumePayload,
} from "$lib/types";

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

  constructor(
    status: number,
    detail = "",
    validationErrors: ValidationErrors = {},
  ) {
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
          Array.isArray(messages) &&
          messages.every((message) => typeof message === "string")
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
  throw new ApiError(
    response.status,
    problem.detail || problem.title || "",
    problem.errors,
  );
}

async function requestJson<T>(
  url: string,
  options: RequestInit = {},
): Promise<T> {
  const response = await fetch(url, options);

  if (!response.ok) {
    return throwApiError(response);
  }

  return (await response.json()) as unknown as T;
}

async function requestVoid(
  url: string,
  options: RequestInit = {},
): Promise<void> {
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
  return requestJson<MediaItem[]>(
    `${mediaEndpoint}${query ? `?${query}` : ""}`,
  );
}

export function getMediaItem(id: string): Promise<MediaDetail> {
  return requestJson<MediaDetail>(`${mediaEndpoint}/${id}`);
}

export function getStats(): Promise<MediaStats> {
  return requestJson<MediaStats>(`${mediaEndpoint}/stats`);
}

export function searchExternal(
  type: SearchScope,
  query: string,
  signal?: AbortSignal,
): Promise<ExternalMedia[]> {
  const url = `${externalEndpoint}/search?type=${encodeURIComponent(type)}&query=${encodeURIComponent(query.trim())}`;
  return requestJson<ExternalMedia[]>(url, { signal });
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

export function updateMedia(
  id: string,
  payload: UpdateMediaPayload,
): Promise<MediaDetail> {
  return requestJson<MediaDetail>(
    `${mediaEndpoint}/${id}`,
    jsonOptions("PUT", payload),
  );
}

export function enrichMedia(id: string): Promise<MediaDetail> {
  return requestJson<MediaDetail>(`${mediaEndpoint}/${id}/enrich`, {
    method: "POST",
  });
}

export function setProgress(
  id: string,
  currentProgress: number,
): Promise<void> {
  return requestVoid(
    `${mediaEndpoint}/${id}/progress`,
    jsonOptions("PUT", { currentProgress }),
  );
}

export function setSeasonProgress(
  id: string,
  currentEpisode: number,
): Promise<void> {
  return requestVoid(
    `/api/seasons/${id}/progress`,
    jsonOptions("PUT", { currentEpisode }),
  );
}

export function setVolumeProgress(
  id: string,
  progress: { currentPage?: number; currentChapter?: number },
): Promise<void> {
  return requestVoid(
    `/api/volumes/${id}/progress`,
    jsonOptions("PUT", progress),
  );
}

export function addVolume(
  mangaId: string,
  payload: CreateVolumePayload,
): Promise<MangaVolume> {
  return requestJson<MangaVolume>(
    `/api/volumes?mangaId=${mangaId}`,
    jsonOptions("POST", payload),
  );
}

export function updateVolume(
  id: string,
  payload: UpdateVolumePayload,
): Promise<MangaVolume> {
  return requestJson<MangaVolume>(
    `/api/volumes/${id}`,
    jsonOptions("PUT", payload),
  );
}

export function deleteVolume(id: string): Promise<void> {
  return requestVoid(`/api/volumes/${id}`, { method: "DELETE" });
}

export function updateStatus(id: string, status: MediaStatus): Promise<void> {
  return requestVoid(
    `${mediaEndpoint}/${id}/status`,
    jsonOptions("PUT", { status }),
  );
}

export function deleteMedia(id: string): Promise<void> {
  return requestVoid(`${mediaEndpoint}/${id}`, { method: "DELETE" });
}

export function refreshMetadata(id: string): Promise<MediaDetail> {
  return requestJson<MediaDetail>(`${mediaEndpoint}/${id}/refresh`, {
    method: "POST",
  });
}

export function getSources(): Promise<SourceInfo[]> {
  return requestJson<SourceInfo[]>("/api/settings/sources");
}

export function toggleSourceEnabled(
  sourceId: string,
  enabled: boolean,
): Promise<{ success: boolean; isEnabled: boolean }> {
  return requestJson(
    `/api/settings/sources/${sourceId}/toggle`,
    jsonOptions("PUT", { enabled }),
  );
}

export function testSourceConnection(
  sourceId: string,
): Promise<ConnectionTestResult> {
  return requestJson<ConnectionTestResult>(
    `/api/settings/sources/${sourceId}/test`,
    { method: "POST" },
  );
}

export function saveSourceKey(
  sourceId: string,
  apiKey: string,
): Promise<{ success: boolean; hasKey: boolean; maskedKey: string | null }> {
  return requestJson(
    `/api/settings/sources/${sourceId}/key`,
    jsonOptions("PUT", { apiKey }),
  );
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
  return requestJson<Record<string, string[]>>(
    "/api/settings/source-priority",
    {
      method: "PUT",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify(priority),
    },
  );
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
  return requestJson<GameRelatedItem[]>(
    `/api/external/games/related?${query.toString()}`,
  );
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
  return requestJson<GameRelatedItem[]>(
    `/api/external/games/recommendations?${query.toString()}`,
  );
}

export function clearAllHistory(): Promise<void> {
  return requestVoid("/api/history", { method: "DELETE" });
}

export function deleteHistoryEntry(
  id: string,
  kind: "started" | "finished",
): Promise<void> {
  return requestVoid(`/api/history/${id}/${kind}`, { method: "DELETE" });
}
