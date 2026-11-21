import 'package:flutter_test/flutter_test.dart';
import 'package:tsundoku_flutter/entities/media/model/time_budget.dart';
import 'package:tsundoku_flutter/shared/types/models.dart';

MediaItem movie(int durationMinutes) {
  return MediaItem.fromJson({
    'id': 'movie-1', 'type': 'movie', 'title': 'Test Movie', 'status': 1,
    'createdAt': '2026-01-01T00:00:00Z', 'durationMinutes': durationMinutes,
    'isAnime': false, 'director': null, 'studio': null, 'romajiTitle': null,
  });
}

MediaItem tvShow({
  int? durationMinutes,
  bool? isAnime,
  required int totalEpisodesCount,
  required int totalEpisodesWatched,
}) {
  return MediaItem.fromJson({
    'id': 'tv-1', 'type': 'tvshow', 'title': 'Test TV Show', 'status': 1,
    'createdAt': '2026-01-01T00:00:00Z',
    'isAnime': isAnime ?? false, 'studio': null, 'romajiTitle': null,
    'network': null, 'seasonsCount': 1,
    'totalEpisodesCount': totalEpisodesCount,
    'totalEpisodesWatched': totalEpisodesWatched,
    'durationMinutes': durationMinutes,
  });
}

MediaItem book(int currentPage, int totalPages) {
  return MediaItem.fromJson({
    'id': 'book-1', 'type': 'book', 'title': 'Test Book', 'status': 1,
    'createdAt': '2026-01-01T00:00:00Z', 'author': 'Author',
    'currentPage': currentPage, 'totalPages': totalPages,
  });
}

MediaItem manga(int currentChapter, int? totalChapters) {
  return MediaItem.fromJson({
    'id': 'manga-1', 'type': 'manga', 'title': 'Test Manga', 'status': 1,
    'createdAt': '2026-01-01T00:00:00Z',
    'currentChapter': currentChapter, 'totalChapters': totalChapters,
    'currentVolume': 1,
  });
}

MediaItem game() {
  return MediaItem.fromJson({
    'id': 'game-1', 'type': 'game', 'title': 'Test Game', 'status': 1,
    'createdAt': '2026-01-01T00:00:00Z', 'platform': 'PC', 'hoursPlayed': 5,
  });
}

/// Прямой перенос vitest-кейсов `timeBudget.test.ts`.
void main() {
  test('rejects long movie and episode in 15 min slot, accepts book and manga',
      () {
    final movieRes = evaluateTimeFit(movie(120), 15, 1.5, 6.0, locale: 'ru');
    expect(movieRes.fits, isFalse);

    final tvRes = evaluateTimeFit(
      tvShow(
          durationMinutes: 45,
          isAnime: false,
          totalEpisodesCount: 10,
          totalEpisodesWatched: 0),
      15, 1.5, 6.0, locale: 'ru',
    );
    expect(tvRes.fits, isFalse);

    final bookRes = evaluateTimeFit(book(50, 300), 15, 1.5, 6.0, locale: 'ru');
    expect(bookRes.fits, isTrue);
    expect(bookRes.sessionLabel, 'За сессию: ~10 стр.');

    final mangaRes = evaluateTimeFit(manga(10, 50), 15, 1.5, 6.0, locale: 'ru');
    expect(mangaRes.fits, isTrue);
    expect(mangaRes.sessionLabel, 'Успеете: ~2 гл.');
  });

  test('evaluates anime episodes in 30 min slot and marks final episode finish',
      () {
    final ongoingRes = evaluateTimeFit(
      tvShow(
          durationMinutes: 24,
          isAnime: true,
          totalEpisodesCount: 12,
          totalEpisodesWatched: 5),
      30, 1.5, 6.0, locale: 'ru',
    );
    expect(ongoingRes.fits, isTrue);
    expect(ongoingRes.canFinishNow, isFalse);
    expect(ongoingRes.sessionLabel, 'Успеете: 1 эп. (~24 мин.)');

    final finalRes = evaluateTimeFit(
      tvShow(
          durationMinutes: 24,
          isAnime: true,
          totalEpisodesCount: 12,
          totalEpisodesWatched: 11),
      30, 1.5, 6.0, locale: 'ru',
    );
    expect(finalRes.fits, isTrue);
    expect(finalRes.canFinishNow, isTrue);
    expect(finalRes.sessionLabel, '🔥 Добить финал: 1 эп. (~24 мин.)');
  });

  test('fits 110 min movie into 120 min slot and marks canFinishNow', () {
    final movieRes = evaluateTimeFit(movie(110), 120, 1.5, 6.0, locale: 'ru');
    expect(movieRes.fits, isTrue);
    expect(movieRes.canFinishNow, isTrue);
    expect(movieRes.sessionLabel, '🔥 Целиком: 110 мин.');
  });

  test('evaluates edge cases for games, book finishing, and English locale', () {
    final g = game();
    expect(evaluateTimeFit(g, 15, 1.5, 6.0, locale: 'ru').fits, isFalse);
    expect(evaluateTimeFit(g, 30, 1.5, 6.0, locale: 'ru').fits, isTrue);
    expect(evaluateTimeFit(g, 30, 1.5, 6.0, locale: 'ru').sessionLabel,
        'Игровая сессия: 30 мин.');

    final bookFinish = evaluateTimeFit(book(195, 200), 15, 1.5, 6.0, locale: 'ru');
    expect(bookFinish.canFinishNow, isTrue);
    expect(bookFinish.sessionLabel, '🔥 Дочитать до конца: 5 стр. (~8 мин.)');

    final movieEn = evaluateTimeFit(movie(90), 90, 1.5, 6.0, locale: 'en');
    expect(movieEn.sessionLabel, '🔥 Entire: 90 min');
  });

  test('formats time budget chips properly for various durations and locales',
      () {
    expect(formatTimeBudgetChip(15, locale: 'ru'), '15 м');
    expect(formatTimeBudgetChip(15, locale: 'en'), '15m');
    expect(formatTimeBudgetChip(40, locale: 'ru'), '40 м');
    expect(formatTimeBudgetChip(40, locale: 'en'), '40m');
    expect(formatTimeBudgetChip(60, locale: 'ru'), '1 ч');
    expect(formatTimeBudgetChip(60, locale: 'en'), '1h');
    expect(formatTimeBudgetChip(90, locale: 'ru'), '1.5 ч');
    expect(formatTimeBudgetChip(90, locale: 'en'), '1.5h');
    expect(formatTimeBudgetChip(120, locale: 'ru'), '2 ч');
    expect(formatTimeBudgetChip(120, locale: 'en'), '2h');
    expect(formatTimeBudgetChip(150, locale: 'ru'), '2.5 ч');
    expect(formatTimeBudgetChip(150, locale: 'en'), '2.5h');
    expect(formatTimeBudgetChip(75, locale: 'ru'), '1ч 15м');
    expect(formatTimeBudgetChip(75, locale: 'en'), '1h 15m');
  });

  test('нулевые и отрицательные бюджеты → не fits', () {
    final res = evaluateTimeFit(movie(90), 0, 1.5, 6.0, locale: 'ru');
    expect(res.fits, isFalse);
    expect(res.sessionLabel, '');

    final resNeg = evaluateTimeFit(manga(1, 10), -5, 1.5, 6.0, locale: 'ru');
    expect(resNeg.fits, isFalse);
  });
}
