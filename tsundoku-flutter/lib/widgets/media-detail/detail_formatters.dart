/// 1:1 port of `mediatracker-ui/src/widgets/media-detail/detailFormatters.ts`.
///
/// Чистые форматтеры детальной страницы: тип/формат, providerLink (URL внешнего
/// источника), статусы релиза, прогресс чтения/просмотра, серии сезона,
/// specRows «Характеристик». i18n через [I18nDictionary] (t, в нём же locale —
/// аналог i18n.current); Intl.DateTimeFormat → DateFormat yMMMMd (конвенция
/// history_formatters, решение #11). Вытащен вперёд из Фазы 4: зависимость
/// BaseCard → providerLink.
library;

import 'dart:convert';
import 'dart:math' as math;

import 'package:collection/collection.dart';
import 'package:diacritic/diacritic.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:intl/intl.dart';
import 'package:material_ui/material_ui.dart' show Color;

import '../../entities/media/model/genre_label.dart';
export '../../entities/media/model/media_labels.dart' show statusLabel;
import '../../shared/i18n/index.dart';
import '../../shared/types/enums.dart';
import '../../shared/types/models.dart';
import '../../shared/utils/source_url_helper.dart';
import 'detail_types.dart';

/// Season rows are synthesised from a count because most seasons arrive
/// without an episodesData payload. Capped so a bogus "5000 episodes" metadata
/// value cannot render 5000 rows.
const int maxEpisodesPerSeason = 200;

bool isAnime(MediaItem item) =>
    (item.type == MediaType.tvshow || item.type == MediaType.movie) &&
    (item.isAnime ?? false);

String typeLabel(MediaItem item, I18nDictionary t) {
  return isAnime(item)
      ? t.tr('navigation.anime')
      : t.tr('types.${item.type.wire}');
}

/// Manga is stored as one type, but the origin decides how it is read: a
/// manhwa or an OEL title called just "Манга" is wrong. Falls back to the
/// plain type label when no source knew.
String formatLabel(MediaItem item, I18nDictionary t) {
  if (item.type == MediaType.book) {
    final isRu = t.locale.wire == 'ru';
    switch (item.format) {
      case 'light_novel':
        return isRu ? 'Ранобэ' : 'Light Novel';
      case 'web_novel':
        return isRu ? 'Веб-новелла' : 'Web Novel';
      case 'comics':
        return isRu ? 'Комикс' : 'Comics';
      case 'ebook':
        return isRu ? 'Электронная книга' : 'E-book';
      case 'audiobook':
        return isRu ? 'Аудиокнига' : 'Audiobook';
    }
    return typeLabel(item, t);
  }
  if (!isMangaDetail(item)) return typeLabel(item, t);

  final known = item.mangaFormat;
  if (known == null || known.isEmpty) return typeLabel(item, t);

  // labels[known] ?? typeLabel(item): неизвестный ключ → фолбэк.
  try {
    return t.tr('detail.mangaFormats.$known');
  } on ArgumentError {
    return typeLabel(item, t);
  }
}

/// The crowned source from "Внешние источники". The stored `IsPrimary` flag is
/// authoritative, so the left "Источник данных" field and the provider link
/// must read from it rather than from the legacy `externalSource` column,
/// which can lag behind a user-switched primary.
///
/// TS читал linkedSources через runtime-cast; в Dart список живёт в
/// [MediaDetail] (list-строки его не несут) — проверка `is MediaDetail`.
LinkedSource? primaryLinkedSource(MediaItem item) =>
    item is MediaDetail
        ? item.linkedSources?.firstWhereOrNull((source) => source.isPrimary)
        : null;

String dataSource(MediaItem item) {
  final primary = primaryLinkedSource(item);
  if (primary?.source.isNotEmpty ?? false) return primary!.source;
  if (item.externalSource?.isNotEmpty ?? false) return item.externalSource!;
  if (isAnime(item) || item.type == MediaType.manga) return 'AniList';

  switch (item.type) {
    case MediaType.game:
      return 'RAWG';
    case MediaType.book:
      return 'OpenLibrary';
    default:
      return 'TMDB';
  }
}

/// Внешняя страница тайтла ({name, url} из TS-объекта).
class ProviderLink {
  final String name;
  final String url;

  const ProviderLink({required this.name, required this.url});
}

