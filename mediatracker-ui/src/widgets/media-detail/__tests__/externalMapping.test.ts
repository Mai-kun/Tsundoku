import { describe, it, expect } from "vitest";
import { toRelatedEntry } from "../externalMapping";
import type { ExternalMedia, ExternalRelation } from "../../../shared/types/models";

function media(overrides: Partial<ExternalMedia> = {}): ExternalMedia {
  return {
    externalId: "42",
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

function relation(
  overrides: Partial<ExternalMedia> = {},
  relationType = "PREQUEL",
): ExternalRelation {
  return { relationType, media: media(overrides) };
}

describe("externalMapping", () => {
  it("survives raw relation type untouched", () => {
    const entry = toRelatedEntry(relation());
    expect(entry.rawRelationType).toBe("PREQUEL");
    expect(entry.id).toBe("42");
    expect(entry.type).toBe("anime");
  });

  it("handles known and missing ratings correctly", () => {
    const entry = toRelatedEntry(relation());
    expect(entry.score).toBe(8.2);
    expect(entry.ratings).toEqual([{ source: "AniList", rating: 8.2 }]);

    const unrated = toRelatedEntry(relation({ rating: null }));
    expect(unrated.score).toBeNull();
    expect(unrated.ratings).toBeNull();
  });

  it("normalises dates and counts", () => {
    const entry = toRelatedEntry(relation());
    expect(entry.releaseDate).toBe("1997-04-06");
    expect(entry.endDate).toBe("2004");
    expect(entry.year).toBe(1997);
    expect(entry.episodes).toBe(25);
  });

  it("leaves missing year null", () => {
    const entry = toRelatedEntry(relation({ releaseYear: null, releaseDate: undefined }));
    expect(entry.year).toBeNull();
    expect(entry.releaseDate).toBeNull();
  });

  it("preserves format", () => {
    expect(toRelatedEntry(relation()).format).toBe("TV");
    expect(toRelatedEntry(relation({ type: "manga", format: "MANGA" }, "ADAPTATION")).format).toBe(
      "MANGA",
    );
  });

  it("falls back to default title when blank", () => {
    expect(toRelatedEntry(relation({ title: "" })).title).toBe("Title");
  });
});
