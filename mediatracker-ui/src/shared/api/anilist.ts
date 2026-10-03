/**
 * AniList GraphQL transport. Kept out of the Svelte views on purpose: it is the only place that
 * knows the wire shape, so the views can work with the domain types from `$shared/types`.
 */

const ANILIST_ENDPOINT = "https://graphql.anilist.co/";

export interface AniListTitle {
    romaji: string | null;
    english: string | null;
    userPreferred: string | null;
    native: string | null;
}

/** AniList returns a partial date: any of the three parts can be null. */
export interface AniListFuzzyDate {
    year: number | null;
    month: number | null;
    day: number | null;
}

export interface AniListMediaNode {
    id: number | string;
    title: AniListTitle;
    format: string | null;
    type: string;
    status: string | null;
    description: string | null;
    averageScore: number | null;
    duration: number | null;
    episodes: number | null;
    chapters: number | null;
    volumes: number | null;
    coverImage: {
        extraLarge: string | null;
        large: string | null;
        medium: string | null;
    } | null;
    bannerImage: string | null;
    startDate: AniListFuzzyDate | null;
    endDate: AniListFuzzyDate | null;
    studios: { nodes: { name: string }[] } | null;
    staff: {
        edges: {
            role: string | null;
            node: { name: { full: string | null } | null } | null;
        }[];
    } | null;
}

export interface AniListRelationEdge {
    relationType: string;
    node: AniListMediaNode;
}

export interface AniListRecommendation {
    id: number | string;
    title: AniListTitle;
    coverImage: { large: string | null } | null;
    averageScore: number | null;
    type: string;
}

export interface AniListLookup {
    /** AniList numeric id. */
    id?: number;
    /** MyAnimeList numeric id, used when the source is MAL/Jikan/Shikimori. */
    idMal?: number;
    /** Always passed so a failed id lookup can fall back to a title search. */
    search: string;
    type: "ANIME" | "MANGA";
}

interface RelationsData {
    Media: { relations: { edges: AniListRelationEdge[] } | null } | null;
}

interface RecommendationsData {
    Media: {
        recommendations: {
            nodes: {
                mediaRecommendation: AniListRecommendation | null;
            }[];
        } | null;
    } | null;
}

const MEDIA_FIELDS = `
    id
    title { romaji english userPreferred native }
    format
    type
    status
    description(asHtml: false)
    averageScore
    duration
    episodes
    chapters
    volumes
    coverImage { extraLarge large medium }
    bannerImage
    startDate { year month day }
    endDate { year month day }
    studios(isMain: true) { nodes { name } }
    staff(perPage: 3) {
      edges {
        role
        node { name { full } }
      }
    }
`;

const RELATIONS_QUERY = `
    query ($id: Int, $idMal: Int, $search: String, $type: MediaType) {
      Media(id: $id, idMal: $idMal, search: $search, type: $type) {
        ${MEDIA_FIELDS}
        relations {
          edges {
            relationType
            node {
              ${MEDIA_FIELDS}
            }
          }
        }
      }
    }
`;

const RECOMMENDATIONS_QUERY = `
    query ($search: String) {
      Media(search: $search) {
        recommendations(page: 1, perPage: 10, sort: RATING_DESC) {
          nodes {
            mediaRecommendation {
              id
              title { romaji english userPreferred }
              coverImage { large }
              averageScore
              type
            }
          }
        }
      }
    }
`;

async function postGraphQl(
    query: string,
    variables: Record<string, unknown>,
): Promise<unknown | null> {
    try {
        const response = await fetch(ANILIST_ENDPOINT, {
            method: "POST",
            headers: { "Content-Type": "application/json" },
            body: JSON.stringify({ query, variables }),
        });
        if (!response.ok) return null;
        return (await response.json()) as unknown;
    } catch {
        return null;
    }
}

/**
 * AniList resolves `id`/`idMal` far more reliably than a title search, so the id wins. When the id
 * lookup misses, the same query is retried by title instead of returning an empty relation list.
 */
export async function fetchAniListRelations(
    lookup: AniListLookup,
): Promise<AniListRelationEdge[]> {
    const byId: Record<string, unknown> = { type: lookup.type };
    if (lookup.id) byId.id = lookup.id;
    else if (lookup.idMal) byId.idMal = lookup.idMal;
    else byId.search = lookup.search;

    let payload = await postGraphQl(RELATIONS_QUERY, byId);
    if (payload === null && (lookup.id || lookup.idMal)) {
        payload = await postGraphQl(RELATIONS_QUERY, {
            search: lookup.search,
            type: lookup.type,
        });
    }
    if (payload === null) return [];

    const data = (payload as { data?: RelationsData }).data;
    return data?.Media?.relations?.edges ?? [];
}

export async function fetchAniListRecommendations(
    search: string,
): Promise<AniListRecommendation[]> {
    const payload = await postGraphQl(RECOMMENDATIONS_QUERY, { search });
    if (payload === null) return [];

    const data = (payload as { data?: RecommendationsData }).data;
    return (
        data?.Media?.recommendations?.nodes
            ?.map((node) => node.mediaRecommendation)
            .filter((node): node is AniListRecommendation => node !== null) ?? []
    );
}
