import { describe, it, expect } from "vitest";
import {
  findMatchingLocal,
  isRelatedMatch,
  normalizeTitle,
  stripMovieMarker,
} from "../relatedMatching";

describe("relatedMatching", () => {
  it("normalizes titles properly", () => {
    expect(normalizeTitle("Violet Evergarden: the Movie")).toBe("violetevergardenthemovie");
    expect(normalizeTitle("Вайолет Эвергарден. Фильм")).toBe("вайолетэвергарденфильм");
    expect(normalizeTitle("劇場版 ヴァイオレット・エヴァーガーデン")).toBe(
      "劇場版ヴァイオレットエヴァーガーデン",
    );
  });

  it("strips movie markers properly", () => {
    expect(stripMovieMarker("Violet Evergarden: the Movie")).toBe("Violet Evergarden:");
    expect(stripMovieMarker("Violet Evergarden Movie")).toBe("Violet Evergarden");
    expect(stripMovieMarker("Вайолет Эвергарден. Фильм")).toBe("Вайолет Эвергарден.");
  });

  it("matches local entities accurately without cross-matching TV vs Movie", () => {
    const violetTvShow: any = {
      id: "uuid-series",
      type: "tvshow",
      title: "Вайолет Эвергарден",
      status: 2,
      score: 10,
      isAnime: true,
      romajiTitle: "Violet Evergarden",
      externalId: "33352",
      externalSource: "Shikimori",
      franchiseId: null,
      franchiseOrder: null,
      createdAt: "",
      network: null,
      studio: "Kyoto Animation",
      totalEpisodesCount: 13,
      totalEpisodesWatched: 13,
      seasonsCount: 1,
      coverUrl: null,
      startedAt: null,
      finishedAt: null,
    };

    const violetMovie: any = {
      id: "uuid-movie",
      type: "movie",
      title: "Вайолет Эвергарден. Фильм",
      status: 2,
      score: 9,
      isAnime: true,
      romajiTitle: "Violet Evergarden Movie",
      externalId: "37987",
      externalSource: "Shikimori",
      franchiseId: null,
      franchiseOrder: null,
      createdAt: "",
      durationMinutes: 140,
      director: null,
      studio: "Kyoto Animation",
      coverUrl: null,
      startedAt: null,
      finishedAt: null,
    };

    const allMedia = [violetTvShow, violetMovie];

    const relMovie: any = {
      id: "103047",
      title: "Violet Evergarden: the Movie",
      romajiTitle: "Violet Evergarden Movie",
      originalTitle: "劇場版 ヴァイオレット・エヴァーガーデン",
      type: "anime",
      format: "MOVIE",
      coverUrl: null,
    };

    const relSeries: any = {
      id: "21827",
      title: "Violet Evergarden",
      romajiTitle: "Violet Evergarden",
      originalTitle: "ヴァイオレット・エヴァーガーデン",
      type: "anime",
      format: "TV",
      coverUrl: null,
    };

    const relGaiden: any = {
      id: "109121",
      title: "Violet Evergarden: Eternity and the Auto Memory Doll",
      romajiTitle: "Violet Evergarden Gaiden: Eien to Jidou Shuki Ningyou",
      type: "anime",
      format: "MOVIE",
      coverUrl: null,
    };

    expect(isRelatedMatch(relMovie, violetMovie)).toBe(true);
    expect(isRelatedMatch(relMovie, violetTvShow)).toBe(false);

    expect(isRelatedMatch(relSeries, violetTvShow)).toBe(true);
    expect(isRelatedMatch(relSeries, violetMovie)).toBe(false);

    expect(findMatchingLocal(relMovie, allMedia)?.id).toBe(violetMovie.id);
    expect(findMatchingLocal(relSeries, allMedia)?.id).toBe(violetTvShow.id);
    expect(findMatchingLocal(relGaiden, allMedia)).toBeUndefined();
  });
});
