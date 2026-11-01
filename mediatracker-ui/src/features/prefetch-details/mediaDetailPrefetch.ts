import { getMediaItem } from "$shared/api/api";
import type { MediaDetail } from "$shared/types";
import { createPrefetchCache } from "$shared/utils/prefetchCache";
import { writeCardProgress } from "$entities/media/model/progressRules";

// Методика 3: in-memory guard. Всё, что уже загружено (или грузится прямо сейчас),
// отсекается ещё до отправки запроса в сеть.
const DETAIL_TTL_MS = 5 * 60 * 1000;
const HOVER_INTENT_MS = 150;

export const mediaDetailCache = createPrefetchCache<MediaDetail>(DETAIL_TTL_MS);

export function loadMediaDetail(id: string): Promise<MediaDetail> {
  return mediaDetailCache.load(id, () => getMediaItem(id));
}

/**
 * Patches the cached detail payload with an optimistic progress value, so
 * opening the detail screen right after stepping a card shows the new number
 * immediately instead of the pre-step one while the refetch is in flight.
 */
export function updateCachedDetailProgress(id: string, value: number): void {
  const cached = mediaDetailCache.peek(id);
  if (cached && cached.id === id) {
    writeCardProgress(cached, value);
  }
}

export function prefetchMediaDetail(id: string): void {
  void import("$views/MediaDetailView.svelte");
  void loadMediaDetail(id).catch(() => {
    // Префетч best-effort: ошибка уйдёт пользователю при реальном открытии.
  });
}

let hoverTimer: ReturnType<typeof setTimeout> | undefined;

/* Пока сетка прокручивается, курсор «проезжает» по десяткам карточек, и каждая шлёт
   pointerenter. Флаг isScrolling гасит префетч на время скролла (+150 мс тишины);
   слушатель лениво вешается на #main-scroll при первом вызове, когда шелл уже смонтирован. */
const SCROLL_QUIET_MS = 150;

let isScrolling = false;
let scrollTimer: ReturnType<typeof setTimeout> | undefined;
let scrollGuardAttached = false;

function ensureScrollGuard(): void {
  if (scrollGuardAttached || typeof window === "undefined") return;
  const scroller = document.getElementById("main-scroll");
  if (!scroller) return;
  scroller.addEventListener(
    "scroll",
    () => {
      isScrolling = true;
      if (scrollTimer) clearTimeout(scrollTimer);
      scrollTimer = setTimeout(() => {
        scrollTimer = undefined;
        isScrolling = false;
      }, SCROLL_QUIET_MS);
    },
    { passive: true },
  );
  scrollGuardAttached = true;
}

/**
 * Наведение мыши по сетке вызывает pointerenter на десятках карточек подряд.
 * Один общий таймер вместо таймера на карточку: запросит только последняя.
 * Во время скролла таймер не ставится — скролл пролетает мимо, намерения нет.
 */
export function schedulePrefetchMediaDetail(id: string): void {
  if (typeof window === "undefined") return;

  ensureScrollGuard();
  if (isScrolling) return;

  if (hoverTimer) clearTimeout(hoverTimer);
  hoverTimer = setTimeout(() => {
    hoverTimer = undefined;
    prefetchMediaDetail(id);
  }, HOVER_INTENT_MS);
}
