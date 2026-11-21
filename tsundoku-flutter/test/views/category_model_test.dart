import 'package:flutter_test/flutter_test.dart';
import 'package:tsundoku_flutter/shared/api/navigation_categories.dart';
import 'package:tsundoku_flutter/shared/types/enums.dart';
import 'package:tsundoku_flutter/shared/types/models.dart';
import 'package:tsundoku_flutter/views/category_model.dart';

/// Прямой перенос vitest-кейсов `categoryModel.test.ts`.
void main() {
  final sections = <StatusSection>[
    StatusSection(status: MediaStatus.inProgress, title: 'In progress'),
    StatusSection(status: MediaStatus.planned, title: 'Planned'),
    StatusSection(status: MediaStatus.completed, title: 'Completed'),
    StatusSection(status: MediaStatus.onHold, title: 'On hold'),
    StatusSection(status: MediaStatus.dropped, title: 'Dropped'),
  ];

  // API присылает status числом; строка может прийти из JSON-parsed
  // localStorage — сравнение везде численное (1-в-1 Number()).
  // MediaItem.fromJson парсит status строго из num — строковый вариант
  // проверяется через filterByStatus/buildStatusGroups (int.tryParse).
  MediaItem item(String id, Object status) {
    return MediaItem.fromJson({
      'id': id, 'type': 'game', 'title': id, 'status': status,
      'createdAt': '2026-11-21T00:00:00Z',
    });
  }

  test('groups items by status and skips empty sections when filtering by all',
      () {
    final items = [item('a', 1), item('b', 1), item('c', 2)];

    final groups = buildStatusGroups(items, 'all', sections);

    expect(groups.map((g) => g.status).toList(),
        [MediaStatus.inProgress, MediaStatus.completed]);
    expect(groups[0].items.map((e) => e.id).toList(), ['a', 'b']);
    expect(groups[1].items.map((e) => e.id).toList(), ['c']);
  });

  test('keeps only the selected section and compares statuses numerically',
      () {
    final items = [item('a', 2), item('b', 0)];

    final groups = buildStatusGroups(items, '2', sections);

    expect(groups, hasLength(1));
    expect(groups.single.status, MediaStatus.completed);
    expect(groups.single.items.map((e) => e.id).toList(), ['a']);
  });

  test('filters the flat list with numeric status comparison', () {
    final items = [item('a', 2), item('b', 0)];

    expect(filterByStatus(items, '2').map((e) => e.id).toList(), ['a']);
    expect(filterByStatus(items, 'all'), hasLength(2));
  });

  test('maps every category to the matching media query filters', () {
    final anime = categoryFilters('anime', '', 'newest');
    expect(anime.isAnime, isTrue);
    expect(anime.sortBy, SortBy.createdAt);
    expect(anime.sortOrder, SortOrder.desc);
    expect(anime.search, isNull);
    expect(anime.type, isNull);

    final tv = categoryFilters('tvshow', '', 'newest');
    expect(tv.type, MediaType.tvshow);
    expect(tv.isAnime, isFalse);

    final movie = categoryFilters('movie', '', 'newest');
    expect(movie.type, MediaType.movie);
    expect(movie.isAnime, isFalse);

    expect(categoryFilters('manga', '', 'newest').type, MediaType.manga);
    expect(categoryFilters('game', '', 'newest').type, MediaType.game);
    expect(categoryFilters('book', '', 'newest').type, MediaType.book);
  });

  test('search: пустая строка → null, непустая → trim', () {
    expect(categoryFilters('game', '  ', 'newest').search, isNull);
    expect(categoryFilters('game', '  ведьмак  ', 'newest').search, 'ведьмак');
  });

  test('sortFilters: newest/oldest/rating/title 1-в-1', () {
    expect(sortFilters('newest').sortBy, SortBy.createdAt);
    expect(sortFilters('newest').sortOrder, SortOrder.desc);
    expect(sortFilters('oldest').sortOrder, SortOrder.asc);
    expect(sortFilters('rating').sortBy, SortBy.score);
    expect(sortFilters('title').sortOrder, SortOrder.asc);
  });

  test('вынесенная подкатегория: type=parent + subId, без isAnime', () {
    final promoted = [
      const PromotedSubcategory(
        id: 'comics', label: 'Комиксы', icon: 'bookmark',
        parentType: 'Book', matchKind: 'format', matchValue: 'comics',
      ),
    ];
    final f = categoryFilters('comics', '', 'newest', promoted: promoted);
    expect(f.type, MediaType.book);
    expect(f.subId, 'comics');
    expect(f.isAnime, isNull, reason: 'isAnime не ставится для вынесенных');
  });

  test('baseCategories 1-в-1 с исходником', () {
    expect(baseCategories,
        ['tvshow', 'movie', 'anime', 'manga', 'game', 'book']);
  });
}
