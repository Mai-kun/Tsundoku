import { i18n } from "$shared/i18n/index.svelte";

const ALIASES: Record<string, string> = {
    "sci fi": "sciFi",
    "slice of life": "sliceOfLife",
    "game show": "gameShow",
    "talk show": "talkShow",
};

/** Matches the localized genre naming of TopGenresBar for the taste-profile widgets. */
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
