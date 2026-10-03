import type {
    AniListFuzzyDate,
    AniListMediaNode,
    AniListRecommendation,
    AniListRelationEdge,
} from "$shared/api/anilist";
import type { RecommendationItem, RelatedEntry } from "./detailTypes";

function toIsoDate(date: AniListFuzzyDate | null): string | null {
    if (!date?.year) return null;
    const year = String(date.year).padStart(4, "0");
    const month = String(date.month ?? 1).padStart(2, "0");
    const day = String(date.day ?? 1).padStart(2, "0");
    return `${year}-${month}-${day}`;
}

function stripHtml(value: string | null): string | null {
    if (!value) return null;
    const text = value.replace(/<[^>]*>/g, "").trim();
    return text ? text : null;
}

function toScore(averageScore: number | null): number | null {
    return typeof averageScore === "number"
        ? parseFloat((averageScore / 10).toFixed(1))
        : null;
}

function readAuthor(node: AniListMediaNode): string | null {
    const edges = node.staff?.edges ?? [];
    const credited = edges.find((edge) =>
        /story|art|original|author/i.test(edge?.role ?? ""),
    );
    return credited?.node?.name?.full ?? edges[0]?.node?.name?.full ?? null;
}

/**
 * Pure AniList → view-model mapping. Deliberately free of i18n and of the network so it can be
 * exercised directly by checks/anilistMapping.check.ts; the caller supplies the localised
 * `relationType` label.
 */
export function toRelatedEntry(edge: AniListRelationEdge): RelatedEntry {
    const node = edge.node;
    const score = toScore(node?.averageScore);

    return {
        id: String(node?.id),
        rawRelationType: edge.relationType,
        title:
            node?.title?.english ||
            node?.title?.romaji ||
            node?.title?.userPreferred ||
            "Title",
        originalTitle: node?.title?.native ?? null,
        romajiTitle: node?.title?.romaji ?? null,
        coverUrl: node?.coverImage?.large ?? node?.coverImage?.medium ?? null,
        bannerUrl: node?.bannerImage ?? null,
        format: node?.format ?? null,
        type: node?.type?.toLowerCase() === "manga" ? "manga" : "anime",
        year: node?.startDate?.year ?? null,
        releaseDate: toIsoDate(node?.startDate ?? null),
        endDate: toIsoDate(node?.endDate ?? null),
        releaseStatus: node?.status ?? null,
        score,
        ratings: score ? [{ source: "AniList", rating: score }] : null,
        description: stripHtml(node?.description ?? null),
        duration: typeof node?.duration === "number" ? node.duration : null,
        episodes: node?.episodes ?? null,
        chapters: node?.chapters ?? null,
        volumes: node?.volumes ?? null,
        studio: node?.studios?.nodes?.[0]?.name ?? null,
        author: readAuthor(node),
        externalSource: "AniList",
    };
}

export function toRecommendationItem(
    node: AniListRecommendation,
): RecommendationItem {
    return {
        id: String(node.id),
        title:
            node.title?.english ||
            node.title?.romaji ||
            node.title?.userPreferred ||
            "Title",
        coverUrl: node.coverImage?.large ?? null,
        score:
            typeof node.averageScore === "number" ? node.averageScore / 10 : null,
        type: node.type?.toLowerCase() === "manga" ? "manga" : "anime",
    };
}