/// The external page of an item, built from the source that actually supplied
/// it.
///
/// This used to return a bare domain and fall through to `anilist.co` for
/// anything unrecognised, so a Dune matched by Kinopoisk linked to AniList
/// with an AniList-styled id. The URL is now composed per source and an
/// unknown source yields no link at all rather than a wrong one.
ProviderLink? providerLink(MediaItem item) {
  final primary = primaryLinkedSource(item);
  if (primary?.url?.isNotEmpty ?? false) {
    return ProviderLink(name: primary!.source, url: primary.url!);
  }
  final src =
      (primary?.source ?? item.externalSource ?? dataSource(item)).toLowerCase();
  final id = (primary?.externalId ?? item.externalId ?? '').trim();

  if (src.contains('kinopoisk')) {
    return id.isNotEmpty
        ? ProviderLink(
            name: 'Кинопоиск',
            url: 'https://www.kinopoisk.ru/film/${Uri.encodeComponent(id)}/')
        : null;
  }
  if (src.contains('tmdb') || src.contains('movie database')) {
    if (id.isEmpty) return null;
    final kind =
        item.type == MediaType.tvshow || isAnime(item) ? 'tv' : 'movie';
    return ProviderLink(
        name: 'TMDb',
        url: 'https://www.themoviedb.org/$kind/${Uri.encodeComponent(id)}');
  }
  if (src.contains('rawg')) {
    // RAWG ids are numeric, but the site's own slug is what the page path
    // expects; the search link works with either, so a slug-less id still
    // gets a usable target.
    return ProviderLink(
      name: 'RAWG',
      url: id.isNotEmpty
          ? 'https://rawg.io/games/${Uri.encodeComponent(_slugify(item.title))}'
              '-${Uri.encodeComponent(id)}'
          : 'https://rawg.io/search?q=${Uri.encodeComponent(item.title)}',
    );
  }
  if (src.contains('mangadex')) {
    return id.isNotEmpty
        ? ProviderLink(
            name: 'MangaDex',
            url: 'https://mangadex.org/title/${Uri.encodeComponent(id)}')
        : null;
  }
  if (src.contains('ranobelib')) {
    return id.isNotEmpty
        ? ProviderLink(
            name: 'RanobeLib',
            url: 'https://ranobelib.me/ru/${Uri.encodeComponent(id)}')
        : null;
  }
  if (src.contains('mangalib')) {
    return id.isNotEmpty
        ? ProviderLink(
            name: 'MangaLib',
            url: 'https://mangalib.me/ru/${Uri.encodeComponent(id)}')
        : null;
  }
  if (src.contains('animelib')) {
    return id.isNotEmpty
        ? ProviderLink(name: 'AnimeLib', url: buildAnimelibUrl(id))
        : null;
  }
  if (src.contains('slashlib')) {
    return id.isNotEmpty
        ? ProviderLink(
            name: 'SlashLib',
            url: 'https://slashlib.me/ru/${Uri.encodeComponent(id)}')
        : null;
  }
  if (src.contains('sociallib')) {
    if (id.isEmpty) return null;
    // The anime corner of the shared catalog is AnimeLib itself: same v5
    // host, /ru/anime/ tree.
    if (isAnime(item)) {
      return ProviderLink(name: 'SocialLib', url: buildAnimelibUrl(id));
    }
    final domain = item.type == MediaType.book ? 'ranobelib.me' : 'mangalib.me';
    return ProviderLink(
        name: 'SocialLib', url: 'https://$domain/ru/${Uri.encodeComponent(id)}');
  }
  if (src.contains('shikimori')) {
    final section =
        item.type == MediaType.tvshow || isAnime(item) ? 'animes' : 'mangas';
    return id.isNotEmpty
        ? ProviderLink(
            name: 'Shikimori',
            url: 'https://shikimori.io/$section/${Uri.encodeComponent(id)}')
        : null;
  }
  if (src.contains('anilist')) {
    if (id.isEmpty) return null;
    final kind = item.type == MediaType.manga ||
            (item.type == MediaType.book &&
                (item.format == 'light_novel' || item.format == 'web_novel'))
        ? 'manga'
        : item.type == MediaType.tvshow || isAnime(item)
            ? 'anime'
            : 'manga';
    return ProviderLink(
        name: 'AniList',
        url: 'https://anilist.co/$kind/${Uri.encodeComponent(id)}');
  }
  if (src.contains('mal') || src.contains('jikan') || src.contains('myanimelist')) {
    return ProviderLink(
      name: 'MyAnimeList',
      url: id.isNotEmpty
          ? 'https://myanimelist.net/anime/${Uri.encodeComponent(id)}'
          : 'https://myanimelist.net',
    );
  }
  if (src.contains('openlibrary')) {
    return ProviderLink(
      name: 'OpenLibrary',
      url: 'https://openlibrary.org${id.startsWith('/') ? id : '/$id'}',
    );
  }
  if (src.contains('igdb')) {
    return id.isNotEmpty
        ? ProviderLink(
            name: 'IGDB',
            url:
                'https://www.igdb.com/games/${Uri.encodeComponent(_slugify(item.title))}')
        : null;
  }
  if (src.contains('steam')) {
    return id.isNotEmpty
        ? ProviderLink(
            name: 'Steam',
            url: 'https://store.steampowered.com/app/${Uri.encodeComponent(id)}')
        : null;
  }
  return null;
}

