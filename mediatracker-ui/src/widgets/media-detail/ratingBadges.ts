import type { SourceInfo } from "$shared/types";
import type { RatingBadge } from "./detailTypes";

/**
 * Sources per category, used when the enabled-source list has not loaded yet (or is
 * unavailable) so the header still shows the badges the user expects to see.
 */
export const CATEGORY_EXPECTED_SOURCES: Record<string, string[]> = {
    anime: ["AniList", "MyAnimeList"],
    manga: ["AniList", "MangaDex", "MangaUpdates", "MyAnimeList"],
    movie: ["TMDB"],
    tvshow: ["TMDB"],
    game: ["RAWG", "Steam", "IGDB"],
    book: ["OpenLibrary", "Google Books"],
};

export interface RawRating {
    source: string;
    rating: number | null;
    votes?: number | null;
    queried?: boolean;
}

export interface RatingBadgeInput {
    /** Ratings already reported by the sources, in provider order. */
    ratings: readonly RawRating[];
    /**
     * Single-score fallback for sources that expose one number instead of a list. Only used
     * when `ratings` came back empty.
     */
    fallback?: { source: string; score: number; votes?: number | null } | null;
    /** Aggregator category used to decide which sources are still missing. */
    category: string;
    availableSources: readonly SourceInfo[];
    /** Used when `availableSources` is empty. */
    fallbackSources?: readonly string[];
    /** Appends a placeholder for expected sources that never answered. */
    includeMissing?: boolean;
}

/**
 * One badge list for all three rating consumers (library detail header, related preview
 * modal, search preview).
 *
 * Two behaviours matter and were previously reimplemented three times:
 *  - a score of 0 means "asked, no rating" and renders as a placeholder, not as a missing
 *    source, otherwise the panel keeps re-requesting APIs that already answered empty;
 *  - disabled sources are dropped entirely rather than shown as empty badges.
 */
export function buildRatingBadges({
    ratings,
    fallback = null,
    category,
    availableSources,
    fallbackSources = CATEGORY_EXPECTED_SOURCES[category] ?? [],
    includeMissing = true,
}: RatingBadgeInput): RatingBadge[] {
    const results: RatingBadge[] = [];
    const seen = new Set<string>();
    const disabledSources = new Set(
        availableSources
            .filter((s) => !s.isEnabled)
            .flatMap((s) => [s.name.toLowerCase(), s.id.toLowerCase()]),
    );

    for (const r of ratings) {
        const src = (r.source ?? "").trim();
        if (!src || disabledSources.has(src.toLowerCase())) continue;
        const key = src.toLowerCase();
        if (seen.has(key)) continue;
        seen.add(key);
        results.push({
            source: src,
            score: r.rating !== null && r.rating > 0 ? r.rating : null,
            votes: r.votes ?? null,
            queried: r.queried,
        });
    }

    if (
        results.length === 0 &&
        fallback &&
        !disabledSources.has(fallback.source.toLowerCase())
    ) {
        seen.add(fallback.source.toLowerCase());
        results.push({
            source: fallback.source,
            score: fallback.score,
            votes: fallback.votes ?? null,
        });
    }

    if (!includeMissing) return results;

    const expected =
        availableSources.length > 0
            ? availableSources
                  .filter((s) => s.isEnabled && s.mediaTypes.includes(category))
                  .map((s) => s.name)
            : fallbackSources;

    for (const exp of expected) {
        const expNorm = exp.toLowerCase();
        // Provider names vary ("MyAnimeList" vs "MAL"), so match on containment either way.
        const found = Array.from(seen).some(
            (s) => s.includes(expNorm) || expNorm.includes(s),
        );
        if (!found) {
            seen.add(expNorm);
            results.push({ source: exp, score: null, votes: null });
        }
    }

    return results;
}