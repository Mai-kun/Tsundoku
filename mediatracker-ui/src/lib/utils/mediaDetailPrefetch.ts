import { getMediaItem } from '$lib/api'
import type { MediaDetail } from '$lib/types'
import { createPrefetchCache } from './prefetchCache'

// Методика 3: in-memory guard. Всё, что уже загружено (или грузится прямо сейчас),
// отсекается ещё до отправки запроса в сеть.
const DETAIL_TTL_MS = 5 * 60 * 1000
const HOVER_INTENT_MS = 150

export const mediaDetailCache = createPrefetchCache<MediaDetail>(DETAIL_TTL_MS)

export function loadMediaDetail(id: string): Promise<MediaDetail> {
  return mediaDetailCache.load(id, () => getMediaItem(id))
}

export function prefetchMediaDetail(id: string): void {
  void loadMediaDetail(id).catch(() => {
    // Префетч best-effort: ошибка уйдёт пользователю при реальном открытии.
  })
}

let hoverTimer: ReturnType<typeof setTimeout> | undefined

/**
 * Наведение мыши по сетке вызывает pointerenter на десятках карточек подряд.
 * Один общий таймер вместо таймера на карточку: запросит только последняя.
 */
export function schedulePrefetchMediaDetail(id: string): void {
  if (typeof window === 'undefined') return

  if (hoverTimer) clearTimeout(hoverTimer)
  hoverTimer = setTimeout(() => {
    hoverTimer = undefined
    prefetchMediaDetail(id)
  }, HOVER_INTENT_MS)
}
