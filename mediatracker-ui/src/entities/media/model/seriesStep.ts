import type { TvSeason } from "$shared/types";

/** Which season a +/- press on a card writes to, and the value it lands on. */
export interface SeriesEpisodeStep {
    seasonId: string;
    currentEpisode: number;
}

/**
 * Resolves one +/- press on a show's episode counter across the whole series instead of inside a
 * single season. Forward lands on the first season that still has an episode left; backward leaves
 * the last season that still has one, so the floor is a flat 0 for the series and not an artificial
 * stop at every season boundary.
 */
export function nextSeriesEpisodeStep(
    seasons: readonly TvSeason[],
    delta: number,
): SeriesEpisodeStep | null {
    if (seasons.length === 0 || delta === 0) return null;

    const ordered = [...seasons].sort((a, b) => a.seasonNumber - b.seasonNumber);

    if (delta < 0) {
        for (let i = ordered.length - 1; i >= 0; i--) {
            const current = ordered[i].currentEpisode ?? 0;
            if (current > 0) {
                return { seasonId: ordered[i].id, currentEpisode: current - 1 };
            }
        }
        return null;
    }

    const total = (season: TvSeason) => season.totalEpisodes ?? 0;
    const target =
        ordered.find((s) => total(s) > 0 && (s.currentEpisode ?? 0) < total(s)) ??
        ordered.find((s) => total(s) <= 0);
    if (!target) return null;

    const current = target.currentEpisode ?? 0;
    const next = total(target) > 0 ? Math.min(current + delta, total(target)) : current + delta;
    return next === current ? null : { seasonId: target.id, currentEpisode: next };
}