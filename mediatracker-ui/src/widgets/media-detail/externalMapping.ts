import type { ExternalRelation } from "$shared/types";
import type { RelatedEntry } from "./detailTypes";

/**
 * Server relation shape → view model.
 *
 * The provider call, the GraphQL in it and the field normalisation all happen on the server now. What
 * stays here is the view-model shaping, deliberately free of i18n — the caller supplies the localised
 * `relationType` label, which is what keeps this directly runnable under
 * `checks/externalMapping.check.ts` with no app state behind it.
 */
export function toRelatedEntry(relation: ExternalRelation): RelatedEntry {
  const media = relation.media;
  const score = media.rating ?? null;

  return {
    id: String(media.externalId),
    rawRelationType: relation.relationType,
    title: media.title || "Title",
    originalTitle: media.originalTitle ?? null,
    romajiTitle: media.romajiTitle ?? null,
    coverUrl: media.coverUrl ?? null,
    type: media.type,
    format: media.format ?? null,
    year: media.releaseYear ?? null,
    releaseDate: media.releaseDate ?? null,
    endDate: media.endDate ?? null,
    releaseStatus: media.releaseStatus ?? null,
    score,
    ratings: score && media.externalSource ? [{ source: media.externalSource, rating: score }] : null,
    description: media.description ?? null,
    duration: media.runtimeMinutes ?? null,
    episodes: media.totalCount ?? null,
    chapters: media.chapters ?? null,
    volumes: media.volumes ?? null,
    studio: media.studio ?? null,
    author: media.author ?? null,
    externalSource: media.externalSource ?? null,
  };
}