import assert from "node:assert/strict";
import {
    getCriteriaAxes,
    parseDetailedScore,
    serializeDetailedScore,
    computeDetailedAverage,
    type CriterionKey,
} from "../src/entities/media/model/detailedScore.ts";

// 1. Check criteria axes per media type
{
    const gameAxes = getCriteriaAxes({ type: "game" });
    const gameKeys = gameAxes.map((a) => a.key);
    assert.equal(gameAxes.length, 5, "game has 5 axes");
    assert.ok(gameKeys.includes("gameplay"), "game contains gameplay axis");
    assert.ok(!gameKeys.includes("writing"), "game does NOT contain writing axis");
    assert.ok(gameKeys.includes("story"), "game contains story axis");
    assert.ok(gameKeys.includes("visuals"), "game contains visuals axis");
    assert.ok(gameKeys.includes("sound"), "game contains sound axis");
    assert.ok(gameKeys.includes("enjoyment"), "game contains enjoyment axis");

    const bookAxes = getCriteriaAxes({ type: "book" });
    const bookKeys = bookAxes.map((a) => a.key);
    assert.equal(bookAxes.length, 5, "book has 5 axes");
    assert.ok(bookKeys.includes("writing"), "book contains writing axis");
    assert.ok(!bookKeys.includes("sound"), "book does NOT contain sound axis");
    assert.ok(bookKeys.includes("story"), "book contains story axis");
    assert.ok(bookKeys.includes("characters"), "book contains characters axis");
    assert.ok(bookKeys.includes("pacing"), "book contains pacing axis");
    assert.ok(bookKeys.includes("enjoyment"), "book contains enjoyment axis");

    const mangaAxes = getCriteriaAxes({ type: "manga" });
    const mangaKeys = mangaAxes.map((a) => a.key);
    assert.equal(mangaAxes.length, 5, "manga has 5 axes");
    assert.ok(mangaKeys.includes("visuals"), "manga contains visuals (art) axis");
    assert.ok(!mangaKeys.includes("sound"), "manga does NOT contain sound axis");
    assert.ok(mangaKeys.includes("story"), "manga contains story axis");
    assert.ok(mangaKeys.includes("characters"), "manga contains characters axis");
    assert.ok(mangaKeys.includes("pacing"), "manga contains pacing axis");
    assert.ok(mangaKeys.includes("enjoyment"), "manga contains enjoyment axis");

    const animeAxes = getCriteriaAxes({ type: "anime" });
    const animeKeys = animeAxes.map((a) => a.key);
    assert.equal(animeAxes.length, 5, "anime has 5 axes");
    assert.ok(animeKeys.includes("story"), "anime contains story axis");
    assert.ok(animeKeys.includes("visuals"), "anime contains visuals axis");
    assert.ok(animeKeys.includes("characters"), "anime contains characters axis");
    assert.ok(animeKeys.includes("sound"), "anime contains sound axis");
    assert.ok(animeKeys.includes("pacing"), "anime contains pacing axis");

    const movieAnimeAxes = getCriteriaAxes({ type: "movie", isAnime: true });
    assert.deepEqual(movieAnimeAxes, animeAxes, "movie with isAnime gets screen axes");
}

// 2. Check parseDetailedScore
{
    assert.deepEqual(parseDetailedScore(null), {}, "null returns empty map");
    assert.deepEqual(parseDetailedScore(undefined), {}, "undefined returns empty map");
    assert.deepEqual(parseDetailedScore(""), {}, "empty string returns empty map");
    assert.deepEqual(parseDetailedScore("   "), {}, "whitespace returns empty map");
    assert.deepEqual(parseDetailedScore("not-valid-json"), {}, "invalid json returns empty map");
    assert.deepEqual(parseDetailedScore("[]"), {}, "array json returns empty map");
    assert.deepEqual(parseDetailedScore("42"), {}, "number json returns empty map");

    const validJson = JSON.stringify({
        story: 9,
        visuals: 8,
        characters: 10,
        sound: 7,
        pacing: 6,
    });
    assert.deepEqual(
        parseDetailedScore(validJson),
        { story: 9, visuals: 8, characters: 10, sound: 7, pacing: 6 },
        "parses valid detailed score correctly",
    );

    const dirtyJson = JSON.stringify({
        story: 9,
        gameplay: 0, // out of range (< 1)
        writing: 11, // out of range (> 10)
        invalidKey: 8, // unknown key
        sound: "good", // not a number
        enjoyment: 8.2, // round to 8
    });
    assert.deepEqual(
        parseDetailedScore(dirtyJson),
        { story: 9, enjoyment: 8 },
        "filters invalid entries and clamps/rounds numbers",
    );
}

// 3. Check serializeDetailedScore
{
    assert.equal(serializeDetailedScore({}), null, "empty map serializes to null");
    assert.equal(
        serializeDetailedScore({ unknownKey: 5 } as Record<string, number>),
        null,
        "map with only invalid keys serializes to null",
    );
    assert.equal(
        serializeDetailedScore({ story: 0, visuals: 12 } as Record<string, number>),
        null,
        "map with only out-of-range scores serializes to null",
    );

    const serialized = serializeDetailedScore({ story: 9, visuals: 8 });
    assert.equal(
        serialized,
        JSON.stringify({ story: 9, visuals: 8 }),
        "serializes valid map to JSON",
    );
}

// 4. Check computeDetailedAverage
{
    assert.equal(computeDetailedAverage({}), null, "empty map returns null average");

    // Exact example from prompt: 9, 8, 9, 8, 8 -> exact: 8.4, rounded: 8
    const sample: Partial<Record<CriterionKey, number>> = {
        story: 9,
        visuals: 8,
        characters: 9,
        sound: 8,
        pacing: 8,
    };
    const avg = computeDetailedAverage(sample);
    assert.ok(avg !== null, "average is computed");
    assert.equal(avg.exact, 8.4, "exact average is 8.4");
    assert.equal(avg.rounded, 8, "rounded average is 8");
    assert.equal(avg.count, 5, "count is 5");

    // Single axis
    const single = computeDetailedAverage({ gameplay: 7 });
    assert.deepEqual(single, { exact: 7, rounded: 7, count: 1 }, "single axis average works");

    // Two axes: (9 + 10) / 2 = 9.5 -> exact: 9.5, rounded: 10
    const two = computeDetailedAverage({ story: 9, enjoyment: 10 });
    assert.deepEqual(two, { exact: 9.5, rounded: 10, count: 2 }, "rounding half-up works");
}

console.log("detailedScore.check: all checks passed!");
