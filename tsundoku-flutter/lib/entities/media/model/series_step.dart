/// 1:1 port of `mediatracker-ui/src/entities/media/model/seriesStep.ts`.
library;

import '../../../shared/types/models.dart';

/// Which season a +/- press on a card writes to, and the value it lands on.
class SeriesEpisodeStep {
  final String seasonId;
  final int currentEpisode;

  const SeriesEpisodeStep({required this.seasonId, required this.currentEpisode});

  @override
  bool operator ==(Object other) =>
      other is SeriesEpisodeStep &&
      other.seasonId == seasonId &&
      other.currentEpisode == currentEpisode;

  @override
  int get hashCode => Object.hash(seasonId, currentEpisode);

  @override
  String toString() => 'SeriesEpisodeStep($seasonId, $currentEpisode)';
}

/// Resolves one +/- press on a show's episode counter across the whole series
/// instead of inside a single season. Forward lands on the first season that
/// still has an episode left; backward leaves the last season that still has
/// one, so the floor is a flat 0 for the series and not an artificial stop at
/// every season boundary.
SeriesEpisodeStep? nextSeriesEpisodeStep(
    List<TvSeason> seasons, int delta) {
  if (seasons.isEmpty || delta == 0) return null;

  final ordered = [...seasons]..sort((a, b) => a.seasonNumber - b.seasonNumber);

  if (delta < 0) {
    for (var i = ordered.length - 1; i >= 0; i--) {
      final current = ordered[i].currentEpisode;
      if (current > 0) {
        return SeriesEpisodeStep(
            seasonId: ordered[i].id, currentEpisode: current - 1);
      }
    }
    return null;
  }

  int total(TvSeason season) => season.totalEpisodes;
  final target = ordered.cast<TvSeason?>().firstWhere(
        (s) => total(s!) > 0 && s.currentEpisode < total(s),
        orElse: () => ordered.cast<TvSeason?>().firstWhere(
              (s) => total(s!) <= 0,
              orElse: () => null,
            ),
      );
  if (target == null) return null;

  final current = target.currentEpisode;
  final next = total(target) > 0
      ? (current + delta > total(target) ? total(target) : current + delta)
      : current + delta;
  return next == current ? null : SeriesEpisodeStep(
      seasonId: target.id, currentEpisode: next);
}
