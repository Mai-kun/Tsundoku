/// 1:1 port of `mediatracker-ui/src/views/categoryModel.ts`.
///
/// `LibrarySort` — строковый union из FilterBar.svelte (Фаза 3 импортирует
/// отсюда).
library;

import '../shared/api/navigation_categories.dart';
import '../shared/types/enums.dart';
import '../shared/types/models.dart';

/// `type LibrarySort = "newest" | "oldest" | "rating" | "title"` (FilterBar).
typedef LibrarySort = String;

/// Базовые категории. Вынесенные (промоутед) подкатегории — динамические id
/// из настроек.
const List<String> baseCategories = <String>[
  'tvshow',
  'movie',
  'anime',
  'manga',
  'game',
  'book',
];

/// `type Category = BaseCategory | (string & {})` — открытый строковый union.
typedef Category = String;

class StatusSection {
  final MediaStatus status;
  final String title;

  const StatusSection({required this.status, required this.title});
}

class StatusGroup {
  final MediaStatus status;
  final String title;
  final List<MediaItem> items;

  const StatusGroup({
    required this.status,
    required this.title,
    required this.items,
  });
}

/// Status can arrive as a number from the API or as a JSON-parsed string from
/// localStorage — сравнение численное (1-в-1 Number()).
List<MediaItem> filterByStatus(List<MediaItem> items, String status) {
  if (status == 'all') return items;
  final needle = int.tryParse(status);
  return items.where((item) => item.status.value == needle).toList();
}

List<StatusGroup> buildStatusGroups(
  List<MediaItem> items,
  String status,
  List<StatusSection> sections,
) {
  // Explicit 0-safe buckets: MEDIA_STATUS.planned is 0 — без Map-less lookup
  // ловушек (прямой аналог Record<number, MediaItem[]>).
  final buckets = <int, List<MediaItem>>{};
  for (final section in sections) {
    buckets[section.status.value] = <MediaItem>[];
  }
  for (final item in items) {
    buckets[item.status.value]?.add(item);
  }

  return [
    for (final section in sections)
      StatusGroup(
        status: section.status,
        title: section.title,
        items: buckets[section.status.value] ?? <MediaItem>[],
      ),
  ].where((group) =>
      status == 'all'
          ? group.items.isNotEmpty
          : group.status.value == int.tryParse(status)).toList();
}

MediaFilters categoryFilters(
  String category,
  String search,
  String sort, {
  List<PromotedSubcategory> promoted = const <PromotedSubcategory>[],
}) {
  final base = sortFilters(sort).copyWithFields(
    search: search.trim().isEmpty ? null : search.trim(),
  );

  // Вынесенная подкатегория: запрос идёт по родительскому типу с subId —
  // сервер сам применяет match-условие и исключает элементы из родительской
  // категории.
  for (final promotedCategory in promoted) {
    if (promotedCategory.id == category) {
      return base.copyWithFields(
        type: MediaType.fromWire(promotedCategory.parentType.toLowerCase()),
        subId: promotedCategory.id,
      );
    }
  }

  switch (category) {
    case 'anime':
      return base.copyWithFields(isAnime: true);
    case 'tvshow':
      return base.copyWithFields(type: MediaType.tvshow, isAnime: false);
    case 'movie':
      return base.copyWithFields(type: MediaType.movie, isAnime: false);
    default:
      // Не вынесенная и не спец-категория: категория совпадает с типом медиа.
      return base.copyWithFields(type: MediaType.fromWire(category));
  }
}

MediaFilters sortFilters(String value) {
  switch (value) {
    case 'oldest':
      return const MediaFilters(
          sortBy: SortBy.createdAt, sortOrder: SortOrder.asc);
    case 'rating':
      return const MediaFilters(
          sortBy: SortBy.score, sortOrder: SortOrder.desc);
    case 'title':
      return const MediaFilters(
          sortBy: SortBy.title, sortOrder: SortOrder.asc);
    default:
      return const MediaFilters(
          sortBy: SortBy.createdAt, sortOrder: SortOrder.desc);
  }
}