/// Lowercase hyphenated form RAWG and IGDB use in their URLs.
///
/// TS: toLowerCase + NFKD-нормализация + зачистка combining marks — в Dart
/// String.normalize нет, эквивалент через removeDiacritics (пакет diacritic,
/// решение #30).
String _slugify(String title) {
  return removeDiacritics(title.toLowerCase())
      .replaceAll(RegExp(r'[\u0300-\u036f]'), '')
      .replaceAll(RegExp(r'[^a-z0-9]+'), '-')
      .replaceAll(RegExp(r'^-+|-+$'), '');
}

List<String> tags(MediaItem item, I18nDictionary t) {
  final list = <String>[typeLabel(item, t)];

  switch (item.type) {
    case MediaType.game:
      // The header shows the platform the user picked in Ваша история;
      // the full release list lives in the platform dropdown instead.
      final userPlatform = item.userPlatform?.trim();
      if (userPlatform?.isNotEmpty ?? false) {
        list.add(userPlatform!);
      } else if (item.platform?.isNotEmpty ?? false) {
        list.add(item.platform!);
      }
      break;
    case MediaType.book:
    case MediaType.manga:
      if (item.author?.isNotEmpty ?? false) list.add(item.author!);
      break;
    case MediaType.movie:
      if (item.studio?.isNotEmpty ?? false) list.add(item.studio!);
      if (item.director?.isNotEmpty ?? false) list.add(item.director!);
      break;
    case MediaType.tvshow:
      if (item.studio?.isNotEmpty ?? false) list.add(item.studio!);
      if (item.network?.isNotEmpty ?? false) list.add(item.network!);
      break;
  }

  return list.where((s) => s.isNotEmpty).toSet().toList();
}

