/// Порт `mediatracker-ui/src/features/edit-media/modules/moduleTypes.ts`.
///
/// Тип-специфичный бандл полей редактора — один биндинг-объект, чтобы
/// CategoryFieldsModule вставлялся в любой экран одним пропом. Все значения —
/// форм-строки/булевы; сборка payload — работа вызывающего.
library;

import 'package:tsundoku_flutter/shared/types/models.dart';

/// Сезонный драфт (тип из create-media/TvShowFormFields.svelte —
/// строковые поля формы; payload строит вызывающий).
class SeasonDraft {
  final String seasonNumber;
  final String title;
  final String totalEpisodes;

  const SeasonDraft({
    required this.seasonNumber,
    required this.title,
    required this.totalEpisodes,
  });

  SeasonDraft copyWith({
    String? seasonNumber,
    String? title,
    String? totalEpisodes,
  }) =>
      SeasonDraft(
        seasonNumber: seasonNumber ?? this.seasonNumber,
        title: title ?? this.title,
        totalEpisodes: totalEpisodes ?? this.totalEpisodes,
      );

  @override
  bool operator ==(Object other) =>
      other is SeasonDraft &&
      other.seasonNumber == seasonNumber &&
      other.title == title &&
      other.totalEpisodes == totalEpisodes;

  @override
  int get hashCode => Object.hash(seasonNumber, title, totalEpisodes);
}

/// `CategoryDraft`: game/movie/tvshow/book/manga поля в одной корзине.
class CategoryDraft {
  final String platform;
  final String hoursPlayed;
  final String author;
  final String bookFormat;
  final String totalPages;
  final String totalChapters;
  final String bookTotalVolumes;
  final String currentVolume;
  final String durationMinutes;
  final bool isAnime;
  final String studio;
  final String network;
  final List<SeasonDraft> seasons;

  const CategoryDraft({
    required this.platform,
    required this.hoursPlayed,
    required this.author,
    required this.bookFormat,
    required this.totalPages,
    required this.totalChapters,
    required this.bookTotalVolumes,
    required this.currentVolume,
    required this.durationMinutes,
    required this.isAnime,
    required this.studio,
    required this.network,
    required this.seasons,
  });

  /// `emptyCategoryDraft()` — каждый вызов возвращает новый объект, чтобы
  /// вызывающий владел им в `$state`.
  static CategoryDraft empty() => CategoryDraft(
        platform: '',
        hoursPlayed: '',
        author: '',
        bookFormat: 'book',
        totalPages: '',
        totalChapters: '',
        bookTotalVolumes: '',
        currentVolume: '',
        durationMinutes: '',
        isAnime: false,
        studio: '',
        network: '',
        seasons: <SeasonDraft>[],
      );

  CategoryDraft copyWith({
    String? platform,
    String? hoursPlayed,
    String? author,
    String? bookFormat,
    String? totalPages,
    String? totalChapters,
    String? bookTotalVolumes,
    String? currentVolume,
    String? durationMinutes,
    bool? isAnime,
    String? studio,
    String? network,
    List<SeasonDraft>? seasons,
  }) =>
      CategoryDraft(
        platform: platform ?? this.platform,
        hoursPlayed: hoursPlayed ?? this.hoursPlayed,
        author: author ?? this.author,
        bookFormat: bookFormat ?? this.bookFormat,
        totalPages: totalPages ?? this.totalPages,
        totalChapters: totalChapters ?? this.totalChapters,
        bookTotalVolumes: bookTotalVolumes ?? this.bookTotalVolumes,
        currentVolume: currentVolume ?? this.currentVolume,
        durationMinutes: durationMinutes ?? this.durationMinutes,
        isAnime: isAnime ?? this.isAnime,
        studio: studio ?? this.studio,
        network: network ?? this.network,
        seasons: seasons ?? this.seasons,
      );
}

/// Цитаты редактируются как готовые объекты и сериализуются в `quotesJson`
/// вызывающим — модуль свободен от API-зависимостей.
typedef QuoteDraft = MediaQuote;

/// Порядок типов редактора (1-в-1 с EDIT_MEDIA_TYPES).
const List<String> kEditMediaTypes = <String>[
  'game',
  'movie',
  'tvshow',
  'book',
  'manga',
];
