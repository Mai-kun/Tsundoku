import { i18n } from '$lib/i18n/index.svelte'
import type {
  CreateMediaPayload,
  ExternalMedia,
  MediaDetail,
  MediaFilters,
  MediaItem,
  MediaStats,
  MediaStatus,
  SearchScope,
  UpdateMediaPayload,
} from '$lib/types'

const mediaEndpoint = '/api/media'
const externalEndpoint = '/api/external'

type ValidationErrors = Record<string, string[]>

interface ProblemDetails {
  detail?: string
  title?: string
  errors?: ValidationErrors
}

export class ApiError extends Error {
  readonly status: number
  readonly detail: string
  readonly validationErrors: ValidationErrors

  constructor(status: number, detail = '', validationErrors: ValidationErrors = {}) {
    super(detail || 'API request failed')
    this.name = 'ApiError'
    this.status = status
    this.detail = detail
    this.validationErrors = validationErrors
  }
}

export function errorMessage(error: unknown): string {
  if (error instanceof ApiError) {
    const validationMessage = Object.values(error.validationErrors).flat()[0]
    return validationMessage || error.detail || i18n.t.errors.requestFailed
  }

  return i18n.t.errors.unexpected
}

function isRecord(value: unknown): value is Record<string, unknown> {
  return typeof value === 'object' && value !== null
}

function readProblemDetails(value: unknown): ProblemDetails {
  if (!isRecord(value)) return {}

  const errors = isRecord(value.errors)
    ? Object.fromEntries(
        Object.entries(value.errors).flatMap(([key, messages]) =>
          Array.isArray(messages) && messages.every((message) => typeof message === 'string') ? [[key, messages]] : [],
        ),
      )
    : {}

  return {
    detail: typeof value.detail === 'string' ? value.detail : undefined,
    title: typeof value.title === 'string' ? value.title : undefined,
    errors,
  }
}

async function throwApiError(response: Response): Promise<never> {
  const payload: unknown = await response.json().catch(() => null)
  const problem = readProblemDetails(payload)
  throw new ApiError(response.status, problem.detail || problem.title || '', problem.errors)
}

async function requestJson<T>(url: string, options: RequestInit = {}): Promise<T> {
  const response = await fetch(url, options)

  if (!response.ok) {
    return throwApiError(response)
  }

  return (await response.json()) as unknown as T
}

async function requestVoid(url: string, options: RequestInit = {}): Promise<void> {
  const response = await fetch(url, options)

  if (!response.ok) {
    return throwApiError(response)
  }
}

function jsonOptions(method: 'POST' | 'PUT', payload: object): RequestInit {
  return {
    method,
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify(payload),
  }
}

export function getMedia(filters: MediaFilters = {}): Promise<MediaItem[]> {
  const params = new URLSearchParams()
  const queryFilters = {
    sortBy: 'createdAt' as const,
    sortOrder: 'desc' as const,
    ...filters,
  }

  for (const [key, value] of Object.entries(queryFilters)) {
    if (value !== undefined && value !== null && value !== '') {
      params.set(key, String(value))
    }
  }

  const query = params.toString()
  return requestJson<MediaItem[]>(`${mediaEndpoint}${query ? `?${query}` : ''}`)
}

export function getMediaItem(id: string): Promise<MediaDetail> {
  return requestJson<MediaDetail>(`${mediaEndpoint}/${id}`)
}

export function getStats(): Promise<MediaStats> {
  return requestJson<MediaStats>(`${mediaEndpoint}/stats`)
}

export function searchExternal(type: SearchScope, query: string): Promise<ExternalMedia[]> {
  const url = `${externalEndpoint}/search?type=${encodeURIComponent(type)}&query=${encodeURIComponent(query.trim())}`
  return requestJson<ExternalMedia[]>(url)
}

export function createMedia(payload: CreateMediaPayload): Promise<MediaDetail> {
  return requestJson<MediaDetail>(mediaEndpoint, jsonOptions('POST', payload))
}

export function updateMedia(id: string, payload: UpdateMediaPayload): Promise<MediaDetail> {
  return requestJson<MediaDetail>(`${mediaEndpoint}/${id}`, jsonOptions('PUT', payload))
}

export function setProgress(id: string, currentProgress: number): Promise<void> {
  return requestVoid(`${mediaEndpoint}/${id}/progress`, jsonOptions('PUT', { currentProgress }))
}

export function setSeasonProgress(id: string, currentEpisode: number): Promise<void> {
  return requestVoid(`/api/seasons/${id}/progress`, jsonOptions('PUT', { currentEpisode }))
}

export function updateStatus(id: string, status: MediaStatus): Promise<void> {
  return requestVoid(`${mediaEndpoint}/${id}/status`, jsonOptions('PUT', { status }))
}

export function deleteMedia(id: string): Promise<void> {
  return requestVoid(`${mediaEndpoint}/${id}`, { method: 'DELETE' })
}

export function refreshMetadata(id: string): Promise<MediaDetail> {
  return requestJson<MediaDetail>(`${mediaEndpoint}/${id}/refresh`, { method: 'POST' })
}

export function getSources(): Promise<import('$lib/types').SourceInfo[]> {
  return requestJson<import('$lib/types').SourceInfo[]>('/api/settings/sources')
}

export function saveSourceKey(
  sourceId: string,
  apiKey: string,
): Promise<{ success: boolean; hasKey: boolean; maskedKey: string | null }> {
  return requestJson(`/api/settings/sources/${sourceId}/key`, jsonOptions('PUT', { apiKey }))
}

export function getCategoryOrder(): Promise<string[]> {
  return requestJson<string[]>('/api/settings/category-order')
}

export function saveCategoryOrder(order: string[]): Promise<string[]> {
  return requestJson<string[]>('/api/settings/category-order', {
    method: 'PUT',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify(order),
  })
}

export function getSourcePriority(): Promise<Record<string, string[]>> {
  return requestJson<Record<string, string[]>>('/api/settings/source-priority')
}

export function saveSourcePriority(priority: Record<string, string[]>): Promise<Record<string, string[]>> {
  return requestJson<Record<string, string[]>>('/api/settings/source-priority', {
    method: 'PUT',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify(priority),
  })
}

