// Self-check for the time budget calculator: verifies that media items fit slots according to
// duration, reading speed, and remaining progress. Run: `node --experimental-strip-types checks/timeBudget.check.ts`
import assert from "node:assert/strict";
import { evaluateTimeFit, formatTimeBudgetChip } from "../src/entities/media/model/timeBudget.ts";
import type { BookMedia, GameMedia, MangaMedia, MovieMedia, TvShowMedia } from "../src/shared/types/models.ts";

function createMovie(durationMinutes: number): MovieMedia {
    return {
        id: "movie-1",
        type: "movie",
        title: "Test Movie",
        status: 1,
        score: null,
        startedAt: null,
        finishedAt: null,
        coverUrl: null,
        createdAt: "2026-01-01T00:00:00Z",
        franchiseId: null,
        franchiseOrder: null,
        durationMinutes,
        director: null,
        isAnime: false,
        studio: null,
        romajiTitle: null,
    };
}

function createTvShow(opts: {
    durationMinutes?: number;
    isAnime?: boolean;
    totalEpisodesCount: number;
    totalEpisodesWatched: number;
}): TvShowMedia {
    return {
        id: "tv-1",
        type: "tvshow",
        title: "Test TV Show",
        status: 1,
        score: null,
        startedAt: null,
        finishedAt: null,
        coverUrl: null,
        createdAt: "2026-01-01T00:00:00Z",
        franchiseId: null,
        franchiseOrder: null,
        isAnime: opts.isAnime ?? false,
        studio: null,
        romajiTitle: null,
        network: null,
        seasonsCount: 1,
        totalEpisodesCount: opts.totalEpisodesCount,
        totalEpisodesWatched: opts.totalEpisodesWatched,
        durationMinutes: opts.durationMinutes,
    };
}

function createBook(currentPage: number, totalPages: number): BookMedia {
    return {
        id: "book-1",
        type: "book",
        title: "Test Book",
        status: 1,
        score: null,
        startedAt: null,
        finishedAt: null,
        coverUrl: null,
        createdAt: "2026-01-01T00:00:00Z",
        franchiseId: null,
        franchiseOrder: null,
        author: "Author",
        currentPage,
        totalPages,
    };
}

function createManga(currentChapter: number, totalChapters: number | null): MangaMedia {
    return {
        id: "manga-1",
        type: "manga",
        title: "Test Manga",
        status: 1,
        score: null,
        startedAt: null,
        finishedAt: null,
        coverUrl: null,
        createdAt: "2026-01-01T00:00:00Z",
        franchiseId: null,
        franchiseOrder: null,
        currentChapter,
        totalChapters,
        currentVolume: 1,
    };
}

function createGame(): GameMedia {
    return {
        id: "game-1",
        type: "game",
        title: "Test Game",
        status: 1,
        score: null,
        startedAt: null,
        finishedAt: null,
        coverUrl: null,
        createdAt: "2026-01-01T00:00:00Z",
        franchiseId: null,
        franchiseOrder: null,
        platform: "PC",
        hoursPlayed: 5,
    };
}

// 1. В слот 15 мин фильм на 120 мин и сериал с серией 45 мин НЕ попадают (fits === false),
//    а книга и манга (при 6 мин/гл -> 2 главы) попадают.
{
    const movie120 = createMovie(120);
    const movieRes = evaluateTimeFit(movie120, 15, 1.5, 6.0, "ru");
    assert.equal(movieRes.fits, false, "120 min movie should not fit into 15 min slot");

    const tv45 = createTvShow({ durationMinutes: 45, isAnime: false, totalEpisodesCount: 10, totalEpisodesWatched: 0 });
    const tvRes = evaluateTimeFit(tv45, 15, 1.5, 6.0, "ru");
    assert.equal(tvRes.fits, false, "45 min episode TV show should not fit into 15 min slot");

    const book = createBook(50, 300);
    const bookRes = evaluateTimeFit(book, 15, 1.5, 6.0, "ru");
    assert.equal(bookRes.fits, true, "Book should fit into 15 min slot (10 pages >= 5)");
    assert.equal(bookRes.sessionLabel, "За сессию: ~10 стр.");

    const manga = createManga(10, 50);
    const mangaRes = evaluateTimeFit(manga, 15, 1.5, 6.0, "ru");
    assert.equal(mangaRes.fits, true, "Manga should fit into 15 min slot (floor(15/6) = 2 chapters)");
    assert.equal(mangaRes.sessionLabel, "Успеете: ~2 гл.");
}