String releaseStatusLabel(MediaItem item, I18nDictionary t) {
  final raw = item.releaseStatus?.trim().toUpperCase();

  if (item.type == MediaType.game) {
    final isRu = t.locale.wire == 'ru';
    const comingSoonRu = 'Скоро выйдет', comingSoonEn = 'Coming Soon';
    const earlyAccessRu = 'Ранний доступ', earlyAccessEn = 'Early Access';
    const fullReleaseRu = 'Релиз', fullReleaseEn = 'Full Release';

    if (raw != null && raw.isNotEmpty) {
      if (raw.contains('COMING') ||
          raw.contains('NOT_YET') ||
          raw.contains('UPCOMING') ||
          raw.contains('СКОРО')) {
        return isRu ? comingSoonRu : comingSoonEn;
      }
      if (raw.contains('EARLY') || raw.contains('РАННИЙ')) {
        return isRu ? earlyAccessRu : earlyAccessEn;
      }
      if (raw.contains('FULL') ||
          raw.contains('RELEASE') ||
          raw.contains('FINISHED') ||
          raw.contains('COMPLETED') ||
          raw.contains('РЕЛИЗ')) {
        return isRu ? fullReleaseRu : fullReleaseEn;
      }
    }
    if (item.releaseDate != null) {
      final start = _tryParseDate(item.releaseDate!);
      if (start != null && start.isAfter(DateTime.now())) {
        return isRu ? comingSoonRu : comingSoonEn;
      }
    }
    return isRu ? fullReleaseRu : fullReleaseEn;
  }

  if (raw != null && raw.isNotEmpty) {
    if (raw == 'RELEASING' || raw == 'CURRENT' || raw == 'RETURNING SERIES') {
      return t.tr('detail.releaseStatuses.releasing');
    }
    if (raw == 'FINISHED' || raw == 'COMPLETED' || raw == 'ENDED') {
      return t.tr('detail.releaseStatuses.finished');
    }
    if (raw == 'NOT_YET_RELEASED' ||
        raw == 'UPCOMING' ||
        raw == 'IN PRODUCTION') {
      return t.tr('detail.releaseStatuses.notYetReleased');
    }
    if (raw == 'CANCELLED' || raw == 'CANCELED') {
      return t.tr('detail.releaseStatuses.cancelled');
    }
    if (raw == 'HIATUS' || raw == 'ON HIATUS') {
      return t.tr('detail.releaseStatuses.hiatus');
    }
  }

  // Fallback: calculate from dates if no API status
  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);

  if (item.endDate != null) {
    final end = _tryParseDate(item.endDate!);
    if (end != null && !end.isAfter(today)) {
      return t.tr('detail.releaseStatuses.finished');
    }
  }

  if (item.releaseDate != null) {
    final start = _tryParseDate(item.releaseDate!);
    if (start != null) {
      if (start.isAfter(today)) {
        return t.tr('detail.releaseStatuses.notYetReleased');
      }
      return t.tr('detail.releaseStatuses.releasing');
    }
  }

  return t.tr('detailModal.valueEmpty');
}

/// Chapters for the detail screen, read from the same `totalChapters` the card
/// renders.
///
/// This used to prefer the volume sum whenever the volumes carried chapter
/// counts, which made "Характеристики" show one number while the card next to
/// it showed another for the same title. The counter is reconciled from the
/// volumes on refresh, so one field is the single source.
({int current, int? total}) mangaChapterProgress(MediaItem item) {
  if (item.type != MediaType.manga) {
    return (current: 0, total: null);
  }
  // TS-тип обещает number, но runtime-поле бывает null — null → 0 (типовой
  // фикс вместо «null» в UI).
  return (current: item.currentChapter ?? 0, total: item.totalChapters);
}

ProgressInfo? readProgress(MediaItem item, I18nDictionary t) {
  switch (item.type) {
    case MediaType.game:
      return ProgressInfo(
        current: item.hoursPlayed ?? 0,
        total: null,
        editable: true,
        label: t.tr('detail.hoursLabel'),
      );
    case MediaType.book:
      final isNovel =
          item.format == 'light_novel' || item.format == 'web_novel';
      return ProgressInfo(
        current: isNovel ? (item.currentChapter ?? 0) : (item.currentPage ?? 0),
        total: isNovel ? item.totalChapters : item.totalPages,
        editable: true,
        label: isNovel
            ? t.tr('detail.chaptersLabel')
            : t.tr('detail.pagesLabel'),
      );
    case MediaType.manga:
      final chapters = mangaChapterProgress(item);
      return ProgressInfo(
        current: chapters.current,
        total: chapters.total,
        editable: true,
        label: t.tr('detail.chaptersLabel'),
      );
    case MediaType.tvshow:
      return ProgressInfo(
        current: item.totalEpisodesWatched ?? 0,
        total: item.totalEpisodesCount,
        editable: false,
        label: t.tr('detail.episodesLabel'),
      );
    default:
      return null;
  }
}

/// Joins the native and romanized titles the source reported, skipping any
/// that duplicates the main one, so "Re:Zero" shows "Re:ゼロ… · Re:Zero kara…"
/// below the headline instead of repeating it.
String? joinOriginalTitle(
    String title, String? originalTitle, String? romajiTitle) {
  final variants = <String>[];
  for (final raw in [originalTitle, romajiTitle]) {
    final value = raw?.trim();
    if (value != null && value.isNotEmpty && value != title) {
      if (!variants.contains(value)) variants.add(value);
    }
  }
  return variants.isNotEmpty ? variants.join(' · ') : null;
}

/// All types: the source's native and/or romanized title, minus what the
/// headline already says.
String? readOriginalTitle(MediaDetail item) {
  // `"romajiTitle" in item` — поле есть у обоих классов Dart-иерархии.
  return joinOriginalTitle(item.title, item.originalTitle, item.romajiTitle);
}

