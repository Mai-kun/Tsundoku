import { SvelteMap } from "svelte/reactivity";
import { createProgressDebounce } from "$shared/utils/progressDebounce";
import { errorMessage, setSeasonProgress, updateStatus } from "$shared/api/api";
import { showToast } from "$shared/ui/toast.svelte";
import { i18n } from "$shared/i18n/index.svelte";
import { MEDIA_STATUS, isTvShowDetail, type MediaStatus, type TvSeason, type TvShowMedia } from "$shared/types";
import { shouldPromoteToInProgress, writeCardProgress } from "$entities/media/model/progressRules";
import { notifyAutoInProgress } from "$features/update-progress/statusPromotionToast.svelte";
import { nextSeriesEpisodeStep, type SeriesEpisodeStep } from "$entities/media/model/seriesStep";
import {
  loadMediaDetail,
  mediaDetailCache,
  updateCachedDetailProgress,
} from "$features/prefetch-details/mediaDetailPrefetch";
import {
  applyOptimisticProgress,
  clearOptimisticProgress,
  resolveOptimisticProgress,
} from "./optimisticProgress.svelte";

/**
 * TV/Anime episode stepping without the per-click network race. The old flow
 * fetched the detail row on every +/- press and PUT the season immediately,
 * so bursts of clicks raced each other and the counters stuck or jumped back.
 *
 * Now a click only moves the local counter (0 ms) and registers into a
 * per-media 3s debounce; the flush computes ONE season write for the final
 * absolute total and sends it. Season data comes from the shared prefetch
 * cache (absolute totals only — stale `currentEpisode` values in the snapshot
 * cannot change the result), fetched at most once per media when absent.
 */

interface SeriesStepContext {
  item: TvShowMedia;
  /** Series total before the first pending step: the error rollback target. */
  previousTotal: number;
  onCommitted?: (id: string) => void;
}

const contexts = new SvelteMap<string, SeriesStepContext>();
const debouncers = new SvelteMap<string, ReturnType<typeof createProgressDebounce>>();

/** Season write that puts the series at exactly `value` watched episodes. */
function absoluteSeriesTarget(
  seasons: readonly TvSeason[],
  value: number,
): SeriesEpisodeStep | null {
  if (seasons.length === 0) return null;
  const ordered = [...seasons].sort((a, b) => a.seasonNumber - b.seasonNumber);

  let cumulative = 0;
  for (const season of ordered) {
    const total = season.totalEpisodes ?? 0;
    // A season with an unknown length ends the walk: everything left lands there.
    if (total <= 0 || value <= cumulative + total) {
      return { seasonId: season.id, currentEpisode: Math.max(0, value - cumulative) };
    }
    cumulative += total;
  }
  const last = ordered[ordered.length - 1];
  return { seasonId: last.id, currentEpisode: last.totalEpisodes ?? 0 };
}

async function resolveSeriesStep(id: string, value: number): Promise<SeriesEpisodeStep | null> {
  try {
    const detail = await loadMediaDetail(id);
    if (!isTvShowDetail(detail) || !detail.seasons?.length) return null;
    return absoluteSeriesTarget(detail.seasons, value);
  } catch {
    return null;
  }
}

function getDebouncer(id: string) {
  let debouncer = debouncers.get(id);
  if (!debouncer) {
    debouncer = createProgressDebounce({
      send: async (mediaId, value) => {
        const step = await resolveSeriesStep(mediaId, value);
        if (!step) return;
        await setSeasonProgress(step.seasonId, step.currentEpisode);
      },
      // Keepalive flush (tab hide / window close) cannot await a fetch for the
      // season list: it targets the seasons snapshot already in memory.
      buildRequest: (mediaId, value) => {
        const cached = mediaDetailCache.peek(mediaId);
        if (cached && isTvShowDetail(cached) && cached.seasons?.length) {
          const step = absoluteSeriesTarget(cached.seasons, value);
          if (step) {
            return {
              url: `/api/seasons/${step.seasonId}/progress`,
              body: { currentEpisode: step.currentEpisode },
            };
          }
        }
        return { url: "", body: null };
      },
      onCommitted: (value) => {
        const context = contexts.get(id);
        resolveOptimisticProgress(id, value);
        mediaDetailCache.invalidate(id);
        context?.onCommitted?.(id);
        contexts.delete(id);
      },
      onError: (failure) => {
        const context = contexts.get(id);
        clearOptimisticProgress(id);
        contexts.delete(id);
        if (context) {
          // Roll the raw item back; the card's $effect reads this field, so
          // the visible counter resnaps without any extra plumbing.
          writeCardProgress(context.item, context.previousTotal);
          showToast({
            title: i18n.t.toast.actionFailed,
            description: errorMessage(failure),
            type: "error",
          });
        }
      },
    });
    debouncers.set(id, debouncer);
  }
  return debouncer;
}

