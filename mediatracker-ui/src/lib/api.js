const mediaEndpoint = '/api/media'

async function request(url, options = {}) {
  const response = await fetch(url, options)

  if (!response.ok) {
    const payload = await response.json().catch(() => null)
    throw new Error(payload?.detail || payload?.title || 'Не удалось выполнить запрос.')
  }

  if (response.status === 204) {
    return null
  }

  return response.json()
}

export function getMedia(filters = {}) {
  const params = new URLSearchParams()

  for (const [key, value] of Object.entries(filters)) {
    if (value !== undefined && value !== null && value !== '') {
      params.set(key, String(value))
    }
  }

  const query = params.toString()
  return request(`${mediaEndpoint}${query ? `?${query}` : ''}`)
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