/// The transliterated title, for every type that stores one. Game and book
/// have none.
String? readRomajiTitle(MediaItem item) {
  if (item.type == MediaType.game || item.type == MediaType.book) return null;
  final value = item.romajiTitle?.trim();
  return (value != null && value.isNotEmpty) ? value : null;
}

String formatDate(String? value, I18nDictionary t) {
  if (value == null || value.isEmpty) return t.tr('detailModal.dateEmpty');
  final parsed = _tryParseDate(value);
  if (parsed == null) return t.tr('detailModal.dateEmpty');
  initializeDateFormatting(t.locale.wire, null);
  return DateFormat.yMMMd(t.locale.wire).format(parsed);
}

/// Renders only the precision the source actually provided. A source that
/// knows just the year must not be padded into "1 January", so the stored
/// releaseYear carries the fallback.
///
/// The end date is a different case: a missing end date means "still running",
/// so it must never borrow the start date's year. That is why the year
/// fallback only applies to the start row.
///
/// TS различал `formatReleaseDate(item)` и `formatReleaseDate(item,
/// item.endDate)` по факту передачи второго аргумента — в Dart это
/// [isEndDate] + [explicitDate] (named-пара).
String formatReleaseDate(
  MediaItem item,
  I18nDictionary t, {
  String? explicitDate,
  bool isEndDate = false,
}) {
  final raw = isEndDate ? explicitDate : item.releaseDate;

  if (raw != null && raw.isNotEmpty) return formatDate(raw, t);
  if (isEndDate) return t.tr('detailModal.dateEmpty');

  final year = item.releaseYear;
  if (year != null && year > 0) {
    return t.locale.wire == 'ru' ? '$year год' : '$year';
  }
  return t.tr('detailModal.dateEmpty');
}

/// Number.MAX_SAFE_INTEGER.
const int _maxSafeInteger = 9007199254740991;

int orderOf(MediaItem item) => item.franchiseOrder ?? _maxSafeInteger;

List<EpisodeRow> buildEpisodes(TvSeason value, I18nDictionary t) {
  var parsed = const <Map<String, Object?>>[];
  if (value.episodesData?.isNotEmpty ?? false) {
    try {
      final decoded = jsonDecode(value.episodesData!);
      if (decoded is List) {
        parsed = decoded.whereType<Map>().cast<Map<String, Object?>>().toList();
      }
    } catch (_) {
      // Битый JSON → пустой список (как пустой catch в TS).
    }
  }
  final total = value.totalEpisodes > parsed.length
      ? value.totalEpisodes
      : parsed.length;
  final watched = value.currentEpisode > 0 ? value.currentEpisode : 0;
  // 1-в-1 с TS: min(total, max(watched, maxEpisodesPerSeason)) — cap режет
  // только не-просмотренный хвост, а не просмотренные строки.
  final limit = math.min(total, math.max(watched, maxEpisodesPerSeason));

  return List.generate(limit, (index) {
    final number = index + 1;
    final found =
        parsed.firstWhereOrNull((p) => (p['number'] as num?)?.toInt() == number);
    return EpisodeRow(
      id: '${value.id}:$number',
      number: number,
      title: (found?['title'] as String?)?.isNotEmpty ?? false
          ? found!['title'] as String
          : t.tf('detail.episodeTitle', [number]),
      airDate: (found?['airDate'] as String?) ?? value.airDate,
      description: (found?['description'] as String?) ?? value.notes,
      watched: number <= watched,
    );
  });
}

/// Цвета статус-круга для related-сетки/таймлайна. Намеренно отдельно от
/// mediaLabels.statusBadgeClasses (пилюли карточек библиотеки). CSS-строки
/// исходника → типизированный набор (конвенция statusBadgeClasses);
/// color-mix(x, transparent N%) ≈ alpha N/100.
class RelatedStatusColors {
  final Color background;
  final Color text;
  final Color border;
  final Color ring;

  const RelatedStatusColors({
    required this.background,
    required this.text,
    required this.border,
    required this.ring,
  });
}

