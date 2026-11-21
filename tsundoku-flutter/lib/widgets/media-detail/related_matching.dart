/// 1:1 port of `mediatracker-ui/src/widgets/media-detail/relatedMatching.ts`.
///
/// Умный матчинг внешней relation-записи с тайтлом библиотеки. Каскад:
/// 1. External ID (item.externalId === rel.id)
/// 2. Оригинальное название (японское/нативное)
/// 3. Ромадзи
/// 4. Нормализованный кросс-матч всех вариантов
/// 5. Базовый тайтл без movie/film-маркеров (когда оба — фильмы)
library;

import '../../shared/types/index.dart' show MediaDetail, MediaItem;
import 'detail_types.dart' show RelatedEntry;

/// Нормализация названия: без пунктуации/пробелов/не-алфавитных символов с
/// сохранением латиницы, кириллицы, канзи, хираганы и катаканы.
String normalizeTitle(String? s) {
  return (s ?? '')
      .toLowerCase()
      .replaceAll(RegExp(r'[・\u30fb\u3000-\u303f\uff00-\uffef]'), '')
      .replaceAll(RegExp(r'[^a-zа-я0-9\u3040-\u30ff\u3400-\u4dbf\u4e00-\u9fff]'), '')
      .trim();
}

/// Является ли строка/формат маркером фильма.
bool hasMovieMarker(String? s) {
  if (s == null || s.isEmpty) return false;
  return RegExp(r'\b(movie|the\s+movie|film|the\s+film)\b', caseSensitive: false)
          .hasMatch(s) ||
      RegExp(r'(фильм|полнометраж)', caseSensitive: false).hasMatch(s) ||
      RegExp(r'(劇場版|映画)').hasMatch(s);
}

/// Убирает movie/film-маркеры и артикли для базового сравнения названий.
String stripMovieMarker(String? s) {
  if (s == null || s.isEmpty) return '';
  return s
      .replaceAll(RegExp(r'\b(the\s+movie|movie|the\s+film|film)\b', caseSensitive: false), '')
      .replaceAll(
          RegExp(r'(фильм|фильм\s+\d+|полнометражный\s+фильм|полнометражка)',
              caseSensitive: false),
          '')
      .replaceAll(RegExp(r'(劇場版|映画)'), '')
      .replaceAll(RegExp(r'\b(the|a|an)\b', caseSensitive: false), '')
      .trim();
}

String? _readItemRomaji(MediaItem item) {
  if (item.type.wire == 'game' || item.type.wire == 'book') return null;
  final val = item.romajiTitle?.trim();
  return (val != null && val.isNotEmpty) ? val : null;
}

/// Матчинг relation-записи с тайтлом библиотеки (каскад 1–5, см. шапку).
bool isRelatedMatch(RelatedEntry rel, MediaItem item) {
  // 1. External ID match
  final itemExternalId = item.externalId?.trim();
  final relId = rel.id.trim();
  if (itemExternalId != null &&
      itemExternalId.isNotEmpty &&
      relId.isNotEmpty &&
      itemExternalId == relId) {
    return true;
  }

  // TS: `(item as { originalTitle?: string | null }).originalTitle` —
  // поле декларировано только в detail-интерфейсе; в рантайме его носят
  // detail-объекты. Dart-эквивалент — проверка подтипа.
  final itemOrig = item is MediaDetail ? item.originalTitle?.trim() : null;
  final relOrig = rel.originalTitle?.trim();
  final itemRomaji = _readItemRomaji(item);
  final relRomaji = rel.romajiTitle?.trim();

  // 2. Original title match
  if (itemOrig != null && itemOrig.isNotEmpty && relOrig != null && relOrig.isNotEmpty) {
    final normItemOrig = normalizeTitle(itemOrig);
    final normRelOrig = normalizeTitle(relOrig);
    if (normItemOrig.isNotEmpty && normItemOrig == normRelOrig) {
      return true;
    }
  }

  // 3. Romaji title match
  if (itemRomaji != null && relRomaji != null && relRomaji.isNotEmpty) {
    final normItemRomaji = normalizeTitle(itemRomaji);
    final normRelRomaji = normalizeTitle(relRomaji);
    if (normItemRomaji.isNotEmpty && normItemRomaji == normRelRomaji) {
      return true;
    }
  }

  // 4. Normalized cross-title match
  final itemCandidates = <String>[
    item.title,
    ?itemRomaji,
    ?itemOrig,
  ];
  final relCandidates = <String>[
    rel.title,
    if (relRomaji != null && relRomaji.isNotEmpty) relRomaji,
    if (relOrig != null && relOrig.isNotEmpty) relOrig,
  ];

  final normRelList = relCandidates
      .map(normalizeTitle)
      .where((t) => t.isNotEmpty)
      .toList();

  for (final itemTitle in itemCandidates) {
    final normItem = normalizeTitle(itemTitle);
    if (normItem.isNotEmpty && normRelList.contains(normItem)) {
      return true;
    }
  }

  // 5. Movie / Film marker match: когда ОБА — фильмы
  final itemIsMovie = item.type.wire == 'movie' ||
      hasMovieMarker(item.title) ||
      hasMovieMarker(itemRomaji);
  final relIsMovie =
      rel.format?.toUpperCase() == 'MOVIE' ||
          rel.type == 'movie' ||
          hasMovieMarker(rel.title) ||
          hasMovieMarker(relRomaji);

  if (itemIsMovie && relIsMovie) {
    final strippedRelList = relCandidates
        .map((t) => normalizeTitle(stripMovieMarker(t)))
        .where((t) => t.length >= 3)
        .toList();

    for (final itemTitle in itemCandidates) {
      final strippedItem = normalizeTitle(stripMovieMarker(itemTitle));
      if (strippedItem.length >= 3 && strippedRelList.contains(strippedItem)) {
        return true;
      }
    }
  }

  return false;
}

/// Ищет matching-тайтл библиотеки для внешней relation-записи.
MediaItem? findMatchingLocal(RelatedEntry rel, List<MediaItem>? library) {
  if (library == null || library.isEmpty) return null;
  try {
    return library.firstWhere((item) {
      try {
        return isRelatedMatch(rel, item);
      } catch (_) {
        return false;
      }
    });
  } catch (_) {
    return null;
  }
}
