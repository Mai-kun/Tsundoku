import { describe, it, expect } from "vitest";
import { nextSeriesEpisodeStep } from "../seriesStep";
import type { TvSeason } from "$shared/types/models";

function season(seasonNumber: number, currentEpisode: number, totalEpisodes: number): TvSeason {
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

describe("seriesStep", () => {
  it("rolls back across season boundary from S2 into S1", () => {
    const series = [season(1, 7, 7), season(2, 0, 13)];
    const step = nextSeriesEpisodeStep(series, -1);
    expect(step).toEqual({ seasonId: "s1", currentEpisode: 6 });
  });

  it("steps back through S1 down to zero", () => {
    let seasons = [season(1, 7, 7), season(2, 0, 13)];
    for (let expected = 6; expected >= 0; expected--) {
      const step = nextSeriesEpisodeStep(seasons, -1);
      expect(step?.currentEpisode).toBe(expected);
      seasons = [season(1, step!.currentEpisode, 7), season(2, 0, 13)];
    }
  });

  it("returns null once every season is at zero", () => {
    expect(nextSeriesEpisodeStep([season(1, 0, 7), season(2, 0, 13)], -1)).toBeNull();
  });

  it("sorts by seasonNumber before walking", () => {
    const step = nextSeriesEpisodeStep([season(2, 0, 13), season(1, 7, 7)], -1);
    expect(step).toEqual({ seasonId: "s1", currentEpisode: 6 });
  });

  it("advances forward, skipping finished seasons", () => {
    const step = nextSeriesEpisodeStep([season(1, 7, 7), season(2, 3, 13)], 1);
    expect(step).toEqual({ seasonId: "s2", currentEpisode: 4 });
  });

  it("returns null when all episodes in all seasons are watched", () => {
    expect(nextSeriesEpisodeStep([season(1, 7, 7), season(2, 13, 13)], 1)).toBeNull();
  });

  it("handles seasons with unknown (uncapped) episode counts", () => {
    const step = nextSeriesEpisodeStep([season(1, 4, 0)], -1);
    expect(step).toEqual({ seasonId: "s1", currentEpisode: 3 });
  });
});