RelatedStatusColors relatedStatusColors(MediaStatus status) {
  switch (status) {
    case MediaStatus.completed:
      return const RelatedStatusColors(
        background: Color(0xFF228B57), // --color-brand-green
        text: Color(0xFFFFFFFF),
        border: Color(0xCC86EFAC), // success-soft 80%
        ring: Color(0x4D86EFAC), // success-soft 30%
      );
    case MediaStatus.inProgress:
      return const RelatedStatusColors(
        background: Color(0xFF2563EB), // --color-brand-blue
        text: Color(0xFFFFFFFF),
        border: Color(0xCC93C5FD), // ink-faint 80%
        ring: Color(0x4D93C5FD), // ink-faint 30%
      );
    case MediaStatus.onHold:
      return const RelatedStatusColors(
        background: Color(0xFFD97706), // --color-warning-line
        text: Color(0xFFFFFFFF),
        border: Color(0xCCFCD34D), // amber-300/80
        ring: Color(0x4DFCD34D), // amber-300/30
      );
    case MediaStatus.dropped:
      return const RelatedStatusColors(
        background: Color(0xFFB92B42), // --color-danger-line
        text: Color(0xFFFFFFFF),
        border: Color(0xCCFDA4AF), // rose-300/80
        ring: Color(0x4DFDA4AF), // rose-300/30
      );
    case MediaStatus.planned:
      return const RelatedStatusColors(
        background: Color(0xFF2A3040), // --color-track
        text: Color(0xFFF1F5F9), // slate-100
        border: Color(0xB394A3B8), // slate-400/70
        ring: Color(0x3394A3B8), // slate-400/20
      );
  }
}

/// Relation label for a related entry, falling back to its media format.
String formatMediaDisplayType(
    String type, String? format, I18nDictionary t) {
  final isRu = t.locale.wire == 'ru';
  if (type == 'game') return isRu ? 'Игра' : 'Game';
  if (type == 'book') return isRu ? 'Книга' : 'Book';
  final f = format?.toUpperCase();
  if (f == 'MOVIE') return t.tr('detail.formats.movie');
  if (f == 'TV' || f == 'TV_SHORT') return t.tr('detail.formats.tv');
  if (f == 'OVA') return t.tr('detail.formats.ova');
  if (f == 'ONA') return t.tr('detail.formats.ona');
  if (f == 'SPECIAL') return t.tr('detail.formats.special');
  if (f == 'MANGA') return t.tr('detail.formats.manga');
  if (f == 'NOVEL') return t.tr('detail.formats.novel');
  if (f == 'ONE_SHOT') return t.tr('detail.formats.oneShot');
  if (f == 'MUSIC') return t.tr('detail.formats.music');
  return type == 'manga'
      ? t.tr('detail.formats.manga')
      : type == 'movie'
          ? t.tr('detail.formats.movie')
          : t.tr('detail.formats.tv');
}

String formatRelationType(String? relType, I18nDictionary t) {
  switch (relType) {
    case 'SEQUEL':
      return t.tr('detail.relations.sequel');
    case 'PREQUEL':
      return t.tr('detail.relations.prequel');
    case 'ADAPTATION':
      return t.tr('detail.relations.adaptation');
    case 'SIDE_STORY':
      return t.tr('detail.relations.sideStory');
    case 'SPIN_OFF':
      return t.tr('detail.relations.spinOff');
    case 'SUMMARY':
      return t.tr('detail.relations.summary');
    case 'ALTERNATIVE':
      return t.tr('detail.relations.alternative');
    case 'CHARACTER':
      return t.tr('detail.relations.character');
    default:
      return t.tr('detail.relations.other');
  }
}

String currentFormatLabel(MediaItem item, I18nDictionary t) {
  return isTvShowDetail(item)
      ? t.tr('detail.formats.tv')
      : item.type == MediaType.movie
          ? t.tr('detail.formats.movie')
          : item.type == MediaType.manga
              ? t.tr('detail.formats.manga')
              : item.type.wire;
}

/// A film or book whose release date has already passed. Sources keep
/// reporting "releasing" for titles that shipped years ago, which is what put
/// an "Онгоинг" badge on a finished Dune.
bool _hasAlreadyReleased(MediaItem item) {
  if (item.releaseDate != null) {
    final parsed = _tryParseDate(item.releaseDate!);
    // NaN <= Date.now() → false в TS: невалидная дата → false.
    return parsed != null &&
        parsed.millisecondsSinceEpoch <=
            DateTime.now().millisecondsSinceEpoch;
  }
  return item.releaseYear != null &&
      item.releaseYear! <= DateTime.now().year;
}

