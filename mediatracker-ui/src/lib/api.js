import { i18n } from '$lib/i18n/index.svelte'

const mediaEndpoint = '/api/media'
const externalEndpoint = '/api/external'

export class ApiError extends Error {
  /** @param {string} [detail] */
  constructor(detail) {
    super(detail || 'API request failed')
    this.detail = detail ?? ''
  }
}

/** @param {unknown} error */
export function errorMessage(error) {
  if (error instanceof ApiError) {
    return error.detail || i18n.t.errors.requestFailed
  }

  return i18n.t.errors.unexpected
}

async function request(url, options = {}) {
  const response = await fetch(url, options)

  if (!response.ok) {
    const payload = await response.json().catch(() => null)
    throw new ApiError(payload?.detail || payload?.title || '')
  }

  if (response.status === 204) {
    return null
  }

  return response.json()
}

export function getMedia(filters = {}) {
  const params = new URLSearchParams()
  const queryFilters = { sortBy: 'createdAt', sortOrder: 'desc', ...filters }

  for (const [key, value] of Object.entries(queryFilters)) {
    if (value !== undefined && value !== null && value !== '') {
      params.set(key, String(value))
    }
  }

  const query = params.toString()
  return request(`${mediaEndpoint}${query ? `?${query}` : ''}`)
}

export function getStats() {
  return request(`${mediaEndpoint}/stats`)
}

export function searchExternal(type, query) {
  return request(`${externalEndpoint}/search?type=${type}&query=${encodeURIComponent(query)}`)
}

export function createMedia(payload) {
  return request(mediaEndpoint, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify(payload),
  })
}

export function incrementProgress(id, currentProgress) {
  return request(`${mediaEndpoint}/${id}/progress`, {
    method: 'PUT',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ currentProgress }),
  })
}

export function updateStatus(id, status) {
  return request(`${mediaEndpoint}/${id}/status`, {
    method: 'PUT',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ status }),
  })
}

export function deleteMedia(id) {
  return request(`${mediaEndpoint}/${id}`, { method: 'DELETE' })
}
