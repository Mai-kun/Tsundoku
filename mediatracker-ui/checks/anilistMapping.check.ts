// Self-check for the AniList -> view-model mapping. Run: `npm run check:anilist-mapping`
// (node --experimental-strip-types). No framework, no fixtures, no network.
import assert from "node:assert/strict";
import {
    toRecommendationItem,
    toRelatedEntry,
} from "../src/widgets/media-detail/anilistMapping.ts";
import type {
    AniListMediaNode,
    AniListRecommendation,
    AniListRelationEdge,
} from "../src/shared/api/anilist.ts";

function node(overrides: Partial<AniListMediaNode> = {}): AniListMediaNode {
    return {
        id: 42,
        title: {
            romaji: "Berserk",
            english: "Berserk",
            userPreferred: "Berserk",
            native: "ベルセルク",
        },
        format: "TV",
        type: "ANIME",
        status: "RELEASING",
        description: "<p>Dark <b>fantasy</b>.</p>",
        averageScore: 82,
        duration: 24,
        episodes: 25,
        chapters: null,
        volumes: null,
        coverImage: { extraLarge: "x", large: "large.jpg", medium: "m.jpg" },
        bannerImage: "banner.jpg",
        startDate: { year: 1997, month: 4, day: 6 },
        endDate: { year: 2004, month: null, day: null },
        studios: { nodes: [{ name: "OLM" }] },
        staff: {
            edges: [
                { role: "Sound", node: { name: { full: "Some Composer" } } },
                { role: "Original Creator", node: { name: { full: "Kentaro Miura" } } },
            ],
        },
        ...overrides,
    };
}

const edge: AniListRelationEdge = { relationType: "PREQUEL", node: node() };

// 1. Score is AniList's 0..100 rescaled to the 0..10 scale the UI shows, rounded to one decimal.
{
    const entry = toRelatedEntry(edge);
    assert.equal(entry.score, 8.2, "82/10 rounded to 8.2");
    assert.deepEqual(
        entry.ratings,
        [{ source: "AniList", rating: 8.2 }],
        "a known score still produces a source badge",
    );
}
{
    const entry = toRelatedEntry({
        relationType: "OTHER",
        node: node({ averageScore: null }),
    });
    assert.equal(entry.score, null, "missing score stays null");
    assert.equal(entry.ratings, null, "no score means no badge, not a zero one");
}

// 2. HTML in the description is stripped; the synopsis column renders plain text.
{
    const entry = toRelatedEntry(edge);
    assert.equal(entry.description, "Dark fantasy.", "<p>/<b> removed and trimmed");
}

// 3. A partial end date must not borrow the start date's month/day.
{
    const entry = toRelatedEntry(edge);
    assert.equal(entry.releaseDate, "1997-04-06", "full start date");
    assert.equal(entry.endDate, "2004-01-01", "year-only end date pads to Jan 1");
}
{
    const entry = toRelatedEntry({
        relationType: "OTHER",
        node: node({ startDate: { year: null, month: null, day: null } }),
    });
    assert.equal(entry.releaseDate, null, "no year means no date, not 0001-01-01");
    assert.equal(entry.year, null, "year mirrors startDate.year");
}

// 4. Author picks the credited creator, not the first staff entry (sound composer here).
{
    const entry = toRelatedEntry(edge);
    assert.equal(entry.author, "Kentaro Miura", "role regex prefers Story & Art");
}
{
    const entry = toRelatedEntry({
        relationType: "OTHER",
        node: node({
            staff: { edges: [{ role: "Music", node: { name: { full: "Only Name" } } }] },
        }),
    });
    assert.equal(entry.author, "Only Name", "falls back to the first staff entry");
}
{
    const entry = toRelatedEntry({
        relationType: "OTHER",
        node: node({ staff: { edges: [] } }),
    });
    assert.equal(entry.author, null, "no staff at all");
}

// 5. Cover falls back large -> medium; manga type is detected from AniList's upper-case type.
{
    assert.equal(toRelatedEntry(edge).coverUrl, "large.jpg");
    assert.equal(
        toRelatedEntry({
            relationType: "ADAPTATION",
            node: node({ coverImage: { extraLarge: "x", large: null, medium: "m.jpg" } }),
        }).coverUrl,
        "m.jpg",
        "large missing falls back to medium",
    );
    assert.equal(
        toRelatedEntry({
            relationType: "ADAPTATION",
            node: node({ type: "MANGA" }),
        }).type,
        "manga",
        "MANGA maps to the manga view-model type",
    );
    assert.equal(toRelatedEntry(edge).externalSource, "AniList");
    assert.equal(toRelatedEntry(edge).id, "42", "numeric AniList id is stringified");
}

// 6. Recommendations share the title cascade and the score rescale.
{
    const rec: AniListRecommendation = {
        id: 7,
        title: { romaji: "Kokoro", english: null, userPreferred: "Kokoro", native: "心" },
        coverImage: { large: "cover.jpg" },
        averageScore: 75,
        type: "ANIME",
    };
    const item = toRecommendationItem(rec);
    assert.equal(item.title, "Kokoro", "english missing falls back to romaji");
    assert.equal(item.score, 7.5, "75/10");
    assert.equal(item.coverUrl, "cover.jpg");
    assert.equal(item.id, "7");
    assert.equal(
        toRecommendationItem({ ...rec, title: { romaji: null, english: null, userPreferred: null, native: "心" } })
            .title,
        "Title",
        "a fully untranslated title still renders a row",
    );
}

console.log("anilistMapping: all checks passed");