List<String> _parseGenresList(Object? genres) {
  if (genres == null) return const [];
  if (genres is List) {
    return genres.map((g) => g.toString().trim()).where((g) => g.isNotEmpty).toList();
  }
  if (genres is String) {
    final trimmed = genres.trim();
    if (trimmed.isEmpty) return const [];
    if (trimmed.startsWith('[') && trimmed.endsWith(']')) {
      try {
        final parsed = jsonDecode(trimmed);
        if (parsed is List) {
          return parsed
              .map((g) => g.toString().trim())
              .where((g) => g.isNotEmpty)
              .toList();
        }
      } catch (_) {
        // Битый JSON → split по запятой ниже.
      }
    }
    return trimmed
        .split(',')
        .map((g) => g.trim())
        .where((g) => g.isNotEmpty)
        .toList();
  }
  return const [];
}

List<SpecRow> specRows(MediaItem item, I18nDictionary t) {
  final empty = t.tr('detailModal.valueEmpty');
  final rows = <SpecRow>[
    SpecRow(label: t.tr('detail.formatLabel'), value: formatLabel(item, t)),
  ];

  if (item.type == MediaType.game) {
    rows.add(SpecRow(
      label: t.locale.wire == 'ru' ? 'Дата релиза' : 'Release date',
      value: formatReleaseDate(item, t),
    ));
    rows.add(SpecRow(
      label: t.tr('status.label'),
      value: releaseStatusLabel(item, t),
    ));
    final tagsValue = (item.tags ?? const <String>[]).join(', ').trim();
    rows.add(SpecRow(
      label: t.locale.wire == 'ru' ? 'Теги' : 'Tags',
      value: tagsValue.isNotEmpty ? tagsValue : '—',
    ));
  } else if (item.type == MediaType.movie || item.type == MediaType.book) {
    // A film and a book are released once: the "start / end" pair was a
    // series-shaped row pair shown on items that cannot have an end, so one
    // row reads as an unfinished run.
    rows.add(SpecRow(
      label: item.type == MediaType.movie
          ? (t.locale.wire == 'ru' ? 'Дата релиза' : 'Release date')
          : (t.locale.wire == 'ru' ? 'Дата публикации' : 'Publication date'),
      value: formatReleaseDate(item, t),
    ));

    // "Онгоинг" on a released film or book is the source's stale status, not
    // the user's state.
    final isOngoing =
        item.releaseStatus == 'RELEASING' || item.releaseStatus == 'releasing';
    if (!isOngoing || !_hasAlreadyReleased(item)) {
      rows.add(SpecRow(
        label: t.tr('status.label'),
        value: releaseStatusLabel(item, t),
      ));
    }
  } else {
    rows.add(SpecRow(
      label: t.tr('detail.startDateLabel'),
      value: formatReleaseDate(item, t),
    ));
    rows.add(SpecRow(
      label: t.tr('detail.endDateLabel'),
      value: formatReleaseDate(item, t,
          explicitDate: item.endDate, isEndDate: true),
    ));
    rows.add(SpecRow(
      label: t.tr('status.label'),
      value: releaseStatusLabel(item, t),
    ));
  }

  switch (item.type) {
    // Totals only: the current progress lives in the main progress card, a
    // "0 / 12" repeat next to it read as a second, competing counter.
    case MediaType.tvshow:
      rows.add(SpecRow(
        label: t.tr('detail.episodesLabel'),
        value: t.tf('card.episodesTotal', [item.totalEpisodesCount ?? 0]),
      ));
      break;
    case MediaType.book:
      final isNovel =
          item.format == 'light_novel' || item.format == 'web_novel';
      if (isNovel) {
        final totalChapters = item.totalChapters;
        final totalVolumes = item.totalVolumes;
        rows.add(SpecRow(
          label: t.tr('detail.chaptersLabel'),
          value: t.tf('card.chaptersTotal', [totalChapters ?? 0]),
        ));
        if (totalVolumes != null && totalVolumes > 0) {
          rows.add(SpecRow(
            label: t.tr('detail.volumesLabel'),
            value: '$totalVolumes',
          ));
        }
      } else {
        rows.add(SpecRow(
          label: t.tr('detail.pagesLabel'),
          value: t.tf('card.pagesTotal', [item.totalPages ?? 0]),
        ));
      }
      break;
    case MediaType.manga:
      final chapters = mangaChapterProgress(item);
      rows.add(SpecRow(
        label: t.tr('detail.chaptersLabel'),
        value: t.tf('card.chaptersTotal', [chapters.total ?? 0]),
      ));

      // TS runtime-cast `(item as { volumes?: unknown }).volumes` — список
      // томов живёт в [MediaDetail].
      final vols = item is MediaDetail ? item.volumes : null;
      final totalVols = item.totalVolumes ?? vols?.length;
      rows.add(SpecRow(
        label: t.tr('detail.volumesLabel'),
        value: totalVols != null && totalVols > 0 ? '$totalVols' : '—',
      ));
      break;
    case MediaType.game:
      // Hours played removed from specRows, stays only in "Ваша история"
      break;
    case MediaType.movie:
      break;
  }

  if (item.type == MediaType.movie || item.type == MediaType.tvshow) {
    final durationMinutes = item.durationMinutes ?? 0;
    final duration = durationMinutes > 0
        ? item.type == MediaType.movie
            ? t.tf('card.movie', [durationMinutes])
            : '$durationMinutes ${t.tr('detail.minPerEp')}'
        : empty;
    rows.add(SpecRow(label: t.tr('detail.durationLabel'), value: duration));
  }

  switch (item.type) {
    case MediaType.tvshow:
    case MediaType.movie:
      rows.add(SpecRow(
        label: t.tr('detailModal.studio'),
        value: item.studio?.isNotEmpty ?? false ? item.studio! : empty,
      ));
      // A romaji title only means something for anime; a live-action show or
      // film has an original title, not a romanized one, so showing the row
      // there is just noise.
      if (isAnime(item) && (item.romajiTitle?.isNotEmpty ?? false)) {
        rows.add(SpecRow(
          label: t.tr('detail.romajiTitle'),
          value: item.romajiTitle!,
        ));
      }
      break;
    case MediaType.book:
    case MediaType.manga:
      rows.add(SpecRow(
        label: t.tr('detailModal.author'),
        value: item.author?.isNotEmpty ?? false ? item.author! : empty,
      ));
      // A romaji title only means something for anime; see the comment above.
      if (item.type == MediaType.manga &&
          (item.romajiTitle?.isNotEmpty ?? false)) {
        rows.add(SpecRow(
          label: t.tr('detail.romajiTitle'),
          value: item.romajiTitle!,
        ));
      }
      break;
    case MediaType.game:
      rows.add(SpecRow(
        label: t.tr('detailModal.platform'),
        value: item.platform?.isNotEmpty ?? false ? item.platform! : empty,
      ));
      break;
  }

  final genreList = formatGenresList(_parseGenresList(item.genres), t, t.locale);
  rows.add(SpecRow(
    label: t.tr('detail.genresLabel'),
    value: genreList.isNotEmpty ? genreList.join(', ') : '—',
    badges: genreList.isNotEmpty ? genreList : null,
  ));

  final link = providerLink(item);
  final primarySource = primaryLinkedSource(item)?.source;
  final targetSource = link?.name ??
      (primarySource ?? item.externalSource ?? dataSource(item));
  final importSrc = item.importSource?.trim();
  final showLineage = (importSrc?.isNotEmpty ?? false) &&
      (item.externalSource?.isNotEmpty ?? false) &&
      importSrc!.toLowerCase() != item.externalSource!.toLowerCase() &&
      importSrc.toLowerCase() != targetSource.toLowerCase();

  rows.add(SpecRow(
    label: t.tr('detail.source'),
    value: targetSource,
    href: link?.url,
    importSource: showLineage ? importSrc : null,
  ));

  return rows;
}

/// TS `new Date(value)`: date-only строка ('YYYY-MM-DD') → UTC-полночь, с
/// временем без зоны → локальное, с 'Z' → UTC. DateTime.tryParse даёт local
/// для date-only — нормализуем к UTC-полуночи 1-в-1 с JS.
DateTime? _tryParseDate(String value) {
  final parsed = DateTime.tryParse(value);
  if (parsed == null) return null;
  if (RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(value)) {
    return DateTime.utc(parsed.year, parsed.month, parsed.day);
  }
  return parsed;
}
