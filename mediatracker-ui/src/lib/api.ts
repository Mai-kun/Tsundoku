import { i18n } from '$lib/i18n/index.svelte'
import type {
  CreateMediaPayload,
  ExternalMedia,
  MediaFilters,
  MediaItem,
  MediaStats,
} from '$lib/types'

const mediaEndpoint = '/api/media'
const externalEndpoint = '/api/external'

export class ApiError extends Error {
  readonly detail: string

  constructor(detail?: string) {
    super(detail || 'API request failed')
    this.detail = detail ?? ''
  }
}

export function errorMessage(error: unknown): string {
  if (error instanceof ApiError) {
    return error.detail || i18n.t.errors.requestFailed
  }

  return i18n.t.errors.unexpected
}

async function request<T>(url: string, options: RequestInit = {}): Promise<T> {
  const response = await fetch(url, options)

  if (!response.ok) {
    const payload = (await response.json().catch(() => null)) as {
      detail?: string
      title?: string
    } | null
    throw new ApiError(payload?.detail || payload?.title || '')
  }

  if (response.status === 204) {
    return null as T
  }

  return (await response.json()) as T
}

export function getMedia(filters: MediaFilters = {}): Promise<MediaItem[]> {
  const params = new URLSearchParams()
  const queryFilters: Record<string, string | number | boolean | undefined> = {
    sortBy: 'createdAt',
    sortOrder: 'desc',
    ...filters,
  }

  for (const [key, value] of Object.entries(queryFilters)) {
    if (value !== undefined && value !== null && value !== '') {
      params.set(key, String(value))
    }
  }

  const query = params.toString()
  return request<MediaItem[]>(`${mediaEndpoint}${query ? `?${query}` : ''}`)
}

export function getStats(): Promise<MediaStats> {
  return request<MediaStats>(`${mediaEndpoint}/stats`)
}

export function searchExternal(type: string, query: string): Promise<ExternalMedia[]> {
  return request<ExternalMedia[]>(`${externalEndpoint}/search?type=${type}&query=${encodeURIComponent(query)}`)
}

export function createMedia(payload: CreateMediaPayload): Promise<MediaItem> {
  return request<MediaItem>(mediaEndpoint, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify(payload),
  })
}

export function incrementProgress(id: string, currentProgress: number): Promise<MediaItem> {
  return request<MediaItem>(`${mediaEndpoint}/${id}/progress`, {
    method: 'PUT',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ currentProgress }),
  })
}

export function updateStatus(id: string, status: number): Promise<MediaItem> {
  return request<MediaItem>(`${mediaEndpoint}/${id}/status`, {
    method: 'PUT',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ status }),
  })
}

export function deleteMedia(id: string): Promise<null> {
  return request<null>(`${mediaEndpoint}/${id}`, { method: 'DELETE' })
}