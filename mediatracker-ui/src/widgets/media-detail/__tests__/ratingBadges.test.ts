import { describe, expect, it } from "vitest";
import { buildRatingBadges } from "../ratingBadges";
import type { SourceInfo } from "$shared/types";

const mockSources: SourceInfo[] = [
  {
    id: "openlibrary",
    name: "OpenLibrary",
    description: "",
    mediaTypes: ["book"],
    baseAddress: "https://openlibrary.org/",
    isEnabled: true,
    isDefault: true,
    priority: 1,
  },
  {
    id: "livelib",
    name: "LiveLib",
    description: "",
    mediaTypes: ["book"],
    baseAddress: "https://www.livelib.ru/",
    isEnabled: true,
    isDefault: false,
    priority: 2,
  },
  {
    id: "anilist",
    name: "AniList",
    description: "",
    mediaTypes: ["anime", "manga"],
    baseAddress: "https://graphql.anilist.co",
    isEnabled: true,
    isDefault: true,
    priority: 1,
  },
  {
    id: "shikimori",
    name: "Shikimori",
    description: "",
    mediaTypes: ["anime", "manga"],
    baseAddress: "https://shikimori.one",
    isEnabled: true,
    isDefault: false,
    priority: 2,
  },
];

describe("buildRatingBadges with linkedSources", () => {
  it("renders only linked sources and excludes unlinked ones", () => {
    const badges = buildRatingBadges({
      ratings: [
        { source: "LiveLib", rating: 8.4, votes: 120 },
        { source: "AniList", rating: 7.5, votes: 300 },
      ],
      category: "book",
      availableSources: mockSources,
      linkedSources: ["openlibrary", "livelib"],
    });

    const sources = badges.map((b) => b.source.toLowerCase());
    expect(sources).toContain("livelib");
    expect(sources).toContain("openlibrary");
    expect(sources).not.toContain("anilist");
    expect(sources).not.toContain("shikimori");

    const livelibBadge = badges.find((b) => b.source.toLowerCase() === "livelib");
    expect(livelibBadge?.score).toBe(8.4);

    const openLibraryBadge = badges.find((b) => b.source.toLowerCase() === "openlibrary");
    expect(openLibraryBadge?.score).toBeNull();
  });

  it("renders no badges if no sources are linked", () => {
    const badges = buildRatingBadges({
      ratings: [{ source: "AniList", rating: 8.0 }],
      category: "book",
      availableSources: mockSources,
      linkedSources: [],
    });

    expect(badges).toHaveLength(0);
  });
});