/** Optimistically bumps a cached seasons snapshot so a hover-prefetched
 *  detail page does not open with the pre-step per-season numbers. */
function patchCachedSeasonStep(id: string, delta: number): void {
  const cached = mediaDetailCache.peek(id);
  if (!cached || !isTvShowDetail(cached) || !cached.seasons?.length) return;
  const step = nextSeriesEpisodeStep(cached.seasons, delta);
  if (!step) return;
  const season = cached.seasons.find((s) => s.id === step.seasonId);
  if (season) season.currentEpisode = step.currentEpisode;
}

export function stepSeriesEpisodes(
  item: TvShowMedia,
  delta: number,
  options?: { onCommitted?: (id: string) => void },
): void {
  const current = item.totalEpisodesWatched ?? 0;
  const next = Math.max(0, current + delta);
  if (next === current) return;

  // Rule 1 of the status contract: only the exact 0 → 1 step of the series
  // total implies watching started. The badge flips optimistically here; the
  // debounced season PUT carries the same rule server-side, so a refetch (or
  // an F5) shows the very same status. The flip is announced by an interactive
  // toast with persisted undo / keep-status outcomes.
  if (shouldPromoteToInProgress(current, next) && item.status !== MEDIA_STATUS.inProgress) {
    const previousStatus = item.status;
    item.status = MEDIA_STATUS.inProgress;
    notifyAutoInProgress(item, previousStatus, {
      undo: () => revertSeriesPromotion(item, previousStatus),
      keepStatus: () => keepSeriesProgressOnly(item, previousStatus, next),
    });
  }

  writeCardProgress(item, next);
  applyOptimisticProgress(item.id, next);
  updateCachedDetailProgress(item.id, next);
  patchCachedSeasonStep(item.id, delta);

  const existing = contexts.get(item.id);
  contexts.set(item.id, {
    item,
    // Roll back to where the burst started, not to the previous click.
    previousTotal: existing ? existing.previousTotal : current,
    onCommitted: options?.onCommitted ?? existing?.onCommitted,
  });
  getDebouncer(item.id).schedule(item.id, next);
}

/** Undo for a series: the pending season write is cancelled, then the first season is
 *  zeroed and the previous status restored — both persisted server-side. */
async function revertSeriesPromotion(item: TvShowMedia, previousStatus: MediaStatus): Promise<void> {
  getDebouncer(item.id).cancel();
  clearOptimisticProgress(item.id);
  mediaDetailCache.invalidate(item.id);
  writeCardProgress(item, 0);
  item.status = previousStatus;
  try {
    const step = await resolveSeriesStep(item.id, 0);
    if (step) await setSeasonProgress(step.seasonId, step.currentEpisode);
  } catch (failure) {
    console.error(failure);
  }
  void updateStatus(item.id, previousStatus).catch((failure) => console.error(failure));
}

/** Keep-status for a series: the progress stays (persisted explicitly, since the
 *  debounced write is cancelled) and the previous status is restored. */
async function keepSeriesProgressOnly(
  item: TvShowMedia,
  previousStatus: MediaStatus,
  value: number,
): Promise<void> {
  getDebouncer(item.id).cancel();
  item.status = previousStatus;
  try {
    const step = await resolveSeriesStep(item.id, value);
    if (step) await setSeasonProgress(step.seasonId, step.currentEpisode);
  } catch (failure) {
    console.error(failure);
  }
  void updateStatus(item.id, previousStatus).catch((failure) => console.error(failure));
}
