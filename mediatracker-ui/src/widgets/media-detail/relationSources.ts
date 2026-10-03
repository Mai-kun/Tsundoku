import { getSources } from "$shared/api/api";
import type { SourceInfo } from "$shared/types";
import { isAnime } from "./detailFormatters";

/**
 * Which sources can actually answer "what else is there?" for a media type.
 *
 * Offering every registered source meant half the picks returned nothing, because most providers only
 * expose a metadata endpoint. This is the whitelist of the ones with a relations source, narrowed
 * further to what the user has enabled in settings.
 */
const RELATION_SOURCES: Record<string, readonly string[]> = {
    movie: ["tmdb"],
    tvshow: ["tmdb"],
    game: ["rawg"],
    anime: ["anilist", "myanimelist", "jikan", "shikimori"],
    manga: ["anilist", "mangadex"],
};

export interface RelationSourceOption {
    id: string;
    label: string;
}

/** The relations-capable sources for this item, reduced to the ones the user has switched on. */
export async function availableRelationSources(item: {
    type: string;
    isAnime?: boolean;
}): Promise<RelationSourceOption[]> {
    const bucket = isAnime(item as never) ? "anime" : item.type;
    const allowed = RELATION_SOURCES[bucket];
    if (!allowed) return [];

    let sources: SourceInfo[];
    try {
        sources = await getSources();
    } catch {
        return [];
    }

    return sources
        .filter((source) => source.isEnabled)
        .filter((source) => {
            const haystack = `${source.id} ${source.name}`.toLowerCase();
            return allowed.some((needle) => haystack.includes(needle));
        })
        .map((source) => ({ id: source.id, label: source.name }));
}