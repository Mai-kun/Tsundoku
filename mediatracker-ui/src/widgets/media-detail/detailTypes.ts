import type { MediaItem } from "$shared/types";

export interface ProgressInfo {
    current: number;
    total: number | null;
    editable: boolean;
    label: string;
}

export interface SpecRow {
    label: string;
    value: string;
    isLink?: boolean;
}

export interface EpisodeRow {
    id: string;
    number: number;
    title: string;
    airDate: string | null;
    description: string | null;
    watched: boolean;
}

export interface RecommendationItem {
    id: string;
    title: string;
    coverUrl: string | null;
    score: number | null;
    type: string;
}

export interface RelatedEntry {
    id: string;
    title: string;
    originalTitle?: string | null;
    coverUrl: string | null;
    bannerUrl?: string | null;
    type: string;
    format?: string | null;
    year?: number | null;
    relationType?: string;
    rawRelationType?: string;
    score?: number | null;
    ratings?: { source: string; rating: number }[] | null;
    description?: string | null;
    episodes?: number | null;
    chapters?: number | null;
    volumes?: number | null;
    studio?: string | null;
    author?: string | null;
    romajiTitle?: string | null;
    duration?: number | null;
    releaseDate?: string | null;
    endDate?: string | null;
    releaseStatus?: string | null;
    externalSource?: string | null;
    localItem?: MediaItem;
}

export interface RatingBadge {
    source: string;
    score: number | null;
    votes?: number | null;
    /**
     * True when the source was actually asked and answered. The backend persists score 0 for
     * "queried, this source has no rating", so the two states must not be collapsed: reading a
     * known-absent rating as "missing" made every card open re-request the same external APIs.
     */
    queried?: boolean;
}

export interface RelationGroup {
    id: string;
    title: string;
    items: RelatedEntry[];
}

export interface TimelineEntry {
    id: string;
    title: string;
    coverUrl: string | null;
    year: number | null;
    formatDisplay: string;
    relationType: string;
    isCurrent: boolean;
    localItem?: MediaItem;
    rawItem?: RelatedEntry;
}

export type SubTab =
    | "overview"
    | "episodes"
    | "volumes"
    | "related"
    | "recommendations";

export type RelatedViewMode = "grouped" | "timeline" | "grid";