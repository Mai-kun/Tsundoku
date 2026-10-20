import type { MediaItem } from "$shared/types";

export type StaleThresholdDays = 90 | 180 | 365;

export function getDaysInactive(item: { lastActivityAt?: string | null; startedAt?: string | null; createdAt?: string | null }): number {
    const rawDate = item.lastActivityAt || item.startedAt || item.createdAt;
    if (!rawDate) return 0;
    const diffMs = Date.now() - new Date(rawDate).getTime();
    return Math.max(0, Math.floor(diffMs / (1000 * 60 * 60 * 24)));
}

export function isStaleInProgress(item: MediaItem, thresholdDays: number = 180): boolean {
    if (item.status !== 1) return false; // MEDIA_STATUS.inProgress
    return getDaysInactive(item) >= thresholdDays;
}