// 2. В слот 30 мин аниме с серией 24 мин попадает (1 эп.), а если осталась ровно 1 последняя серия (11/12),
//    выставляется canFinishNow === true.
{
    const animeOngoing = createTvShow({ durationMinutes: 24, isAnime: true, totalEpisodesCount: 12, totalEpisodesWatched: 5 });
    const ongoingRes = evaluateTimeFit(animeOngoing, 30, 1.5, 6.0, "ru");
    assert.equal(ongoingRes.fits, true, "24 min anime fits into 30 min slot");
    assert.equal(ongoingRes.canFinishNow, false, "5/12 anime cannot finish in 30 min");
    assert.equal(ongoingRes.sessionLabel, "Успеете: 1 эп. (~24 мин.)");

    const animeFinal = createTvShow({ durationMinutes: 24, isAnime: true, totalEpisodesCount: 12, totalEpisodesWatched: 11 });
    const finalRes = evaluateTimeFit(animeFinal, 30, 1.5, 6.0, "ru");
    assert.equal(finalRes.fits, true, "Final episode fits into 30 min slot");
    assert.equal(finalRes.canFinishNow, true, "1 episode left can finish now");
    assert.equal(finalRes.sessionLabel, "🔥 Добить финал: 1 эп. (~24 мин.)");
}

// 3. В слот 120 мин попадает фильм на 110 мин с canFinishNow === true.
{
    const movie110 = createMovie(110);
    const movieRes = evaluateTimeFit(movie110, 120, 1.5, 6.0, "ru");
    assert.equal(movieRes.fits, true, "110 min movie fits into 120 min slot");
    assert.equal(movieRes.canFinishNow, true, "Movie can finish now");
    assert.equal(movieRes.sessionLabel, "🔥 Целиком: 110 мин.");
}

// 4. Edge cases: Games, books finishing, and English locale
{
    const game = createGame();
    assert.equal(evaluateTimeFit(game, 15, 1.5, 6.0, "ru").fits, false, "Game does not fit in 15 min");
    assert.equal(evaluateTimeFit(game, 30, 1.5, 6.0, "ru").fits, true, "Game fits in 30 min");
    assert.equal(evaluateTimeFit(game, 30, 1.5, 6.0, "ru").sessionLabel, "Игровая сессия: 30 мин.");

    const almostDoneBook = createBook(195, 200); // 5 pages left -> 5 * 1.5 = 7.5 min <= 15 min
    const bookFinish = evaluateTimeFit(almostDoneBook, 15, 1.5, 6.0, "ru");
    assert.equal(bookFinish.canFinishNow, true, "5 pages left can finish in 15 min");
    assert.equal(bookFinish.sessionLabel, "🔥 Дочитать до конца: 5 стр. (~8 мин.)");

    const movieEn = evaluateTimeFit(createMovie(90), 90, 1.5, 6.0, "en");
    assert.equal(movieEn.sessionLabel, "🔥 Entire: 90 min");
}

// 5. Arbitrary custom time (40 min, 150 min) and formatTimeBudgetChip
{
    // Custom time 40 min
    const anime1EpLeft = createTvShow({ durationMinutes: 24, isAnime: true, totalEpisodesCount: 12, totalEpisodesWatched: 11 });
    const anime1Res = evaluateTimeFit(anime1EpLeft, 40, 1.5, 6.0, "ru");
    assert.equal(anime1Res.fits, true, "24 min anime fits in 40 min slot");
    assert.equal(anime1Res.canFinishNow, true, "1 episode left finishes in 40 min");

    const movie45 = createMovie(45);
    assert.equal(evaluateTimeFit(movie45, 40, 1.5, 6.0, "ru").fits, false, "45 min movie does not fit in 40 min slot");

    const game = createGame();
    assert.equal(evaluateTimeFit(game, 40, 1.5, 6.0, "ru").fits, true, "Game fits in 40 min slot (>= 30)");

    // Custom time 150 min (2.5 hours)
    const movie140 = createMovie(140);
    const movie140Res = evaluateTimeFit(movie140, 150, 1.5, 6.0, "ru");
    assert.equal(movie140Res.fits, true, "140 min movie fits in 150 min slot");
    assert.equal(movie140Res.canFinishNow, true, "140 min movie finishes in 150 min slot");

    // formatTimeBudgetChip tests
    assert.equal(formatTimeBudgetChip(15, "ru"), "15 м");
    assert.equal(formatTimeBudgetChip(15, "en"), "15m");
    assert.equal(formatTimeBudgetChip(40, "ru"), "40 м");
    assert.equal(formatTimeBudgetChip(40, "en"), "40m");
    assert.equal(formatTimeBudgetChip(60, "ru"), "1 ч");
    assert.equal(formatTimeBudgetChip(60, "en"), "1h");
    assert.equal(formatTimeBudgetChip(90, "ru"), "1.5 ч");
    assert.equal(formatTimeBudgetChip(90, "en"), "1.5h");
    assert.equal(formatTimeBudgetChip(120, "ru"), "2 ч");
    assert.equal(formatTimeBudgetChip(120, "en"), "2h");
    assert.equal(formatTimeBudgetChip(150, "ru"), "2.5 ч");
    assert.equal(formatTimeBudgetChip(150, "en"), "2.5h");
    assert.equal(formatTimeBudgetChip(75, "ru"), "1ч 15м");
    assert.equal(formatTimeBudgetChip(75, "en"), "1h 15m");
}

console.log("ok   time budget evaluateTimeFit checks passed");
