import type { MediaItem } from "$shared/types";
import type { RelatedEntry } from "./detailTypes";

/**
 * Normalizes title string by removing punctuation, spaces and non-alphanumeric chars
 * while preserving Latin, Cyrillic, Kanji, Hiragana and Katakana.
 */
export function normalizeTitle(s: string | null | undefined): string {
    return (s || "")
        .toLowerCase()
        .replace(/[・\u30fb\u3000-\u303f\uff00-\uffef]/g, "")
        .replace(/[^a-zа-я0-9\u3040-\u30ff\u3400-\u4dbf\u4e00-\u9fff]/gi, "")
        .trim();
}

/** Checks whether a title or format represents a movie/film. */
export function hasMovieMarker(s: string | null | undefined): boolean {
    if (!s) return false;
    return (
        /\b(movie|the\s+movie|film|the\s+film)\b/i.test(s) ||
        /(фильм|полнометраж)/i.test(s) ||
        /(劇場版|映画)/.test(s)
    );
}

/** Strips movie/film markers and common articles for base title comparison. */
export function stripMovieMarker(s: string | null | undefined): string {
    if (!s) return "";
    return s
        .replace(/\b(the\s+movie|movie|the\s+film|film)\b/gi, "")
        .replace(/(фильм|фильм\s+\d+|полнометражный\s+фильм|полнометражка)/gi, "")
        .replace(/(劇場版|映画)/g, "")
        .replace(/\b(the|a|an)\b/gi, "")
        .trim();
}

function readItemRomaji(item: { type?: string; romajiTitle?: string | null }): string | null {
    if (item.type === "game" || item.type === "book") return null;
    const val = item.romajiTitle?.trim();
    return val ? val : null;
}

/**
 * Smart matching between an external relation entry and a library item.
 * Follows the cascade:
 * 1. External ID match (item.externalId === rel.id)
 * 2. Original title match (Japanese / native names)
 * 3. Romaji title match
 * 4. Cross-title normalized match (all variants)
 * 5. Base title match with movie/film markers stripped (when both represent movies)
 */
export function isRelatedMatch(rel: RelatedEntry, item: MediaItem): boolean {
    // 1. External ID match
    if (
        item.externalId &&
        rel.id &&
        String(item.externalId).trim() === String(rel.id).trim()
    ) {
        return true;
    }

    const itemOrig = (item as { originalTitle?: string | null }).originalTitle?.trim() || null;
    const relOrig = rel.originalTitle?.trim() || null;
    const itemRomaji = readItemRomaji(item as { type?: string; romajiTitle?: string | null });
    const relRomaji = rel.romajiTitle?.trim() || null;

    // 2. Original title match
    if (itemOrig && relOrig) {
        const normItemOrig = normalizeTitle(itemOrig);
        const normRelOrig = normalizeTitle(relOrig);
        if (normItemOrig.length > 0 && normItemOrig === normRelOrig) {
            return true;
        }
    }

    // 3. Romaji title match
    if (itemRomaji && relRomaji) {
        const normItemRomaji = normalizeTitle(itemRomaji);
        const normRelRomaji = normalizeTitle(relRomaji);
        if (normItemRomaji.length > 0 && normItemRomaji === normRelRomaji) {
            return true;
        }
    }

    // 4. Normalized cross-title match
    const itemCandidates = [item.title, itemRomaji, itemOrig].filter(Boolean) as string[];
    const relCandidates = [rel.title, relRomaji, relOrig].filter(Boolean) as string[];

    const normRelList = relCandidates
        .map((t) => normalizeTitle(t))
        .filter((t) => t.length > 0);

    for (const itemTitle of itemCandidates) {
        const normItem = normalizeTitle(itemTitle);
        if (normItem.length > 0 && normRelList.includes(normItem)) {
            return true;
        }
    }

    // 5. Movie / Film marker match: when BOTH represent movies
    const itemIsMovie =
        item.type === "movie" ||
        hasMovieMarker(item.title) ||
        hasMovieMarker(itemRomaji);
    const relIsMovie =
        rel.format?.toUpperCase() === "MOVIE" ||
        rel.type === "movie" ||
        hasMovieMarker(rel.title) ||
        hasMovieMarker(relRomaji);

    if (itemIsMovie && relIsMovie) {
        const strippedRelList = relCandidates
            .map((t) => normalizeTitle(stripMovieMarker(t)))
            .filter((t) => t.length >= 3);

        for (const itemTitle of itemCandidates) {
            const strippedItem = normalizeTitle(stripMovieMarker(itemTitle));
            if (strippedItem.length >= 3 && strippedRelList.includes(strippedItem)) {
                return true;
            }
        }
    }

    return false;
}

/** Finds a matching library item for an external relation entry. */
export function findMatchingLocal(
    rel: RelatedEntry,
    all: readonly MediaItem[],
): MediaItem | undefined {
    return all.find((item) => isRelatedMatch(rel, item));
}
