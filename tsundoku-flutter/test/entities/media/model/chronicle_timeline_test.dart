import 'package:flutter_test/flutter_test.dart';
import 'package:tsundoku_flutter/entities/media/model/chronicle_timeline.dart';
import 'package:tsundoku_flutter/shared/types/enums.dart';
import 'package:tsundoku_flutter/shared/types/models.dart';

MediaItem game(String id,
    {MediaStatus status = MediaStatus.completed,
    String? finishedAt,
    int? score,
    String? startedAt}) {
  return MediaItem.fromJson({
    'id': id,
    'type': 'game',
    'title': 'Game $id',
    'status': status.value,
    'score': score,
    'startedAt': startedAt,
    'finishedAt': finishedAt,
    'coverUrl': null,
    'createdAt': '2024-01-01T00:00:00Z',
    'franchiseId': null,
    'franchiseOrder': null,
    'platform': 'PC',
    'hoursPlayed': null,
  });
}

MediaItem movie(String id, {bool? isAnime, String? finishedAt}) {
  return MediaItem.fromJson({
    'id': id,
    'type': 'movie',
    'title': 'Movie $id',
    'status': MediaStatus.completed.value,
    'score': null,
    'startedAt': null,
    'finishedAt': finishedAt,
    'coverUrl': null,
    'createdAt': '2024-01-01T00:00:00Z',
    'franchiseId': null,
    'franchiseOrder': null,
    'durationMinutes': 120,
    'director': null,
    'isAnime': isAnime,
    'studio': null,
    'romajiTitle': null,
  });
}

MediaItem tvshow(String id, {bool? isAnime, String? finishedAt}) {
  return MediaItem.fromJson({
    'id': id,
    'type': 'tvshow',
    'title': 'TvShow $id',
    'status': MediaStatus.completed.value,
    'score': null,
    'startedAt': null,
    'finishedAt': finishedAt,
    'coverUrl': null,
    'createdAt': '2024-01-01T00:00:00Z',
    'franchiseId': null,
    'franchiseOrder': null,
    'isAnime': isAnime,
    'studio': null,
    'romajiTitle': null,
    'network': null,
    'totalEpisodesCount': 12,
    'totalEpisodesWatched': 12,
    'seasonsCount': 1,
  });
}

/// Прямой перенос vitest-кейсов `chronicleTimeline.test.ts`.
void main() {
  test('groups items by year and month in descending order', () {
    final items = [
      game('g1', finishedAt: '2024-03-10T00:00:00Z', score: 8),
      game('g2', finishedAt: '2024-11-01T00:00:00Z', score: 9),
      game('g3', finishedAt: '2025-01-15T00:00:00Z', score: 7),
      game('g4', finishedAt: '2024-03-20T00:00:00Z', score: null),
    ];

    final result = buildChronicle(items, category: 'all', includeInProgress: false);

    expect(result.years.map((y) => y.year).toList(), [2025, 2024]);

    final year2024 = result.years.firstWhere((y) => y.year == 2024);
    expect(year2024.months.map((m) => m.month).toList(), [10, 2]);

    final marchGroup = year2024.months.firstWhere((m) => m.month == 2);
    expect(marchGroup.entries[0].item.id, 'g4');
    expect(marchGroup.entries[1].item.id, 'g1');
  });

  test('calculates averageScore and topRatedItem correctly', () {
    final items = [
      game('g1', finishedAt: '2024-06-01T00:00:00Z', score: 8),
      game('g2', finishedAt: '2024-06-15T00:00:00Z', score: 6),
      game('g3', finishedAt: '2024-06-20T00:00:00Z', score: 10),
      game('g4', finishedAt: '2024-06-25T00:00:00Z', score: null),
    ];

    final result = buildChronicle(items, category: 'all', includeInProgress: false);
    final year = result.years.first;

    expect(year.averageScore, 8.0);
    expect(year.topRatedItem?.id, 'g3');

    final juneGroup = year.months.first;
    expect(juneGroup.averageScore, 8.0);
  });

  test('filters properly by category (anime, movie, tvshow, game, all)', () {
    final items = [
      game('g1', finishedAt: '2024-05-01T00:00:00Z'),
      movie('m1', isAnime: false, finishedAt: '2024-05-02T00:00:00Z'),
      movie('m2', isAnime: true, finishedAt: '2024-05-03T00:00:00Z'),
      tvshow('tv1', isAnime: true, finishedAt: '2024-05-04T00:00:00Z'),
      tvshow('tv2', isAnime: false, finishedAt: '2024-05-05T00:00:00Z'),
    ];

    final animeResult =
        buildChronicle(items, category: 'anime', includeInProgress: false);
    final animeIds = animeResult.years.firstOrNull?.entries
        .map((e) => e.item.id)
        .toList()
      ?..sort();
    expect(animeIds, ['m2', 'tv1']);

    final movieResult =
        buildChronicle(items, category: 'movie', includeInProgress: false);
    final movieIds = movieResult.years.firstOrNull?.entries
        .map((e) => e.item.id)
        .toList()
      ?..sort();
    expect(movieIds, ['m1']);

    final tvResult =
        buildChronicle(items, category: 'tvshow', includeInProgress: false);
    final tvIds = tvResult.years.firstOrNull?.entries
        .map((e) => e.item.id)
        .toList()
      ?..sort();
    expect(tvIds, ['tv2']);

    final gameResult =
        buildChronicle(items, category: 'game', includeInProgress: false);
    final gameIds = gameResult.years.firstOrNull?.entries
        .map((e) => e.item.id)
        .toList()
      ?..sort();
    expect(gameIds, ['g1']);

    final allResult = buildChronicle(items, category: 'all', includeInProgress: false);
    expect(allResult.totalDatedCount, 5);
  });

  test('places undated completed items into undatedCompleted', () {
    final items = [
      game('g_dated', finishedAt: '2024-09-01T00:00:00Z'),
      game('g_undated1', finishedAt: null, startedAt: null),
      game('g_undated2', finishedAt: null, startedAt: null),
      game('g_startedonly', finishedAt: null, startedAt: '2024-08-01T00:00:00Z'),
    ];

    final result = buildChronicle(items, category: 'all', includeInProgress: false);

    expect(result.undatedCompleted.length, 2);
    expect(result.undatedCompleted.any((i) => i.id == 'g_undated1'), isTrue);
    expect(result.undatedCompleted.any((i) => i.id == 'g_undated2'), isTrue);
    expect(result.totalDatedCount, 2);
  });

  test('respects includeInProgress flag', () {
    final items = [
      game('g_done', finishedAt: '2024-04-01T00:00:00Z',
          status: MediaStatus.completed),
      game('g_ip_dated',
          status: MediaStatus.inProgress,
          startedAt: '2024-04-15T00:00:00Z',
          finishedAt: null),
      game('g_ip_nodates',
          status: MediaStatus.inProgress,
          startedAt: null,
          finishedAt: null),
    ];

    final withoutIP =
        buildChronicle(items, category: 'all', includeInProgress: false);
    expect(withoutIP.totalDatedCount, 1);

    final withIP =
        buildChronicle(items, category: 'all', includeInProgress: true);
    expect(withIP.totalDatedCount, 2);
    final ipEntry = withIP.years.firstOrNull?.entries
        .firstWhere((e) => e.item.id == 'g_ip_dated');
    expect(ipEntry?.isCompleted, isFalse);
  });
}
