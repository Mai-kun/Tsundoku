import 'package:flutter_test/flutter_test.dart';
import 'package:tsundoku_flutter/entities/media/model/series_step.dart';
import 'package:tsundoku_flutter/shared/types/models.dart';

TvSeason season(int seasonNumber, int currentEpisode, int totalEpisodes) {
  return TvSeason.fromJson({
    'id': 's$seasonNumber',
    'seasonNumber': seasonNumber,
    'title': 'Season $seasonNumber',
    'coverUrl': null,
    'currentEpisode': currentEpisode,
    'totalEpisodes': totalEpisodes,
    'status': 1,
    'score': null,
    'notes': null,
    'airDate': null,
    'tvShowId': 'show',
  });
}

/// Прямой перенос vitest-кейсов `seriesStep.test.ts`.
void main() {
  test('rolls back across season boundary from S2 into S1', () {
    final step = nextSeriesEpisodeStep([season(1, 7, 7), season(2, 0, 13)], -1);
    expect(step, const SeriesEpisodeStep(seasonId: 's1', currentEpisode: 6));
  });

  test('steps back through S1 down to zero', () {
    var seasons = [season(1, 7, 7), season(2, 0, 13)];
    for (var expected = 6; expected >= 0; expected--) {
      final step = nextSeriesEpisodeStep(seasons, -1)!;
      expect(step.currentEpisode, expected);
      seasons = [season(1, step.currentEpisode, 7), season(2, 0, 13)];
    }
  });

  test('returns null once every season is at zero', () {
    expect(
        nextSeriesEpisodeStep([season(1, 0, 7), season(2, 0, 13)], -1), isNull);
  });

  test('sorts by seasonNumber before walking', () {
    final step = nextSeriesEpisodeStep([season(2, 0, 13), season(1, 7, 7)], -1);
    expect(step, const SeriesEpisodeStep(seasonId: 's1', currentEpisode: 6));
  });

  test('advances forward, skipping finished seasons', () {
    final step = nextSeriesEpisodeStep([season(1, 7, 7), season(2, 3, 13)], 1);
    expect(step, const SeriesEpisodeStep(seasonId: 's2', currentEpisode: 4));
  });

  test('returns null when all episodes in all seasons are watched', () {
    expect(
        nextSeriesEpisodeStep([season(1, 7, 7), season(2, 13, 13)], 1), isNull);
  });

  test('handles seasons with unknown (uncapped) episode counts', () {
    final step = nextSeriesEpisodeStep([season(1, 4, 0)], -1);
    expect(step, const SeriesEpisodeStep(seasonId: 's1', currentEpisode: 3));
  });

  test('delta = 0 → null; пустой список → null', () {
    expect(nextSeriesEpisodeStep([season(1, 2, 5)], 0), isNull);
    expect(nextSeriesEpisodeStep(<TvSeason>[], 1), isNull);
  });
}
