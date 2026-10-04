// Self-check for the series-wide episode stepper: a decrement must cross season boundaries all the
// way down to a flat 0, never stopping at a season edge. Run: `npm run check:series-step`
// (node --experimental-strip-types). No framework, no fixtures, no network.
import assert from "node:assert/strict";
import { nextSeriesEpisodeStep } from "../src/entities/media/model/seriesStep.ts";
import type { TvSeason } from "../src/shared/types/models.ts";

function season(
    seasonNumber: number,
    currentEpisode: number,
    totalEpisodes: number,
): TvSeason {
    return {
        id: `s${seasonNumber}`,
        seasonNumber,
        title: `Season ${seasonNumber}`,
        coverUrl: null,
        currentEpisode,
        totalEpisodes,
        status: 1,
        score: null,
        notes: null,
        airDate: null,
        tvShowId: "show",
    };
}

// Two seasons: S1 7/7 done, S2 sitting at 0/13. This is the exact shape that used to deadlock.
const series = [season(1, 7, 7), season(2, 0, 13)];

// 1. Decrement at the S1/S2 boundary rolls back into S1 instead of stopping at 7.
{
    const step = nextSeriesEpisodeStep(series, -1);
    assert.deepEqual(step, { seasonId: "s1", currentEpisode: 6 }, "rollback crossed into S1");
}

// 2. One decrement per press, continuing down through S1 until it is empty.
{
    let seasons = [season(1, 7, 7), season(2, 0, 13)];
    for (let expected = 6; expected >= 0; expected--) {
        const step = nextSeriesEpisodeStep(seasons, -1);
        assert.equal(step?.currentEpisode, expected, `S1 rolled back to ${expected}`);
        seasons = [season(1, step!.currentEpisode, 7), season(2, 0, 13)];
    }
}

// 3. The floor is 0 for the WHOLE series: a further press is a no-op, not a negative or a rewind.
{
    assert.equal(
        nextSeriesEpisodeStep([season(1, 0, 7), season(2, 0, 13)], -1),
        null,
        "no step left once every season is at 0",
    );
}

// 4. Out-of-order seasons must not matter — the walk sorts by seasonNumber first.
{
    assert.deepEqual(
        nextSeriesEpisodeStep([season(2, 0, 13), season(1, 7, 7)], -1),
        { seasonId: "s1", currentEpisode: 6 },
        "seasons are walked in season order, not array order",
    );
}

// 5. Increment still advances forward: S1 is full, so the press lands on S2.
{
    assert.deepEqual(
        nextSeriesEpisodeStep([season(1, 7, 7), season(2, 3, 13)], 1),
        { seasonId: "s2", currentEpisode: 4 },
        "increment skips the finished season",
    );
}

// 6. Increment stops at the last episode of the last season.
{
    assert.equal(
        nextSeriesEpisodeStep([season(1, 7, 7), season(2, 13, 13)], 1),
        null,
        "a finished series takes no further increment",
    );
}

// 7. A season with an unknown episode count is still steppable (total <= 0 means uncapped).
{
    assert.deepEqual(
        nextSeriesEpisodeStep([season(1, 4, 0)], -1),
        { seasonId: "s1", currentEpisode: 3 },
        "seasons without a known total still roll back",
    );
}

console.log("ok   series step crosses season boundaries down to 0");