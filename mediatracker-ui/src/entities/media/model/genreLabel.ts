import { i18n } from "$shared/i18n/index.svelte";

/**
 * Canonical genre keys (camelCase translations keys from stats.genres) whose natural
 * camelCasing from the Title Case genre name does not produce the key.
 */
const ALIASES: Record<string, string> = {
    "sci fi": "sciFi",
    "slice of life": "sliceOfLife",
    "game show": "gameShow",
    "talk show": "talkShow",
    "martial arts": "martialarts",
    "board & card": "boardAndCard",
    "board and card": "boardAndCard",
    "utilities & software": "utilitiesAndSoftware",
    "utilities and software": "utilitiesAndSoftware",
    "programming & it": "programmingAndIt",
    "programming and it": "programmingAndIt",
    "business & economics": "businessAndEconomics",
    "business and economics": "businessAndEconomics",
    "art & design": "artAndDesign",
    "art and design": "artAndDesign",
    // Legacy canonical names still stored in old rows of tracker.db
    reality: "realityTv",
    kids: "family",
};

/** Localizes a canonical (or already-normalized) genre name; unknown genres pass through untouched. */
export function genreLabel(genre: string): string {
    const normalized = genre.toLowerCase().replace(/[^a-z0-9]+/g, " ").trim();
    const key =
        ALIASES[normalized] ??
        normalized
            .replace(/\s+([a-z])/g, (_, letter: string) => letter.toUpperCase())
            .replace(/^([a-z])/, (_, letter: string) => letter.toLowerCase());
    return key in i18n.t.stats.genres
        ? i18n.t.stats.genres[key as keyof typeof i18n.t.stats.genres]
        : genre;
}

/** Localizes a genre list and removes duplicates, so "Боевик, Боевик" never renders. */
export function formatGenresList(genres: readonly string[]): string[] {
    return [...new Set(genres.map((genre) => genreLabel(genre.trim())).filter(Boolean))];
}
