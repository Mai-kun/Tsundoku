// Self-check for the server relation -> view-model mapping. Run: `npm run check:external-mapping`
// (node --experimental-strip-types). No framework, no fixtures, no network.
import assert from "node:assert/strict";
import { toRelatedEntry } from "../src/widgets/media-detail/externalMapping.ts";
import type { ExternalMedia, ExternalRelation } from "../src/shared/types/models.ts";

function media(overrides: Partial<ExternalMedia> = {}): ExternalMedia {
  return {
    externalId: 42,
    externalSource: "AniList",
    title: "Berserk",
    originalTitle: "ベルセルク",
    romajiTitle: "Berserk",
    coverUrl: "large.jpg",
    description: "Dark fantasy.",
    releaseYear: 1997,
    releaseDate: "1997-04-06",
    endDate: "2004",
    releaseStatus: "RELEASED",
    format: "TV",
    runtimeMinutes: 24,
    type: "anime",
    author: "Kentaro Miura",
    studio: "OLM",
    totalCount: 25,
    rating: 8.2,
    platform: null,
    ...overrides,
  };
}

function relation(overrides: Partial<ExternalMedia> = {}, relationType = "PREQUEL"): ExternalRelation {
  return { relationType, media: media(overrides) };
}

// 1. The raw relation type survives untouched; the tab groups on it (SEQUEL/PREQUEL, SIDE_STORY...).
{
  const entry = toRelatedEntry(relation());
  assert.equal(entry.rawRelationType, "PREQUEL");
  assert.equal(entry.id, "42", "the provider id is stringified");
  assert.equal(entry.type, "anime");
}

// 2. A known score produces a source badge; a missing one produces neither score nor badge, so an
//    unrated title is not rendered as a zero.
{
  const entry = toRelatedEntry(relation());
  assert.equal(entry.score, 8.2);
  assert.deepEqual(entry.ratings, [{ source: "AniList", rating: 8.2 }]);

  const unrated = toRelatedEntry(relation({ rating: null }));
  assert.equal(unrated.score, null, "missing score stays null");
  assert.equal(unrated.ratings, null, "no score means no badge, not a zero one");
}

// 3. Dates and counters are passed through as the server normalised them: a year-only end date stays
//    year-only rather than being padded into a fake 1 January.
{
  const entry = toRelatedEntry(relation());
  assert.equal(entry.releaseDate, "1997-04-06");
  assert.equal(entry.endDate, "2004", "the server already shortened the partial date");
  assert.equal(entry.year, 1997, "year mirrors releaseYear");
  assert.equal(entry.episodes, 25, "totalCount maps to the episode count");
}

// 4. A missing year stays null rather than becoming 0001.
{
  const entry = toRelatedEntry(relation({ releaseYear: null, releaseDate: undefined }));
  assert.equal(entry.year, null);
  assert.equal(entry.releaseDate, null);
}

// 5. Format is carried through: the tab uses it to label a manga adaptation.
{
  assert.equal(toRelatedEntry(relation()).format, "TV");
  assert.equal(
    toRelatedEntry(relation({ type: "manga", format: "MANGA" }, "ADAPTATION")).format,
    "MANGA",
  );
}

// 6. A blank title still yields a renderable row instead of an empty card.
{
  assert.equal(toRelatedEntry(relation({ title: "" })).title, "Title");
}

console.log("externalMapping: all checks passed");