import 'package:flutter_test/flutter_test.dart';
import 'package:tsundoku_flutter/entities/media/model/progress_rules.dart';
import 'package:tsundoku_flutter/shared/types/models.dart';

MediaItem item(String type,
    {int? hoursPlayed,
    String? format,
    int? currentPage,
    int? totalPages,
    int? currentChapter,
    int? totalChapters,
    int? totalEpisodesWatched}) {
  return MediaItem.fromJson({
    'id': 'm1',
    'type': type,
    'title': 'T',
    'status': 1,
    'createdAt': '2026-11-21T00:00:00Z',
    'format': format,
    'hoursPlayed': hoursPlayed,
    'currentPage': currentPage,
    'totalPages': totalPages,
    'currentChapter': currentChapter,
    'totalChapters': totalChapters,
    'totalEpisodesWatched': totalEpisodesWatched,
  });
}

/// Прямой перенос vitest-кейсов progressRules (+ writeCardProgress copyWith).
void main() {
  test('readCardProgress: game/book/manga/tvshow/movie', () {
    expect(readCardProgress(item('game', hoursPlayed: 42)), 42);
    expect(readCardProgress(item('book', currentPage: 30)), 30);
    expect(readCardProgress(item('book', format: 'light_novel', currentChapter: 5)), 5);
    expect(readCardProgress(item('book', format: 'web_novel', currentChapter: 7)), 7);
    expect(readCardProgress(item('manga', currentChapter: 12)), 12);
    expect(readCardProgress(item('tvshow', totalEpisodesWatched: 4)), 4);
    expect(readCardProgress(item('movie')), 0, reason: 'movie не читает прогресс');
  });

  test('cardProgressTotal: book (novel → chapters; обычная → pages)', () {
    expect(cardProgressTotal(item('book', format: 'light_novel', totalChapters: 20)),
        20);
    expect(cardProgressTotal(item('book', totalPages: 300)), 300);
    expect(cardProgressTotal(item('manga', totalChapters: 100)), 100);
    expect(cardProgressTotal(item('game')), isNull);
    expect(cardProgressTotal(item('movie')), isNull);
    expect(cardProgressTotal(item('tvshow')), isNull);
  });

  test('writeCardProgress: копия с новым значением (решение #14)', () {
    final game = item('game', hoursPlayed: 5);
    final game2 = writeCardProgress(game, 7);
    expect(game2.hoursPlayed, 7);
    expect(game.hoursPlayed, 5, reason: 'исходник иммутабелен');
    expect(game2.id, game.id, reason: 'копия сохраняет прочие поля');

    final book = item('book', format: 'light_novel', currentChapter: 2);
    expect(writeCardProgress(book, 3).currentChapter, 3);

    final paper = item('book', currentPage: 100);
    expect(writeCardProgress(paper, 120).currentPage, 120);
    expect(writeCardProgress(paper, 120).currentChapter, isNull,
        reason: 'не novel — пишет в currentPage');

    final manga = item('manga', currentChapter: 8);
    expect(writeCardProgress(manga, 9).currentChapter, 9);

    final tv = item('tvshow', totalEpisodesWatched: 6);
    expect(writeCardProgress(tv, 7).totalEpisodesWatched, 7);
  });

  test('supportsProgressStepper: все кроме movie', () {
    expect(supportsProgressStepper(item('game')), isTrue);
    expect(supportsProgressStepper(item('book')), isTrue);
    expect(supportsProgressStepper(item('manga')), isTrue);
    expect(supportsProgressStepper(item('tvshow')), isTrue);
    expect(supportsProgressStepper(item('movie')), isFalse);
  });

  test('clampProgress: отрицательные и переполнение', () {
    expect(clampProgress(-5, null), 0);
    expect(clampProgress(10, null), 10);
    expect(clampProgress(10, 5), 5);
    expect(clampProgress(-3, 5), 0);
    expect(clampProgress(10, 0), 10, reason: 'total <= 0 — не ограничивает');
  });

  test('nextCardProgress: +/- с клампом', () {
    final manga = item('manga', currentChapter: 8, totalChapters: 10);
    expect(nextCardProgress(manga, 8, 1), 9);
    expect(nextCardProgress(manga, 8, -1), 7);
    expect(nextCardProgress(manga, 9, 1), 10, reason: 'кламп к total');
    expect(nextCardProgress(manga, 0, -1), 0, reason: 'не ниже нуля');
  });

  test('shouldPromoteToInProgress: только 0 → 1 (rule 1 статуса)', () {
    expect(shouldPromoteToInProgress(0, 1), isTrue);
    expect(shouldPromoteToInProgress(1, 2), isFalse);
    expect(shouldPromoteToInProgress(0, 2), isFalse);
    expect(shouldPromoteToInProgress(0, 0), isFalse);
    expect(shouldPromoteToInProgress(5, 6), isFalse);
  });
}
