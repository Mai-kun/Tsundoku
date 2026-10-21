import assert from "node:assert/strict";
import {
    findMatchingLocal,
    isRelatedMatch,
    normalizeTitle,
    stripMovieMarker,
} from "../src/widgets/media-detail/relatedMatching";

// 1. normalizeTitle
assert.equal(normalizeTitle("Violet Evergarden: the Movie"), "violetevergardenthemovie");
assert.equal(normalizeTitle("Вайолет Эвергарден. Фильм"), "вайолетэвергарденфильм");
assert.equal(normalizeTitle("劇場版 ヴァイオレット・エヴァーガーデン"), "劇場版ヴァイオレットエヴァーガーデン");

// 2. stripMovieMarker
assert.equal(stripMovieMarker("Violet Evergarden: the Movie"), "Violet Evergarden:");
assert.equal(stripMovieMarker("Violet Evergarden Movie"), "Violet Evergarden");
assert.equal(stripMovieMarker("Вайолет Эвергарден. Фильм"), "Вайолет Эвергарден.");

// 3. Violet Evergarden library match
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

// Relation A: Violet Evergarden: the Movie (AniList)
const relMovie: any = {
    id: "103047",
    title: "Violet Evergarden: the Movie",
    romajiTitle: "Violet Evergarden Movie",
    originalTitle: "劇場版 ヴァイオレット・エヴァーガーデン",
    type: "anime",
    format: "MOVIE",
    coverUrl: null,
};

// Relation B: Violet Evergarden TV Series (AniList)
const relSeries: any = {
    id: "21827",
    title: "Violet Evergarden",
    romajiTitle: "Violet Evergarden",
    originalTitle: "ヴァイオレット・エヴァーガーデン",
    type: "anime",
    format: "TV",
    coverUrl: null,
};

// Relation C: Gaiden
const relGaiden: any = {
    id: "109121",
    title: "Violet Evergarden: Eternity and the Auto Memory Doll",
    romajiTitle: "Violet Evergarden Gaiden: Eien to Jidou Shuki Ningyou",
    type: "anime",
    format: "MOVIE",
    coverUrl: null,
};

// Verify relMovie matches violetMovie and NOT violetTvShow
assert.equal(isRelatedMatch(relMovie, violetMovie), true, "relMovie should match violetMovie");
assert.equal(isRelatedMatch(relMovie, violetTvShow), false, "relMovie must NOT match violetTvShow");

// Verify relSeries matches violetTvShow and NOT violetMovie
assert.equal(isRelatedMatch(relSeries, violetTvShow), true, "relSeries should match violetTvShow");
assert.equal(isRelatedMatch(relSeries, violetMovie), false, "relSeries must NOT match violetMovie");

// Verify findMatchingLocal
const matchedMovie = findMatchingLocal(relMovie, allMedia);
assert.equal(matchedMovie?.id, violetMovie.id, "findMatchingLocal should resolve violetMovie");

const matchedSeries = findMatchingLocal(relSeries, allMedia);
assert.equal(matchedSeries?.id, violetTvShow.id, "findMatchingLocal should resolve violetTvShow");

const matchedGaiden = findMatchingLocal(relGaiden, allMedia);
assert.equal(matchedGaiden, undefined, "relGaiden is not in library, should be undefined");

console.log("ALL RELATED MATCHING CHECKS PASSED!");
