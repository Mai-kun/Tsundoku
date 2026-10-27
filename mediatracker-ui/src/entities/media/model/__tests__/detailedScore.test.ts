import { describe, it, expect } from "vitest";
import {
  getCriteriaAxes,
  parseDetailedScore,
  serializeDetailedScore,
  computeDetailedAverage,
  type CriterionKey,
} from "../detailedScore";

describe("detailedScore", () => {
  it("checks criteria axes per media type", () => {
    const gameAxes = getCriteriaAxes({ type: "game" });
    const gameKeys = gameAxes.map((a) => a.key);
    expect(gameAxes.length).toBe(5);
    expect(gameKeys).toContain("gameplay");
    expect(gameKeys).not.toContain("writing");
    expect(gameKeys).toContain("story");
    expect(gameKeys).toContain("visuals");
    expect(gameKeys).toContain("sound");
    expect(gameKeys).toContain("enjoyment");

    const bookAxes = getCriteriaAxes({ type: "book" });
    const bookKeys = bookAxes.map((a) => a.key);
    expect(bookAxes.length).toBe(5);
    expect(bookKeys).toContain("writing");
    expect(bookKeys).not.toContain("sound");
    expect(bookKeys).toContain("story");
    expect(bookKeys).toContain("characters");
    expect(bookKeys).toContain("pacing");
    expect(bookKeys).toContain("enjoyment");

    const mangaAxes = getCriteriaAxes({ type: "manga" });
    const mangaKeys = mangaAxes.map((a) => a.key);
    expect(mangaAxes.length).toBe(5);
    expect(mangaKeys).toContain("visuals");
    expect(mangaKeys).not.toContain("sound");

    const animeAxes = getCriteriaAxes({ type: "anime" });
    const animeKeys = animeAxes.map((a) => a.key);
    expect(animeAxes.length).toBe(5);
    expect(animeKeys).toContain("story");
    expect(animeKeys).toContain("visuals");
    expect(animeKeys).toContain("characters");
    expect(animeKeys).toContain("sound");
    expect(animeKeys).toContain("pacing");

    const movieAnimeAxes = getCriteriaAxes({ type: "movie", isAnime: true });
    expect(movieAnimeAxes).toEqual(animeAxes);
  });

  it("parses detailed score JSON with clamping, filtering, and default fallbacks", () => {
    expect(parseDetailedScore(null)).toEqual({});
    expect(parseDetailedScore(undefined)).toEqual({});
    expect(parseDetailedScore("")).toEqual({});
    expect(parseDetailedScore("   ")).toEqual({});
    expect(parseDetailedScore("not-valid-json")).toEqual({});
    expect(parseDetailedScore("[]")).toEqual({});
    expect(parseDetailedScore("42")).toEqual({});

    const validJson = JSON.stringify({
      story: 9,
      visuals: 8,
      characters: 10,
      sound: 7,
      pacing: 6,
    });
    expect(parseDetailedScore(validJson)).toEqual({
      story: 9,
      visuals: 8,
      characters: 10,
      sound: 7,
      pacing: 6,
    });

    const dirtyJson = JSON.stringify({
      story: 9,
      gameplay: 0,
      writing: 11,
      invalidKey: 8,
      sound: "good",
      enjoyment: 8.2,
    });
    expect(parseDetailedScore(dirtyJson)).toEqual({ story: 9, enjoyment: 8 });
  });

  it("serializes detailed score dictionary back to JSON", () => {
    expect(serializeDetailedScore({})).toBeNull();
    expect(serializeDetailedScore({ unknownKey: 5 } as Record<string, number>)).toBeNull();
    expect(serializeDetailedScore({ story: 0, visuals: 12 } as Record<string, number>)).toBeNull();

    const serialized = serializeDetailedScore({ story: 9, visuals: 8 });
    expect(serialized).toBe(JSON.stringify({ story: 9, visuals: 8 }));
  });

  it("computes detailed average with exact and rounded results", () => {
    expect(computeDetailedAverage({})).toBeNull();

    const sample: Partial<Record<CriterionKey, number>> = {
      story: 9,
      visuals: 8,
      characters: 9,
      sound: 8,
      pacing: 8,
    };
    const avg = computeDetailedAverage(sample);
    expect(avg).not.toBeNull();
    expect(avg!.exact).toBe(8.4);
    expect(avg!.rounded).toBe(8);
    expect(avg!.count).toBe(5);

    const single = computeDetailedAverage({ gameplay: 7 });
    expect(single).toEqual({ exact: 7, rounded: 7, count: 1 });

    const two = computeDetailedAverage({ story: 9, enjoyment: 10 });
    expect(two).toEqual({ exact: 9.5, rounded: 10, count: 2 });
  });
});
