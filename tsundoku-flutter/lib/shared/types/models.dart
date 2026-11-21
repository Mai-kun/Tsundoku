/// 1:1 port of `mediatracker-ui/src/shared/types/models.ts`.
///
/// Стратегия (зафиксирована в FLUTTER_MIGRATION.md, «⚖️ Спорные решения и развилки»):
/// - сервер шлёт список **плоским** `MediaListDto`, поэтому `GameMedia`/`BookMedia`/...
///   варианты и `MediaBase` слиты в один плоский класс [MediaItem] с полем `type`
///   (решение #4); [MediaDetail] расширяет его detail-полями `MediaDetailFields`;
/// - поля TS-вариантов, суженные до non-null (`MovieMedia.durationMinutes`), остаются
///   nullable как в плоском DTO; инвариант поддерживается потребителями (решение #4);
/// - `Record<number, number>` → `Map<int, double>` (JSON-ключи приводятся к int),
///   `Record<string, number>` → `Map<String, double>` (решение #3);
/// - `string[] | string` (genres/tags) нормализуется в `List<String>`
///   (строка → split(',') с trim) — решение #3;
/// - read-only модели (TS interface без отправки на сервер) не получают `toJson`
///   (YAGNI) — сериализация только для payload'ов запросов.
library;

import 'enums.dart';

// ---------------------------------------------------------------------------
// Небольшие утилиты парсинга (lenient, как runtime-JS в Svelte).
// ---------------------------------------------------------------------------

int? _int(Object? v) => v == null ? null : (v as num).toInt();

double? _double(Object? v) => v == null ? null : (v as num).toDouble();

String? _str(Object? v) => v as String?;

bool? _bool(Object? v) => v as bool?;

/// `string[] | string | null` → `List<String>?` (строка → split(',') + trim).
List<String>? _strOrList(Object? v) {
  if (v == null) return null;
  if (v is String) {
    if (v.isEmpty) return const <String>[];
    return v.split(',').map((g) => g.trim()).toList();
  }
  return (v as List<Object?>).cast<String>().toList();
}

// ---------------------------------------------------------------------------
// Мелкие сущности.
// ---------------------------------------------------------------------------

class ExternalRating {
  final String source;
  final double rating;
  final double? score;
  final int? votes;

  const ExternalRating({
    required this.source,
    required this.rating,
    required this.score,
    required this.votes,
  });

  factory ExternalRating.fromJson(Map<String, dynamic> json) => ExternalRating(
        source: json['source'] as String,
        rating: (json['rating'] as num).toDouble(),
        score: _double(json['score']),
        votes: _int(json['votes']),
      );

  @override
  bool operator ==(Object other) =>
      other is ExternalRating &&
      other.source == source &&
      other.rating == rating &&
      other.score == score &&
      other.votes == votes;

  @override
  int get hashCode => Object.hash(source, rating, score, votes);
}

class ExternalEpisode {
  final int number;
  final String title;
  final String? airDate;

  const ExternalEpisode({
    required this.number,
    required this.title,
    required this.airDate,
  });

  factory ExternalEpisode.fromJson(Map<String, dynamic> json) =>
      ExternalEpisode(
        number: (json['number'] as num).toInt(),
        title: json['title'] as String,
        airDate: json['airDate'] as String?,
      );

  @override
  bool operator ==(Object other) =>
      other is ExternalEpisode &&
      other.number == number &&
      other.title == title &&
      other.airDate == airDate;

  @override
  int get hashCode => Object.hash(number, title, airDate);
}

class MediaQuote {
  final String id;
  final String text;
  /// Например: "стр. 142" или "Гл. 5".
  final String? pageOrContext;
  final String createdAt;

  const MediaQuote({
    required this.id,
    required this.text,
    required this.pageOrContext,
    required this.createdAt,
  });

  factory MediaQuote.fromJson(Map<String, dynamic> json) => MediaQuote(
        id: json['id'] as String,
        text: json['text'] as String,
        pageOrContext: json['pageOrContext'] as String?,
        createdAt: json['createdAt'] as String,
      );

  @override
  bool operator ==(Object other) =>
      other is MediaQuote &&
      other.id == id &&
      other.text == text &&
      other.pageOrContext == pageOrContext &&
      other.createdAt == createdAt;

  @override
  int get hashCode => Object.hash(id, text, pageOrContext, createdAt);
}

class MediaCoverItem {
  final String id;
  final String thumbUrl;
  final String originalUrl;
  final String? source;
  /// The provider URL this variant was downloaded from; lets a refresh reuse it.
  final String? sourceUrl;
  final String addedAt;

  const MediaCoverItem({
    required this.id,
    required this.thumbUrl,
    required this.originalUrl,
    required this.source,
    required this.sourceUrl,
    required this.addedAt,
  });

  factory MediaCoverItem.fromJson(Map<String, dynamic> json) =>
      MediaCoverItem(
        id: json['id'] as String,
        thumbUrl: json['thumbUrl'] as String,
        originalUrl: json['originalUrl'] as String,
        source: json['source'] as String?,
        sourceUrl: json['sourceUrl'] as String?,
        addedAt: json['addedAt'] as String,
      );

  @override
  bool operator ==(Object other) =>
      other is MediaCoverItem &&
      other.id == id &&
      other.thumbUrl == thumbUrl &&
      other.originalUrl == originalUrl &&
      other.source == source &&
      other.sourceUrl == sourceUrl &&
      other.addedAt == addedAt;

  @override
  int get hashCode => Object.hash(id, thumbUrl, originalUrl, source, sourceUrl, addedAt);
}

/// One file attached to a title (book, archive, save).
class MediaAttachment {
  final String id;
  final String fileName;
  final int fileSizeBytes;
  final String? contentType;
  final String addedAt;

  const MediaAttachment({
    required this.id,
    required this.fileName,
    required this.fileSizeBytes,
    required this.contentType,
    required this.addedAt,
  });

  factory MediaAttachment.fromJson(Map<String, dynamic> json) =>
      MediaAttachment(
        id: json['id'] as String,
        fileName: json['fileName'] as String,
        fileSizeBytes: (json['fileSizeBytes'] as num).toInt(),
        contentType: json['contentType'] as String?,
        addedAt: json['addedAt'] as String,
      );

  @override
  bool operator ==(Object other) =>
      other is MediaAttachment &&
      other.id == id &&
      other.fileName == fileName &&
      other.fileSizeBytes == fileSizeBytes &&
      other.contentType == contentType &&
      other.addedAt == addedAt;

  @override
  int get hashCode => Object.hash(id, fileName, fileSizeBytes, contentType, addedAt);
}

/// One user screenshot of the title's gallery.
class MediaGalleryItem {
  final String id;
  final String thumbUrl;
  final String originalUrl;
  final String? title;
  final String addedAt;

  const MediaGalleryItem({
    required this.id,
    required this.thumbUrl,
    required this.originalUrl,
    required this.title,
    required this.addedAt,
  });

  factory MediaGalleryItem.fromJson(Map<String, dynamic> json) =>
      MediaGalleryItem(
        id: json['id'] as String,
        thumbUrl: json['thumbUrl'] as String,
        originalUrl: json['originalUrl'] as String,
        title: json['title'] as String?,
        addedAt: json['addedAt'] as String,
      );

  @override
  bool operator ==(Object other) =>
      other is MediaGalleryItem &&
      other.id == id &&
      other.thumbUrl == thumbUrl &&
      other.originalUrl == originalUrl &&
      other.title == title &&
      other.addedAt == addedAt;

  @override
  int get hashCode => Object.hash(id, thumbUrl, originalUrl, title, addedAt);
}

/// Inline-интерфейс `linkedSources` из `MediaDetailFields` (имя дано портом).
class LinkedSource {
  final String source;
  final String externalId;
  final String? url;
  final bool isPrimary;
  final String? title;
  final List<String>? providedFields;

  const LinkedSource({
    required this.source,
    required this.externalId,
    required this.url,
    required this.isPrimary,
    required this.title,
    required this.providedFields,
  });

  factory LinkedSource.fromJson(Map<String, dynamic> json) => LinkedSource(
        source: json['source'] as String,
        externalId: json['externalId'] as String,
        url: json['url'] as String?,
        isPrimary: json['isPrimary'] as bool,
        title: json['title'] as String?,
        providedFields:
            (json['providedFields'] as List<Object?>?)?.cast<String>().toList(),
      );

  Map<String, dynamic> toJson() => <String, dynamic>{
        'source': source,
        'externalId': externalId,
        'url': url,
        'isPrimary': isPrimary,
        'title': title,
        'providedFields': providedFields,
      };

  @override
  bool operator ==(Object other) =>
      other is LinkedSource &&
      other.source == source &&
      other.externalId == externalId &&
      other.url == url &&
      other.isPrimary == isPrimary &&
      other.title == title &&
      other.providedFields == providedFields;

  @override
  int get hashCode =>
      Object.hash(source, externalId, url, isPrimary, title, providedFields);
}

// ---------------------------------------------------------------------------
// MediaBase + варианты → плоский MediaItem (решение #4).
// ---------------------------------------------------------------------------

/// The card/list shape. Сервер (`MediaListDto`) шлёт список плоским DTO, поэтому
/// `MediaBase` и все `*Media`-варианты слиты в один класс; `type` определяет,
/// какие вариантные поля валидны.
class MediaItem {
  final String id;
  final MediaType type;
  final String title;
  final MediaStatus status;
  /// 1 while the background enrichment of a search hit is still filling this row in; 3 when it found ambiguous matches and parked the row for review.
  final SyncStatus? syncStatus;
  final int? score;
  final String? startedAt;
  final String? finishedAt;
  final String? lastActivityAt;
  final String? dropReason;
  final String? dropNotes;
  final String? coverUrl;
  final String createdAt;
  /// Feeds the cover cache-buster on the server side.
  final String? updatedAt;
  final String? franchiseId;
  final String? franchiseName;
  final int? franchiseOrder;
  final String? externalId;
  final String? externalSource;
  final String? importSource;
  final double? externalRating;
  final int? externalRatingVotes;
  final String? translationLanguage;
  final String? releaseDate;
  final int? releaseYear;
  /// Where the user watched it: a known site or free text.
  final String? watchedOn;
  final String? endDate;
  final String? releaseStatus;
  final String? originalLanguage;
  final String? countryOfOrigin;
  final int? durationMinutes;
  final List<String>? genres;
  final List<String>? tags;
  final String? userPlatform;
  final String? format;
  /// Next scheduled background content check, so the UI can show when an ongoing is polled.
  final String? nextAutoRefreshAt;
  /// Current adaptive interval between auto-refresh checks, in days.
  final int? autoRefreshIntervalDays;
  /// When the last background check ran; null until the first one happened.
  final String? lastAutoRefreshedAt;

  // --- Вариантные поля (game / book / manga / movie / tvshow), плоско. ---
  final String? platform;
  final int? hoursPlayed;
  final String? author;
  final int? currentPage;
  final int? totalPages;
  final int? currentChapter;
  final int? totalChapters;
  final int? currentVolume;
  final int? totalVolumes;
  final String? isbn;
  final String? studio;
  final String? romajiTitle;
  /// manga / manhwa / manhua / oel, derived from the external source.
  final String? mangaFormat;
  final bool? isAnime;
  final String? network;
  final int? totalEpisodesCount;
  final int? totalEpisodesWatched;
  final int? seasonsCount;
  final int? episodeDurationMinutes;
  final String? director;

  const MediaItem({
    required this.id,
    required this.type,
    required this.title,
    required this.status,
    required this.syncStatus,
    required this.score,
    required this.startedAt,
    required this.finishedAt,
    required this.lastActivityAt,
    required this.dropReason,
    required this.dropNotes,
    required this.coverUrl,
    required this.createdAt,
    required this.updatedAt,
    required this.franchiseId,
    required this.franchiseName,
    required this.franchiseOrder,
    required this.externalId,
    required this.externalSource,
    required this.importSource,
    required this.externalRating,
    required this.externalRatingVotes,
    required this.translationLanguage,
    required this.releaseDate,
    required this.releaseYear,
    required this.watchedOn,
    required this.endDate,
    required this.releaseStatus,
    required this.originalLanguage,
    required this.countryOfOrigin,
    required this.durationMinutes,
    required this.genres,
    required this.tags,
    required this.userPlatform,
    required this.format,
    required this.nextAutoRefreshAt,
    required this.autoRefreshIntervalDays,
    required this.lastAutoRefreshedAt,
    required this.platform,
    required this.hoursPlayed,
    required this.author,
    required this.currentPage,
    required this.totalPages,
    required this.currentChapter,
    required this.totalChapters,
    required this.currentVolume,
    required this.totalVolumes,
    required this.isbn,
    required this.studio,
    required this.romajiTitle,
    required this.mangaFormat,
    required this.isAnime,
    required this.network,
    required this.totalEpisodesCount,
    required this.totalEpisodesWatched,
    required this.seasonsCount,
    required this.episodeDurationMinutes,
    required this.director,
  });

  
/// Полиморфная копия для оптимистичных обновлений (прогресс/статус/оценка).
/// Только для MediaItem: MediaDetail.copyWith потерял бы detail-поля — там
/// используется пере-парсинг (решение #14).
MediaItem copyWithFields({

    String? id,
    MediaType? type,
    String? title,
    MediaStatus? status,
    SyncStatus? syncStatus,
    int? score,
    String? startedAt,
    String? finishedAt,
    String? lastActivityAt,
    String? dropReason,
    String? dropNotes,
    String? coverUrl,
    String? createdAt,
    String? updatedAt,
    String? franchiseId,
    String? franchiseName,
    int? franchiseOrder,
    String? externalId,
    String? externalSource,
    String? importSource,
    double? externalRating,
    int? externalRatingVotes,
    String? translationLanguage,
    String? releaseDate,
    int? releaseYear,
    String? watchedOn,
    String? endDate,
    String? releaseStatus,
    String? originalLanguage,
    String? countryOfOrigin,
    int? durationMinutes,
    List<String>? genres,
    List<String>? tags,
    String? userPlatform,
    String? format,
    String? nextAutoRefreshAt,
    int? autoRefreshIntervalDays,
    String? lastAutoRefreshedAt,
    String? platform,
    int? hoursPlayed,
    String? author,
    int? currentPage,
    int? totalPages,
    int? currentChapter,
    int? totalChapters,
    int? currentVolume,
    int? totalVolumes,
    String? isbn,
    String? studio,
    String? romajiTitle,
    String? mangaFormat,
    bool? isAnime,
    String? network,
    int? totalEpisodesCount,
    int? totalEpisodesWatched,
    int? seasonsCount,
    int? episodeDurationMinutes,
    String? director,
  }) {
    return MediaItem(
      id: id ?? this.id,
      type: type ?? this.type,
      title: title ?? this.title,
      status: status ?? this.status,
      syncStatus: syncStatus ?? this.syncStatus,
      score: score ?? this.score,
      startedAt: startedAt ?? this.startedAt,
      finishedAt: finishedAt ?? this.finishedAt,
      lastActivityAt: lastActivityAt ?? this.lastActivityAt,
      dropReason: dropReason ?? this.dropReason,
      dropNotes: dropNotes ?? this.dropNotes,
      coverUrl: coverUrl ?? this.coverUrl,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      franchiseId: franchiseId ?? this.franchiseId,
      franchiseName: franchiseName ?? this.franchiseName,
      franchiseOrder: franchiseOrder ?? this.franchiseOrder,
      externalId: externalId ?? this.externalId,
      externalSource: externalSource ?? this.externalSource,
      importSource: importSource ?? this.importSource,
      externalRating: externalRating ?? this.externalRating,
      externalRatingVotes: externalRatingVotes ?? this.externalRatingVotes,
      translationLanguage: translationLanguage ?? this.translationLanguage,
      releaseDate: releaseDate ?? this.releaseDate,
      releaseYear: releaseYear ?? this.releaseYear,
      watchedOn: watchedOn ?? this.watchedOn,
      endDate: endDate ?? this.endDate,
      releaseStatus: releaseStatus ?? this.releaseStatus,
      originalLanguage: originalLanguage ?? this.originalLanguage,
      countryOfOrigin: countryOfOrigin ?? this.countryOfOrigin,
      durationMinutes: durationMinutes ?? this.durationMinutes,
      genres: genres ?? this.genres,
      tags: tags ?? this.tags,
      userPlatform: userPlatform ?? this.userPlatform,
      format: format ?? this.format,
      nextAutoRefreshAt: nextAutoRefreshAt ?? this.nextAutoRefreshAt,
      autoRefreshIntervalDays: autoRefreshIntervalDays ?? this.autoRefreshIntervalDays,
      lastAutoRefreshedAt: lastAutoRefreshedAt ?? this.lastAutoRefreshedAt,
      platform: platform ?? this.platform,
      hoursPlayed: hoursPlayed ?? this.hoursPlayed,
      author: author ?? this.author,
      currentPage: currentPage ?? this.currentPage,
      totalPages: totalPages ?? this.totalPages,
      currentChapter: currentChapter ?? this.currentChapter,
      totalChapters: totalChapters ?? this.totalChapters,
      currentVolume: currentVolume ?? this.currentVolume,
      totalVolumes: totalVolumes ?? this.totalVolumes,
      isbn: isbn ?? this.isbn,
      studio: studio ?? this.studio,
      romajiTitle: romajiTitle ?? this.romajiTitle,
      mangaFormat: mangaFormat ?? this.mangaFormat,
      isAnime: isAnime ?? this.isAnime,
      network: network ?? this.network,
      totalEpisodesCount: totalEpisodesCount ?? this.totalEpisodesCount,
      totalEpisodesWatched: totalEpisodesWatched ?? this.totalEpisodesWatched,
      seasonsCount: seasonsCount ?? this.seasonsCount,
      episodeDurationMinutes: episodeDurationMinutes ?? this.episodeDurationMinutes,
      director: director ?? this.director,
    );
  }

  factory MediaItem.fromJson(Map<String, dynamic> json) => MediaItem(
        id: json['id'] as String,
        type: MediaType.fromWire(json['type'] as String),
        title: json['title'] as String,
        status: MediaStatus.fromValue((json['status'] as num).toInt()),
        syncStatus: json['syncStatus'] == null
            ? null
            : SyncStatus.fromValue((json['syncStatus'] as num).toInt()),
        score: _int(json['score']),
        startedAt: _str(json['startedAt']),
        finishedAt: _str(json['finishedAt']),
        lastActivityAt: _str(json['lastActivityAt']),
        dropReason: _str(json['dropReason']),
        dropNotes: _str(json['dropNotes']),
        coverUrl: _str(json['coverUrl']),
        createdAt: json['createdAt'] as String,
        updatedAt: _str(json['updatedAt']),
        franchiseId: _str(json['franchiseId']),
        franchiseName: _str(json['franchiseName']),
        franchiseOrder: _int(json['franchiseOrder']),
        externalId: _str(json['externalId']),
        externalSource: _str(json['externalSource']),
        importSource: _str(json['importSource']),
        externalRating: _double(json['externalRating']),
        externalRatingVotes: _int(json['externalRatingVotes']),
        translationLanguage: _str(json['translationLanguage']),
        releaseDate: _str(json['releaseDate']),
        releaseYear: _int(json['releaseYear']),
        watchedOn: _str(json['watchedOn']),
        endDate: _str(json['endDate']),
        releaseStatus: _str(json['releaseStatus']),
        originalLanguage: _str(json['originalLanguage']),
        countryOfOrigin: _str(json['countryOfOrigin']),
        durationMinutes: _int(json['durationMinutes']),
        genres: _strOrList(json['genres']),
        tags: _strOrList(json['tags']),
        userPlatform: _str(json['userPlatform']),
        format: _str(json['format']),
        nextAutoRefreshAt: _str(json['nextAutoRefreshAt']),
        autoRefreshIntervalDays: _int(json['autoRefreshIntervalDays']),
        lastAutoRefreshedAt: _str(json['lastAutoRefreshedAt']),
        platform: _str(json['platform']),
        hoursPlayed: _int(json['hoursPlayed']),
        author: _str(json['author']),
        currentPage: _int(json['currentPage']),
        totalPages: _int(json['totalPages']),
        currentChapter: _int(json['currentChapter']),
        totalChapters: _int(json['totalChapters']),
        currentVolume: _int(json['currentVolume']),
        totalVolumes: _int(json['totalVolumes']),
        isbn: _str(json['isbn']),
        studio: _str(json['studio']),
        romajiTitle: _str(json['romajiTitle']),
        mangaFormat: _str(json['mangaFormat']),
        isAnime: _bool(json['isAnime']),
        network: _str(json['network']),
        totalEpisodesCount: _int(json['totalEpisodesCount']),
        totalEpisodesWatched: _int(json['totalEpisodesWatched']),
        seasonsCount: _int(json['seasonsCount']),
        episodeDurationMinutes: _int(json['episodeDurationMinutes']),
        director: _str(json['director']),
      );

  Map<String, dynamic> toJson() => <String, dynamic>{
        'id': id,
        'type': type.wire,
        'title': title,
        'status': status.value,
        'syncStatus': syncStatus?.value,
        'score': score,
        'startedAt': startedAt,
        'finishedAt': finishedAt,
        'lastActivityAt': lastActivityAt,
        'dropReason': dropReason,
        'dropNotes': dropNotes,
        'coverUrl': coverUrl,
        'createdAt': createdAt,
        'updatedAt': updatedAt,
        'franchiseId': franchiseId,
        'franchiseName': franchiseName,
        'franchiseOrder': franchiseOrder,
        'externalId': externalId,
        'externalSource': externalSource,
        'importSource': importSource,
        'externalRating': externalRating,
        'externalRatingVotes': externalRatingVotes,
        'translationLanguage': translationLanguage,
        'releaseDate': releaseDate,
        'releaseYear': releaseYear,
        'watchedOn': watchedOn,
        'endDate': endDate,
        'releaseStatus': releaseStatus,
        'originalLanguage': originalLanguage,
        'countryOfOrigin': countryOfOrigin,
        'durationMinutes': durationMinutes,
        'genres': genres,
        'tags': tags,
        'userPlatform': userPlatform,
        'format': format,
        'nextAutoRefreshAt': nextAutoRefreshAt,
        'autoRefreshIntervalDays': autoRefreshIntervalDays,
        'lastAutoRefreshedAt': lastAutoRefreshedAt,
        'platform': platform,
        'hoursPlayed': hoursPlayed,
        'author': author,
        'currentPage': currentPage,
        'totalPages': totalPages,
        'currentChapter': currentChapter,
        'totalChapters': totalChapters,
        'currentVolume': currentVolume,
        'totalVolumes': totalVolumes,
        'isbn': isbn,
        'studio': studio,
        'romajiTitle': romajiTitle,
        'mangaFormat': mangaFormat,
        'isAnime': isAnime,
        'network': network,
        'totalEpisodesCount': totalEpisodesCount,
        'totalEpisodesWatched': totalEpisodesWatched,
        'seasonsCount': seasonsCount,
        'episodeDurationMinutes': episodeDurationMinutes,
        'director': director,
      };

  @override
  bool operator ==(Object other) =>
      other is MediaItem && other.toJson() == toJson();

  @override
  int get hashCode => toJson().hashCode;
}

// ---------------------------------------------------------------------------
// MediaDetailFields → MediaDetail.
// ---------------------------------------------------------------------------

/// Payload the list endpoint deliberately omits: these are only read by the
/// detail screen, so carrying them for every item in the library was the bulk
/// of the JSON list response. В Dart — поля [MediaDetail] (плоский detail-DTO).
class MediaDetail extends MediaItem {
  final List<MediaCoverItem>? covers;
  /// Files attached to the title (books, archives, saves), rendered by the overview's file block.
  final List<MediaAttachment>? attachments;
  /// The user's screenshot gallery, rendered by the gallery tab.
  final List<MediaGalleryItem>? gallery;
  final String? notes;
  final String? linkedSourcesJson;
  final List<LinkedSource>? linkedSources;
  final String? detailedScoreJson;
  final String? quotesJson;
  final String? description;
  final String? trailerVideoId;
  final List<CastMember>? cast;
  /// Native/romanized title; rendered under the main headline on the detail screen.
  final String? originalTitle;
  /// Every known title variant (English, Romaji, Native, localized) minus the display title.
  final List<String>? altTitles;
  final String? staffJson;
  /// Key crew, already parsed by the server (like recommendations).
  final List<StaffMember>? staff;
  /// Director photo or studio logo, when a provider supplied one.
  final String? creatorImageUrl;
  final String? externalRatingsJson;
  final String? translatedSynopsis;
  final String? unlockedAchievements;
  /// Cached related titles, so the Related tab is populated on a reload.
  final String? relatedMediaJson;
  /// The provider relatedMediaJson was fetched from.
  final String? relatedSource;
  /// Cached achievements / recommendations: written once, replayed on F5.
  final String? achievementsJson;
  final String? recommendationsJson;
  final String? recommendationsUpdatedAt;
  /// The same candidates, already parsed by the server.
  final List<ExternalMedia>? pendingMatches;
  /// The cached recommendations, already parsed by the server.
  final List<ExternalRecommendation>? recommendations;
  /// The user hand-edited this row, so a refresh has to ask instead of overwriting silently.
  final bool? isCustomEdited;
  final List<MangaVolume>? volumes;
  final List<TvSeason>? seasons;

  const MediaDetail({
    // Базовые поля MediaItem.
    required super.id,
    required super.type,
    required super.title,
    required super.status,
    required super.syncStatus,
    required super.score,
    required super.startedAt,
    required super.finishedAt,
    required super.lastActivityAt,
    required super.dropReason,
    required super.dropNotes,
    required super.coverUrl,
    required super.createdAt,
    required super.updatedAt,
    required super.franchiseId,
    required super.franchiseName,
    required super.franchiseOrder,
    required super.externalId,
    required super.externalSource,
    required super.importSource,
    required super.externalRating,
    required super.externalRatingVotes,
    required super.translationLanguage,
    required super.releaseDate,
    required super.releaseYear,
    required super.watchedOn,
    required super.endDate,
    required super.releaseStatus,
    required super.originalLanguage,
    required super.countryOfOrigin,
    required super.durationMinutes,
    required super.genres,
    required super.tags,
    required super.userPlatform,
    required super.format,
    required super.nextAutoRefreshAt,
    required super.autoRefreshIntervalDays,
    required super.lastAutoRefreshedAt,
    required super.platform,
    required super.hoursPlayed,
    required super.author,
    required super.currentPage,
    required super.totalPages,
    required super.currentChapter,
    required super.totalChapters,
    required super.currentVolume,
    required super.totalVolumes,
    required super.isbn,
    required super.studio,
    required super.romajiTitle,
    required super.mangaFormat,
    required super.isAnime,
    required super.network,
    required super.totalEpisodesCount,
    required super.totalEpisodesWatched,
    required super.seasonsCount,
    required super.episodeDurationMinutes,
    required super.director,
    // Detail-поля.
    required this.covers,
    required this.attachments,
    required this.gallery,
    required this.notes,
    required this.linkedSourcesJson,
    required this.linkedSources,
    required this.detailedScoreJson,
    required this.quotesJson,
    required this.description,
    required this.trailerVideoId,
    required this.cast,
    required this.originalTitle,
    required this.altTitles,
    required this.staffJson,
    required this.staff,
    required this.creatorImageUrl,
    required this.externalRatingsJson,
    required this.translatedSynopsis,
    required this.unlockedAchievements,
    required this.relatedMediaJson,
    required this.relatedSource,
    required this.achievementsJson,
    required this.recommendationsJson,
    required this.recommendationsUpdatedAt,
    required this.pendingMatches,
    required this.recommendations,
    required this.isCustomEdited,
    required this.volumes,
    required this.seasons,
  });

  factory MediaDetail.fromJson(Map<String, dynamic> json) {
    final base = MediaItem.fromJson(json);
    return MediaDetail(
      id: base.id,
      type: base.type,
      title: base.title,
      status: base.status,
      syncStatus: base.syncStatus,
      score: base.score,
      startedAt: base.startedAt,
      finishedAt: base.finishedAt,
      lastActivityAt: base.lastActivityAt,
      dropReason: base.dropReason,
      dropNotes: base.dropNotes,
      coverUrl: base.coverUrl,
      createdAt: base.createdAt,
      updatedAt: base.updatedAt,
      franchiseId: base.franchiseId,
      franchiseName: base.franchiseName,
      franchiseOrder: base.franchiseOrder,
      externalId: base.externalId,
      externalSource: base.externalSource,
      importSource: base.importSource,
      externalRating: base.externalRating,
      externalRatingVotes: base.externalRatingVotes,
      translationLanguage: base.translationLanguage,
      releaseDate: base.releaseDate,
      releaseYear: base.releaseYear,
      watchedOn: base.watchedOn,
      endDate: base.endDate,
      releaseStatus: base.releaseStatus,
      originalLanguage: base.originalLanguage,
      countryOfOrigin: base.countryOfOrigin,
      durationMinutes: base.durationMinutes,
      genres: base.genres,
      tags: base.tags,
      userPlatform: base.userPlatform,
      format: base.format,
      nextAutoRefreshAt: base.nextAutoRefreshAt,
      autoRefreshIntervalDays: base.autoRefreshIntervalDays,
      lastAutoRefreshedAt: base.lastAutoRefreshedAt,
      platform: base.platform,
      hoursPlayed: base.hoursPlayed,
      author: base.author,
      currentPage: base.currentPage,
      totalPages: base.totalPages,
      currentChapter: base.currentChapter,
      totalChapters: base.totalChapters,
      currentVolume: base.currentVolume,
      totalVolumes: base.totalVolumes,
      isbn: base.isbn,
      studio: base.studio,
      romajiTitle: base.romajiTitle,
      mangaFormat: base.mangaFormat,
      isAnime: base.isAnime,
      network: base.network,
      totalEpisodesCount: base.totalEpisodesCount,
      totalEpisodesWatched: base.totalEpisodesWatched,
      seasonsCount: base.seasonsCount,
      episodeDurationMinutes: base.episodeDurationMinutes,
      director: base.director,
      covers: (json['covers'] as List<Object?>?)
          ?.map((e) => MediaCoverItem.fromJson(e as Map<String, dynamic>))
          .toList(),
      attachments: (json['attachments'] as List<Object?>?)
          ?.map((e) => MediaAttachment.fromJson(e as Map<String, dynamic>))
          .toList(),
      gallery: (json['gallery'] as List<Object?>?)
          ?.map((e) => MediaGalleryItem.fromJson(e as Map<String, dynamic>))
          .toList(),
      notes: _str(json['notes']),
      linkedSourcesJson: _str(json['linkedSourcesJson']),
      linkedSources: (json['linkedSources'] as List<Object?>?)
          ?.map((e) => LinkedSource.fromJson(e as Map<String, dynamic>))
          .toList(),
      detailedScoreJson: _str(json['detailedScoreJson']),
      quotesJson: _str(json['quotesJson']),
      description: _str(json['description']),
      trailerVideoId: _str(json['trailerVideoId']),
      cast: (json['cast'] as List<Object?>?)
          ?.map((e) => CastMember.fromJson(e as Map<String, dynamic>))
          .toList(),
      originalTitle: _str(json['originalTitle']),
      altTitles: (json['altTitles'] as List<Object?>?)?.cast<String>().toList(),
      staffJson: _str(json['staffJson']),
      staff: (json['staff'] as List<Object?>?)
          ?.map((e) => StaffMember.fromJson(e as Map<String, dynamic>))
          .toList(),
      creatorImageUrl: _str(json['creatorImageUrl']),
      externalRatingsJson: _str(json['externalRatingsJson']),
      translatedSynopsis: _str(json['translatedSynopsis']),
      unlockedAchievements: _str(json['unlockedAchievements']),
      relatedMediaJson: _str(json['relatedMediaJson']),
      relatedSource: _str(json['relatedSource']),
      achievementsJson: _str(json['achievementsJson']),
      recommendationsJson: _str(json['recommendationsJson']),
      recommendationsUpdatedAt: _str(json['recommendationsUpdatedAt']),
      pendingMatches: (json['pendingMatches'] as List<Object?>?)
          ?.map((e) => ExternalMedia.fromJson(e as Map<String, dynamic>))
          .toList(),
      recommendations: (json['recommendations'] as List<Object?>?)
          ?.map((e) => ExternalRecommendation.fromJson(e as Map<String, dynamic>))
          .toList(),
      isCustomEdited: _bool(json['isCustomEdited']),
      volumes: (json['volumes'] as List<Object?>?)
          ?.map((e) => MangaVolume.fromJson(e as Map<String, dynamic>))
          .toList(),
      seasons: (json['seasons'] as List<Object?>?)
          ?.map((e) => TvSeason.fromJson(e as Map<String, dynamic>))
          .toList(),
    );
  }

  @override
  bool operator ==(Object other) =>
      other is MediaDetail && other.toJson() == toJson();

  @override
  int get hashCode => toJson().hashCode;
}

/// `isTvShowDetail(item)`: 1-в-1 с TS (`type === "tvshow" && "seasons" in item`).
bool isTvShowDetail(MediaItem item) =>
    item.type == MediaType.tvshow && item is MediaDetail && item.seasons != null;

/// `isMangaDetail(item)`: 1-в-1 с TS (`type === "manga"`).
bool isMangaDetail(MediaItem item) => item.type == MediaType.manga;

// ---------------------------------------------------------------------------
// Volume / Season.
// ---------------------------------------------------------------------------

class MangaVolume {
  final String id;
  final int volumeNumber;
  final String title;
  final String? coverUrl;
  final int currentPage;
  final int totalPages;
  final int currentChapter;
  final int totalChapters;
  final MediaStatus status;
  final int? score;
  final String? notes;
  final String? releaseDate;
  final String mangaId;

  const MangaVolume({
    required this.id,
    required this.volumeNumber,
    required this.title,
    required this.coverUrl,
    required this.currentPage,
    required this.totalPages,
    required this.currentChapter,
    required this.totalChapters,
    required this.status,
    required this.score,
    required this.notes,
    required this.releaseDate,
    required this.mangaId,
  });

  factory MangaVolume.fromJson(Map<String, dynamic> json) => MangaVolume(
        id: json['id'] as String,
        volumeNumber: (json['volumeNumber'] as num).toInt(),
        title: json['title'] as String,
        coverUrl: _str(json['coverUrl']),
        currentPage: (json['currentPage'] as num).toInt(),
        totalPages: (json['totalPages'] as num).toInt(),
        currentChapter: (json['currentChapter'] as num).toInt(),
        totalChapters: (json['totalChapters'] as num).toInt(),
        status: MediaStatus.fromValue((json['status'] as num).toInt()),
        score: _int(json['score']),
        notes: _str(json['notes']),
        releaseDate: _str(json['releaseDate']),
        mangaId: json['mangaId'] as String,
      );

  Map<String, dynamic> toJson() => <String, dynamic>{
        'id': id,
        'volumeNumber': volumeNumber,
        'title': title,
        'coverUrl': coverUrl,
        'currentPage': currentPage,
        'totalPages': totalPages,
        'currentChapter': currentChapter,
        'totalChapters': totalChapters,
        'status': status.value,
        'score': score,
        'notes': notes,
        'releaseDate': releaseDate,
        'mangaId': mangaId,
      };

  @override
  bool operator ==(Object other) =>
      other is MangaVolume && other.toJson() == toJson();

  @override
  int get hashCode => toJson().hashCode;
}

class TvSeason {
  final String id;
  final int seasonNumber;
  final String title;
  final String? coverUrl;
  final int currentEpisode;
  final int totalEpisodes;
  final MediaStatus status;
  final int? score;
  final String? notes;
  final String? airDate;
  final String? episodesData;
  final String tvShowId;

  const TvSeason({
    required this.id,
    required this.seasonNumber,
    required this.title,
    required this.coverUrl,
    required this.currentEpisode,
    required this.totalEpisodes,
    required this.status,
    required this.score,
    required this.notes,
    required this.airDate,
    required this.episodesData,
    required this.tvShowId,
  });

  factory TvSeason.fromJson(Map<String, dynamic> json) => TvSeason(
        id: json['id'] as String,
        seasonNumber: (json['seasonNumber'] as num).toInt(),
        title: json['title'] as String,
        coverUrl: _str(json['coverUrl']),
        currentEpisode: (json['currentEpisode'] as num).toInt(),
        totalEpisodes: (json['totalEpisodes'] as num).toInt(),
        status: MediaStatus.fromValue((json['status'] as num).toInt()),
        score: _int(json['score']),
        notes: _str(json['notes']),
        airDate: _str(json['airDate']),
        episodesData: _str(json['episodesData']),
        tvShowId: json['tvShowId'] as String,
      );

  Map<String, dynamic> toJson() => <String, dynamic>{
        'id': id,
        'seasonNumber': seasonNumber,
        'title': title,
        'coverUrl': coverUrl,
        'currentEpisode': currentEpisode,
        'totalEpisodes': totalEpisodes,
        'status': status.value,
        'score': score,
        'notes': notes,
        'airDate': airDate,
        'episodesData': episodesData,
        'tvShowId': tvShowId,
      };

  @override
  bool operator ==(Object other) =>
      other is TvSeason && other.toJson() == toJson();

  @override
  int get hashCode => toJson().hashCode;
}

// ---------------------------------------------------------------------------
// Creator / Cast / Staff.
// ---------------------------------------------------------------------------

/// `type CreatorRole = "director" | "author" | "studio"`.
enum CreatorRole {
  director('director'),
  author('author'),
  studio('studio');

  final String wire;
  const CreatorRole(this.wire);

  static CreatorRole? tryFromWire(String wire) {
    for (final s in values) {
      if (s.wire == wire) return s;
    }
    return null;
  }

  static CreatorRole fromWire(String wire) =>
      tryFromWire(wire) ??
      (throw ArgumentError.value(wire, 'CreatorRole', 'unknown wire value'));
}

class CreatorSummaryDto {
  final String name;
  final CreatorRole role;
  final int totalCount;
  final int completedCount;
  final double? averageScore;
  final List<MediaItem> otherItems;

  const CreatorSummaryDto({
    required this.name,
    required this.role,
    required this.totalCount,
    required this.completedCount,
    required this.averageScore,
    required this.otherItems,
  });

  factory CreatorSummaryDto.fromJson(Map<String, dynamic> json) =>
      CreatorSummaryDto(
        name: json['name'] as String,
        role: CreatorRole.fromWire(json['role'] as String),
        totalCount: (json['totalCount'] as num).toInt(),
        completedCount: (json['completedCount'] as num).toInt(),
        averageScore: _double(json['averageScore']),
        otherItems: (json['otherItems'] as List<Object?>? ?? const [])
            .map((e) => MediaItem.fromJson(e as Map<String, dynamic>))
            .toList(),
      );

  @override
  bool operator ==(Object other) =>
      other is CreatorSummaryDto &&
      other.name == name &&
      other.role == role &&
      other.totalCount == totalCount &&
      other.completedCount == completedCount &&
      other.averageScore == averageScore &&
      other.otherItems == otherItems;

  @override
  int get hashCode =>
      Object.hash(name, role, totalCount, completedCount, averageScore, otherItems);
}

class CastMember {
  final String name;
  final String? character;
  final String? photoUrl;
  /// MAIN / SUPPORTING, as the source spelled it.
  final String? characterRole;
  final String? characterImageUrl;
  /// Japanese voice actor; absent for manga entries and legacy flat cast.
  final String? voiceActorName;
  final String? voiceActorImageUrl;

  const CastMember({
    required this.name,
    required this.character,
    required this.photoUrl,
    required this.characterRole,
    required this.characterImageUrl,
    required this.voiceActorName,
    required this.voiceActorImageUrl,
  });

  factory CastMember.fromJson(Map<String, dynamic> json) => CastMember(
        name: json['name'] as String,
        character: _str(json['character']),
        photoUrl: _str(json['photoUrl']),
        characterRole: _str(json['characterRole']),
        characterImageUrl: _str(json['characterImageUrl']),
        voiceActorName: _str(json['voiceActorName']),
        voiceActorImageUrl: _str(json['voiceActorImageUrl']),
      );

  @override
  bool operator ==(Object other) =>
      other is CastMember &&
      other.name == name &&
      other.character == character &&
      other.photoUrl == photoUrl &&
      other.characterRole == characterRole &&
      other.characterImageUrl == characterImageUrl &&
      other.voiceActorName == voiceActorName &&
      other.voiceActorImageUrl == voiceActorImageUrl;

  @override
  int get hashCode => Object.hash(name, character, photoUrl, characterRole,
      characterImageUrl, voiceActorName, voiceActorImageUrl);
}

class StaffMember {
  final String name;
  final String? role;
  final String? imageUrl;

  const StaffMember({
    required this.name,
    required this.role,
    required this.imageUrl,
  });

  factory StaffMember.fromJson(Map<String, dynamic> json) => StaffMember(
        name: json['name'] as String,
        role: _str(json['role']),
        imageUrl: _str(json['imageUrl']),
      );

  @override
  bool operator ==(Object other) =>
      other is StaffMember &&
      other.name == name &&
      other.role == role &&
      other.imageUrl == imageUrl;

  @override
  int get hashCode => Object.hash(name, role, imageUrl);
}

// ---------------------------------------------------------------------------
// Статистика.
// ---------------------------------------------------------------------------

class MediaStats {
  final int totalItems;
  final int completedItems;
  final int inProgressItems;
  final int plannedItems;
  final double totalHoursPlayed;
  final int totalPagesRead;
  final int totalChaptersRead;
  final int totalEpisodesWatched;
  final int completedGamesCount;
  final int completedBooksCount;
  final int completedMoviesCount;

  const MediaStats({
    required this.totalItems,
    required this.completedItems,
    required this.inProgressItems,
    required this.plannedItems,
    required this.totalHoursPlayed,
    required this.totalPagesRead,
    required this.totalChaptersRead,
    required this.totalEpisodesWatched,
    required this.completedGamesCount,
    required this.completedBooksCount,
    required this.completedMoviesCount,
  });

  factory MediaStats.fromJson(Map<String, dynamic> json) => MediaStats(
        totalItems: (json['totalItems'] as num).toInt(),
        completedItems: (json['completedItems'] as num).toInt(),
        inProgressItems: (json['inProgressItems'] as num).toInt(),
        plannedItems: (json['plannedItems'] as num).toInt(),
        totalHoursPlayed: (json['totalHoursPlayed'] as num).toDouble(),
        totalPagesRead: (json['totalPagesRead'] as num).toInt(),
        totalChaptersRead: (json['totalChaptersRead'] as num).toInt(),
        totalEpisodesWatched: (json['totalEpisodesWatched'] as num).toInt(),
        completedGamesCount: (json['completedGamesCount'] as num).toInt(),
        completedBooksCount: (json['completedBooksCount'] as num).toInt(),
        completedMoviesCount: (json['completedMoviesCount'] as num).toInt(),
      );

  @override
  bool operator ==(Object other) =>
      other is MediaStats &&
      other.totalItems == totalItems &&
      other.completedItems == completedItems &&
      other.inProgressItems == inProgressItems &&
      other.plannedItems == plannedItems &&
      other.totalHoursPlayed == totalHoursPlayed &&
      other.totalPagesRead == totalPagesRead &&
      other.totalChaptersRead == totalChaptersRead &&
      other.totalEpisodesWatched == totalEpisodesWatched &&
      other.completedGamesCount == completedGamesCount &&
      other.completedBooksCount == completedBooksCount &&
      other.completedMoviesCount == completedMoviesCount;

  @override
  int get hashCode => Object.hash(totalItems, completedItems, inProgressItems,
      plannedItems, totalHoursPlayed, totalPagesRead, totalChaptersRead,
      totalEpisodesWatched, completedGamesCount, completedBooksCount,
      completedMoviesCount);
}

/// `{ monthYear: string; count: number }`.
class MonthCompletion {
  final String monthYear;
  final int count;

  const MonthCompletion({required this.monthYear, required this.count});

  factory MonthCompletion.fromJson(Map<String, dynamic> json) =>
      MonthCompletion(
        monthYear: json['monthYear'] as String,
        count: (json['count'] as num).toInt(),
      );

  @override
  bool operator ==(Object other) =>
      other is MonthCompletion &&
      other.monthYear == monthYear &&
      other.count == count;

  @override
  int get hashCode => Object.hash(monthYear, count);
}

/// `{ genre: string; count: number; percentage: number }`.
class GenreCount {
  final String genre;
  final int count;
  final double percentage;

  const GenreCount({
    required this.genre,
    required this.count,
    required this.percentage,
  });

  factory GenreCount.fromJson(Map<String, dynamic> json) => GenreCount(
        genre: json['genre'] as String,
        count: (json['count'] as num).toInt(),
        percentage: (json['percentage'] as num).toDouble(),
      );

  @override
  bool operator ==(Object other) =>
      other is GenreCount &&
      other.genre == genre &&
      other.count == count &&
      other.percentage == percentage;

  @override
  int get hashCode => Object.hash(genre, count, percentage);
}

class AdvancedStats {
  final int totalTitles;
  final int completedTitles;
  final double completionRatePercent;
  final double totalHours;
  final double totalDays;
  final double gameHours;
  final double movieHours;
  final double seriesHours;
  final double animeHours;
  final double bookHours;
  final double mangaHours;
  final int totalPagesRead;
  final int totalChaptersRead;
  final int totalEpisodesWatched;
  final int? seriesEpisodesWatched;
  final int? animeEpisodesWatched;
  final double averageScore;
  /// `Record<number, number>` — JSON-ключи приводятся к int (решение #3).
  final Map<int, double> scoreDistribution;
  final Map<String, double> averageScoreByType;
  final int currentStreakDays;
  final List<MonthCompletion> monthlyCompletions;
  final List<GenreCount> topGenres;
  final Map<String, List<GenreCount>> topGenresByType;
  final Map<String, double> dailyActivity;

  const AdvancedStats({
    required this.totalTitles,
    required this.completedTitles,
    required this.completionRatePercent,
    required this.totalHours,
    required this.totalDays,
    required this.gameHours,
    required this.movieHours,
    required this.seriesHours,
    required this.animeHours,
    required this.bookHours,
    required this.mangaHours,
    required this.totalPagesRead,
    required this.totalChaptersRead,
    required this.totalEpisodesWatched,
    required this.seriesEpisodesWatched,
    required this.animeEpisodesWatched,
    required this.averageScore,
    required this.scoreDistribution,
    required this.averageScoreByType,
    required this.currentStreakDays,
    required this.monthlyCompletions,
    required this.topGenres,
    required this.topGenresByType,
    required this.dailyActivity,
  });

  factory AdvancedStats.fromJson(Map<String, dynamic> json) => AdvancedStats(
        totalTitles: (json['totalTitles'] as num).toInt(),
        completedTitles: (json['completedTitles'] as num).toInt(),
        completionRatePercent: (json['completionRatePercent'] as num).toDouble(),
        totalHours: (json['totalHours'] as num).toDouble(),
        totalDays: (json['totalDays'] as num).toDouble(),
        gameHours: (json['gameHours'] as num).toDouble(),
        movieHours: (json['movieHours'] as num).toDouble(),
        seriesHours: (json['seriesHours'] as num).toDouble(),
        animeHours: (json['animeHours'] as num).toDouble(),
        bookHours: (json['bookHours'] as num).toDouble(),
        mangaHours: (json['mangaHours'] as num).toDouble(),
        totalPagesRead: (json['totalPagesRead'] as num).toInt(),
        totalChaptersRead: (json['totalChaptersRead'] as num).toInt(),
        totalEpisodesWatched: (json['totalEpisodesWatched'] as num).toInt(),
        seriesEpisodesWatched: _int(json['seriesEpisodesWatched']),
        animeEpisodesWatched: _int(json['animeEpisodesWatched']),
        averageScore: (json['averageScore'] as num).toDouble(),
        scoreDistribution: (json['scoreDistribution'] as Map<String, dynamic>? ?? {})
            .map((k, v) => MapEntry(int.parse(k), (v as num).toDouble())),
        averageScoreByType: (json['averageScoreByType'] as Map<String, dynamic>? ?? {})
            .map((k, v) => MapEntry(k, (v as num).toDouble())),
        currentStreakDays: (json['currentStreakDays'] as num).toInt(),
        monthlyCompletions: (json['monthlyCompletions'] as List<Object?>? ?? const [])
            .map((e) => MonthCompletion.fromJson(e as Map<String, dynamic>))
            .toList(),
        topGenres: (json['topGenres'] as List<Object?>? ?? const [])
            .map((e) => GenreCount.fromJson(e as Map<String, dynamic>))
            .toList(),
        topGenresByType: (json['topGenresByType'] as Map<String, dynamic>? ?? {})
            .map((k, v) => MapEntry(
                k,
                (v as List<Object?>)
                    .map((e) => GenreCount.fromJson(e as Map<String, dynamic>))
                    .toList())),
        dailyActivity: (json['dailyActivity'] as Map<String, dynamic>? ?? {})
            .map((k, v) => MapEntry(k, (v as num).toDouble())),
      );

  @override
  bool operator ==(Object other) =>
      other is AdvancedStats &&
      other.totalTitles == totalTitles &&
      other.completedTitles == completedTitles &&
      other.completionRatePercent == completionRatePercent &&
      other.totalHours == totalHours &&
      other.totalDays == totalDays &&
      other.gameHours == gameHours &&
      other.movieHours == movieHours &&
      other.seriesHours == seriesHours &&
      other.animeHours == animeHours &&
      other.bookHours == bookHours &&
      other.mangaHours == mangaHours &&
      other.totalPagesRead == totalPagesRead &&
      other.totalChaptersRead == totalChaptersRead &&
      other.totalEpisodesWatched == totalEpisodesWatched &&
      other.seriesEpisodesWatched == seriesEpisodesWatched &&
      other.animeEpisodesWatched == animeEpisodesWatched &&
      other.averageScore == averageScore &&
      other.scoreDistribution == scoreDistribution &&
      other.averageScoreByType == averageScoreByType &&
      other.currentStreakDays == currentStreakDays &&
      other.monthlyCompletions == monthlyCompletions &&
      other.topGenres == topGenres &&
      other.topGenresByType == topGenresByType &&
      other.dailyActivity == dailyActivity;

  @override
  int get hashCode => Object.hash(totalTitles, completedTitles, totalHours,
      averageScore, currentStreakDays);
}

// ---------------------------------------------------------------------------
// Taste profile (Stats).
// ---------------------------------------------------------------------------

class TastePersona {
  final String title;
  final String description;
  final String icon;
  final List<String> traits;

  const TastePersona({
    required this.title,
    required this.description,
    required this.icon,
    required this.traits,
  });

  factory TastePersona.fromJson(Map<String, dynamic> json) => TastePersona(
        title: json['title'] as String,
        description: json['description'] as String,
        icon: json['icon'] as String,
        traits: (json['traits'] as List<Object?>? ?? const []).cast<String>().toList(),
      );

  @override
  bool operator ==(Object other) =>
      other is TastePersona &&
      other.title == title &&
      other.description == description &&
      other.icon == icon &&
      other.traits == traits;

  @override
  int get hashCode => Object.hash(title, description, icon, traits);
}

class SunkCost {
  final double lowScoreHours;
  final double percentageOfTotal;
  final int titlesCount;
  final Map<String, double> categoryBreakdown;

  const SunkCost({
    required this.lowScoreHours,
    required this.percentageOfTotal,
    required this.titlesCount,
    required this.categoryBreakdown,
  });

  factory SunkCost.fromJson(Map<String, dynamic> json) => SunkCost(
        lowScoreHours: (json['lowScoreHours'] as num).toDouble(),
        percentageOfTotal: (json['percentageOfTotal'] as num).toDouble(),
        titlesCount: (json['titlesCount'] as num).toInt(),
        categoryBreakdown: (json['categoryBreakdown'] as Map<String, dynamic>? ?? {})
            .map((k, v) => MapEntry(k, (v as num).toDouble())),
      );

  @override
  bool operator ==(Object other) =>
      other is SunkCost &&
      other.lowScoreHours == lowScoreHours &&
      other.percentageOfTotal == percentageOfTotal &&
      other.titlesCount == titlesCount &&
      other.categoryBreakdown == categoryBreakdown;

  @override
  int get hashCode => Object.hash(lowScoreHours, percentageOfTotal, titlesCount,
      categoryBreakdown);
}

class DivergenceItem {
  final String id;
  final String title;
  final String type;
  final String? coverUrl;
  final double userScore;
  final double worldRating;
  final double delta;

  const DivergenceItem({
    required this.id,
    required this.title,
    required this.type,
    required this.coverUrl,
    required this.userScore,
    required this.worldRating,
    required this.delta,
  });

  factory DivergenceItem.fromJson(Map<String, dynamic> json) => DivergenceItem(
        id: json['id'] as String,
        title: json['title'] as String,
        type: json['type'] as String,
        coverUrl: _str(json['coverUrl']),
        userScore: (json['userScore'] as num).toDouble(),
        worldRating: (json['worldRating'] as num).toDouble(),
        delta: (json['delta'] as num).toDouble(),
      );

  @override
  bool operator ==(Object other) =>
      other is DivergenceItem &&
      other.id == id &&
      other.title == title &&
      other.type == type &&
      other.coverUrl == coverUrl &&
      other.userScore == userScore &&
      other.worldRating == worldRating &&
      other.delta == delta;

  @override
  int get hashCode =>
      Object.hash(id, title, type, coverUrl, userScore, worldRating, delta);
}

class CriticalDivergence {
  final DivergenceItem? hiddenGem;
  final DivergenceItem? disappointment;

  const CriticalDivergence({
    required this.hiddenGem,
    required this.disappointment,
  });

  factory CriticalDivergence.fromJson(Map<String, dynamic> json) =>
      CriticalDivergence(
        hiddenGem: json['hiddenGem'] == null
            ? null
            : DivergenceItem.fromJson(json['hiddenGem'] as Map<String, dynamic>),
        disappointment: json['disappointment'] == null
            ? null
            : DivergenceItem.fromJson(
                json['disappointment'] as Map<String, dynamic>),
      );

  @override
  bool operator ==(Object other) =>
      other is CriticalDivergence &&
      other.hiddenGem == hiddenGem &&
      other.disappointment == disappointment;

  @override
  int get hashCode => Object.hash(hiddenGem, disappointment);
}

class GenreCompletionStat {
  final String genre;
  final int total;
  final int completed;
  final int dropped;
  final double completionRate;
  final double dropRate;

  const GenreCompletionStat({
    required this.genre,
    required this.total,
    required this.completed,
    required this.dropped,
    required this.completionRate,
    required this.dropRate,
  });

  factory GenreCompletionStat.fromJson(Map<String, dynamic> json) =>
      GenreCompletionStat(
        genre: json['genre'] as String,
        total: (json['total'] as num).toInt(),
        completed: (json['completed'] as num).toInt(),
        dropped: (json['dropped'] as num).toInt(),
        completionRate: (json['completionRate'] as num).toDouble(),
        dropRate: (json['dropRate'] as num).toDouble(),
      );

  @override
  bool operator ==(Object other) =>
      other is GenreCompletionStat &&
      other.genre == genre &&
      other.total == total &&
      other.completed == completed &&
      other.dropped == dropped &&
      other.completionRate == completionRate &&
      other.dropRate == dropRate;

  @override
  int get hashCode =>
      Object.hash(genre, total, completed, dropped, completionRate, dropRate);
}

class EraAffinityStat {
  final String era;
  final int count;
  final double percentage;

  const EraAffinityStat({
    required this.era,
    required this.count,
    required this.percentage,
  });

  factory EraAffinityStat.fromJson(Map<String, dynamic> json) =>
      EraAffinityStat(
        era: json['era'] as String,
        count: (json['count'] as num).toInt(),
        percentage: (json['percentage'] as num).toDouble(),
      );

  @override
  bool operator ==(Object other) =>
      other is EraAffinityStat &&
      other.era == era &&
      other.count == count &&
      other.percentage == percentage;

  @override
  int get hashCode => Object.hash(era, count, percentage);
}

class RadarAxis {
  final String genre;
  final double volumeScore;
  final double averageScore;

  const RadarAxis({
    required this.genre,
    required this.volumeScore,
    required this.averageScore,
  });

  factory RadarAxis.fromJson(Map<String, dynamic> json) => RadarAxis(
        genre: json['genre'] as String,
        volumeScore: (json['volumeScore'] as num).toDouble(),
        averageScore: (json['averageScore'] as num).toDouble(),
      );

  @override
  bool operator ==(Object other) =>
      other is RadarAxis &&
      other.genre == genre &&
      other.volumeScore == volumeScore &&
      other.averageScore == averageScore;

  @override
  int get hashCode => Object.hash(genre, volumeScore, averageScore);
}

class DropReasonStat {
  final String reason;
  final int count;
  final double percentage;

  const DropReasonStat({
    required this.reason,
    required this.count,
    required this.percentage,
  });

  factory DropReasonStat.fromJson(Map<String, dynamic> json) => DropReasonStat(
        reason: json['reason'] as String,
        count: (json['count'] as num).toInt(),
        percentage: (json['percentage'] as num).toDouble(),
      );

  @override
  bool operator ==(Object other) =>
      other is DropReasonStat &&
      other.reason == reason &&
      other.count == count &&
      other.percentage == percentage;

  @override
  int get hashCode => Object.hash(reason, count, percentage);
}

class DropAnalytics {
  final int totalDropped;
  final double averageDropProgressPercent;
  final int earlyDropCount;
  final int midDropCount;
  final int lateDropCount;
  final List<DropReasonStat> topReasons;

  const DropAnalytics({
    required this.totalDropped,
    required this.averageDropProgressPercent,
    required this.earlyDropCount,
    required this.midDropCount,
    required this.lateDropCount,
    required this.topReasons,
  });

  factory DropAnalytics.fromJson(Map<String, dynamic> json) => DropAnalytics(
        totalDropped: (json['totalDropped'] as num).toInt(),
        averageDropProgressPercent:
            (json['averageDropProgressPercent'] as num).toDouble(),
        earlyDropCount: (json['earlyDropCount'] as num).toInt(),
        midDropCount: (json['midDropCount'] as num).toInt(),
        lateDropCount: (json['lateDropCount'] as num).toInt(),
        topReasons: (json['topReasons'] as List<Object?>? ?? const [])
            .map((e) => DropReasonStat.fromJson(e as Map<String, dynamic>))
            .toList(),
      );

  @override
  bool operator ==(Object other) =>
      other is DropAnalytics &&
      other.totalDropped == totalDropped &&
      other.averageDropProgressPercent == averageDropProgressPercent &&
      other.earlyDropCount == earlyDropCount &&
      other.midDropCount == midDropCount &&
      other.lateDropCount == lateDropCount &&
      other.topReasons == topReasons;

  @override
  int get hashCode => Object.hash(totalDropped, averageDropProgressPercent,
      earlyDropCount, midDropCount, lateDropCount, topReasons);
}

class TasteProfile {
  final TastePersona persona;
  final SunkCost sunkCost;
  final CriticalDivergence divergence;
  final List<GenreCompletionStat> genreParadox;
  final List<EraAffinityStat> eraAffinity;
  final List<RadarAxis> genreRadar;
  final DropAnalytics? dropAnalytics;

  const TasteProfile({
    required this.persona,
    required this.sunkCost,
    required this.divergence,
    required this.genreParadox,
    required this.eraAffinity,
    required this.genreRadar,
    required this.dropAnalytics,
  });

  factory TasteProfile.fromJson(Map<String, dynamic> json) => TasteProfile(
        persona: TastePersona.fromJson(json['persona'] as Map<String, dynamic>),
        sunkCost: SunkCost.fromJson(json['sunkCost'] as Map<String, dynamic>),
        divergence:
            CriticalDivergence.fromJson(json['divergence'] as Map<String, dynamic>),
        genreParadox: (json['genreParadox'] as List<Object?>? ?? const [])
            .map((e) => GenreCompletionStat.fromJson(e as Map<String, dynamic>))
            .toList(),
        eraAffinity: (json['eraAffinity'] as List<Object?>? ?? const [])
            .map((e) => EraAffinityStat.fromJson(e as Map<String, dynamic>))
            .toList(),
        genreRadar: (json['genreRadar'] as List<Object?>? ?? const [])
            .map((e) => RadarAxis.fromJson(e as Map<String, dynamic>))
            .toList(),
        dropAnalytics: json['dropAnalytics'] == null
            ? null
            : DropAnalytics.fromJson(json['dropAnalytics'] as Map<String, dynamic>),
      );

  @override
  bool operator ==(Object other) =>
      other is TasteProfile &&
      other.persona == persona &&
      other.sunkCost == sunkCost &&
      other.divergence == divergence &&
      other.genreParadox == genreParadox &&
      other.eraAffinity == eraAffinity &&
      other.genreRadar == genreRadar &&
      other.dropAnalytics == dropAnalytics;

  @override
  int get hashCode =>
      Object.hash(persona, sunkCost, divergence, genreParadox, eraAffinity,
          genreRadar, dropAnalytics);
}

// ---------------------------------------------------------------------------
// External search.
// ---------------------------------------------------------------------------

class ExternalMedia {
  final String externalId;
  final String? externalSource;
  final String title;
  final String? originalTitle;
  final String? romajiTitle;
  final String? coverUrl;
  final String? description;
  final String? trailerVideoId;
  final int? releaseYear;
  final String? releaseDate;
  final String? endDate;
  final String? releaseStatus;
  /// Provider's own format label (MANGA, NOVEL, TV, MOVIE...).
  final String? format;
  final int? runtimeMinutes;
  /// `SearchMediaType` — открытый строковый union (может быть "anime").
  final String type;
  final String? author;
  final String? studio;
  final String? isbn;
  final List<String>? covers;
  final int? totalCount;
  final int? chapters;
  final int? volumes;
  /// One of manga/manhwa/manhua/oel; null when no source could tell.
  final String? mangaFormat;
  final String? countryOfOrigin;
  final String? platform;
  final double? rating;
  final int? ratingVotes;
  final List<ExternalRating>? ratings;
  final List<ExternalEpisode>? episodes;
  final List<String>? genres;
  final List<String>? tags;
  final List<String>? synonyms;
  /// Set client-side when the entry was resolved from a pasted direct link.
  final bool? isDirectUrl;

  const ExternalMedia({
    required this.externalId,
    required this.externalSource,
    required this.title,
    required this.originalTitle,
    required this.romajiTitle,
    required this.coverUrl,
    required this.description,
    required this.trailerVideoId,
    required this.releaseYear,
    required this.releaseDate,
    required this.endDate,
    required this.releaseStatus,
    required this.format,
    required this.runtimeMinutes,
    required this.type,
    required this.author,
    required this.studio,
    required this.isbn,
    required this.covers,
    required this.totalCount,
    required this.chapters,
    required this.volumes,
    required this.mangaFormat,
    required this.countryOfOrigin,
    required this.platform,
    required this.rating,
    required this.ratingVotes,
    required this.ratings,
    required this.episodes,
    required this.genres,
    required this.tags,
    required this.synonyms,
    required this.isDirectUrl,
  });

  factory ExternalMedia.fromJson(Map<String, dynamic> json) => ExternalMedia(
        externalId: json['externalId'] as String,
        externalSource: _str(json['externalSource']),
        title: json['title'] as String,
        originalTitle: _str(json['originalTitle']),
        romajiTitle: _str(json['romajiTitle']),
        coverUrl: _str(json['coverUrl']),
        description: _str(json['description']),
        trailerVideoId: _str(json['trailerVideoId']),
        releaseYear: _int(json['releaseYear']),
        releaseDate: _str(json['releaseDate']),
        endDate: _str(json['endDate']),
        releaseStatus: _str(json['releaseStatus']),
        format: _str(json['format']),
        runtimeMinutes: _int(json['runtimeMinutes']),
        type: json['type'] as String,
        author: _str(json['author']),
        studio: _str(json['studio']),
        isbn: _str(json['isbn']),
        covers: (json['covers'] as List<Object?>?)?.cast<String>().toList(),
        totalCount: _int(json['totalCount']),
        chapters: _int(json['chapters']),
        volumes: _int(json['volumes']),
        mangaFormat: _str(json['mangaFormat']),
        countryOfOrigin: _str(json['countryOfOrigin']),
        platform: _str(json['platform']),
        rating: _double(json['rating']),
        ratingVotes: _int(json['ratingVotes']),
        ratings: (json['ratings'] as List<Object?>?)
            ?.map((e) => ExternalRating.fromJson(e as Map<String, dynamic>))
            .toList(),
        episodes: (json['episodes'] as List<Object?>?)
            ?.map((e) => ExternalEpisode.fromJson(e as Map<String, dynamic>))
            .toList(),
        genres: _strOrList(json['genres']),
        tags: _strOrList(json['tags']),
        synonyms: (json['synonyms'] as List<Object?>?)?.cast<String>().toList(),
        isDirectUrl: _bool(json['isDirectUrl']),
      );

  @override
  bool operator ==(Object other) =>
      other is ExternalMedia &&
      other.externalId == externalId &&
      other.externalSource == externalSource &&
      other.title == title &&
      other.type == type &&
      other.rating == rating &&
      other.coverUrl == coverUrl;

  @override
  int get hashCode => Object.hash(externalId, externalSource, title, type);
}

// ---------------------------------------------------------------------------
// Фильтры списка.
// ---------------------------------------------------------------------------

/// Query-фильтры `GET /api/media`. 1-в-1 `MediaFilters`; `toQueryParameters`
/// строит dio-совместимые query-параметры.
class MediaFilters {
  final MediaType? type;
  final MediaStatus? status;
  final bool? isAnime;
  /// Вынесенная категория навигации: сервер применяет её match-условие и исключает из родителя.
  final String? subId;
  final String? search;
  final SortBy? sortBy;
  final SortOrder? sortOrder;
  final int? limit;
  final int? offset;

  const MediaFilters({
    this.type,
    this.status,
    this.isAnime,
    this.subId,
    this.search,
    this.sortBy,
    this.sortOrder,
    this.limit,
    this.offset,
  });

  Map<String, dynamic> toQueryParameters() => <String, dynamic>{
        if (type != null) 'type': type!.wire,
        if (status != null) 'status': status!.value,
        if (isAnime != null) 'isAnime': isAnime,
        if (subId != null) 'subId': subId,
        if (search != null && search!.isNotEmpty) 'search': search,
        if (sortBy != null) 'sortBy': sortBy!.wire,
        if (sortOrder != null) 'sortOrder': sortOrder!.wire,
        if (limit != null) 'limit': limit,
        if (offset != null) 'offset': offset,
      };

  @override
  bool operator ==(Object other) =>
      other is MediaFilters &&
      other.type == type &&
      other.status == status &&
      other.isAnime == isAnime &&
      other.subId == subId &&
      other.search == search &&
      other.sortBy == sortBy &&
      other.sortOrder == sortOrder &&
      other.limit == limit &&
      other.offset == offset;

  @override
  int get hashCode => Object.hash(type, status, isAnime, subId, search, sortBy,
      sortOrder, limit, offset);
}

// ---------------------------------------------------------------------------
// Achievements / related / recommendations.
// ---------------------------------------------------------------------------

class GameAchievementItem {
  final String name;
  final String? description;
  final String? iconUrl;

  const GameAchievementItem({
    required this.name,
    required this.description,
    required this.iconUrl,
  });

  factory GameAchievementItem.fromJson(Map<String, dynamic> json) =>
      GameAchievementItem(
        name: json['name'] as String,
        description: _str(json['description']),
        iconUrl: _str(json['iconUrl']),
      );

  @override
  bool operator ==(Object other) =>
      other is GameAchievementItem &&
      other.name == name &&
      other.description == description &&
      other.iconUrl == iconUrl;

  @override
  int get hashCode => Object.hash(name, description, iconUrl);
}

class GameAchievementsResponse {
  final int totalCount;
  final List<GameAchievementItem> achievements;

  const GameAchievementsResponse({
    required this.totalCount,
    required this.achievements,
  });

  factory GameAchievementsResponse.fromJson(Map<String, dynamic> json) =>
      GameAchievementsResponse(
        totalCount: (json['totalCount'] as num).toInt(),
        achievements: (json['achievements'] as List<Object?>? ?? const [])
            .map((e) => GameAchievementItem.fromJson(e as Map<String, dynamic>))
            .toList(),
      );

  @override
  bool operator ==(Object other) =>
      other is GameAchievementsResponse &&
      other.totalCount == totalCount &&
      other.achievements == achievements;

  @override
  int get hashCode => Object.hash(totalCount, achievements);
}

class GameRelatedItem {
  final String id;
  final String title;
  final String? coverUrl;
  final String? releaseDate;
  final int? score;

  const GameRelatedItem({
    required this.id,
    required this.title,
    required this.coverUrl,
    required this.releaseDate,
    required this.score,
  });

  factory GameRelatedItem.fromJson(Map<String, dynamic> json) =>
      GameRelatedItem(
        id: json['id'] as String,
        title: json['title'] as String,
        coverUrl: _str(json['coverUrl']),
        releaseDate: _str(json['releaseDate']),
        score: _int(json['score']),
      );

  @override
  bool operator ==(Object other) =>
      other is GameRelatedItem &&
      other.id == id &&
      other.title == title &&
      other.coverUrl == coverUrl &&
      other.releaseDate == releaseDate &&
      other.score == score;

  @override
  int get hashCode => Object.hash(id, title, coverUrl, releaseDate, score);
}

/// One recommended title, normalised server-side across AniList and TMDb.
class ExternalRecommendation {
  final String id;
  final String title;
  final String? coverUrl;
  final double? rating;
  final String source;

  const ExternalRecommendation({
    required this.id,
    required this.title,
    required this.coverUrl,
    required this.rating,
    required this.source,
  });

  factory ExternalRecommendation.fromJson(Map<String, dynamic> json) =>
      ExternalRecommendation(
        id: json['id'] as String,
        title: json['title'] as String,
        coverUrl: _str(json['coverUrl']),
        rating: _double(json['rating']),
        source: json['source'] as String,
      );

  @override
  bool operator ==(Object other) =>
      other is ExternalRecommendation &&
      other.id == id &&
      other.title == title &&
      other.coverUrl == coverUrl &&
      other.rating == rating &&
      other.source == source;

  @override
  int get hashCode => Object.hash(id, title, coverUrl, rating, source);
}

/// A related title plus the relationship that produced it.
class ExternalRelation {
  final String relationType;
  final ExternalMedia media;

  const ExternalRelation({required this.relationType, required this.media});

  factory ExternalRelation.fromJson(Map<String, dynamic> json) =>
      ExternalRelation(
        relationType: json['relationType'] as String,
        media: ExternalMedia.fromJson(json['media'] as Map<String, dynamic>),
      );

  @override
  bool operator ==(Object other) =>
      other is ExternalRelation &&
      other.relationType == relationType &&
      other.media == media;

  @override
  int get hashCode => Object.hash(relationType, media);
}

// ---------------------------------------------------------------------------
// History.
// ---------------------------------------------------------------------------

/// Mirrors MediaEventType on the server.
class HistoryEvent {
  final String id;
  final String mediaId;
  /// Serialised by name ("StatusChanged"), matching the HistoryEventType union.
  final HistoryEventType type;
  final String? oldValue;
  final String? newValue;
  final String createdAt;
  /// Null once the media is deleted.
  final String? title;

  const HistoryEvent({
    required this.id,
    required this.mediaId,
    required this.type,
    required this.oldValue,
    required this.newValue,
    required this.createdAt,
    required this.title,
  });

  factory HistoryEvent.fromJson(Map<String, dynamic> json) => HistoryEvent(
        id: json['id'] as String,
        mediaId: json['mediaId'] as String,
        type: HistoryEventType.fromWire(json['type'] as String),
        oldValue: _str(json['oldValue']),
        newValue: _str(json['newValue']),
        createdAt: json['createdAt'] as String,
        title: _str(json['title']),
      );

  Map<String, dynamic> toJson() => <String, dynamic>{
        'id': id,
        'mediaId': mediaId,
        'type': type.wire,
        'oldValue': oldValue,
        'newValue': newValue,
        'createdAt': createdAt,
        'title': title,
      };

  @override
  bool operator ==(Object other) =>
      other is HistoryEvent && other.toJson() == toJson();

  @override
  int get hashCode => toJson().hashCode;
}

// ---------------------------------------------------------------------------
// Storage / Offline / Search cache.
// ---------------------------------------------------------------------------

/// `mode: "default" | "portable" | "custom"`; "default" — зарезервированное
/// слово Dart, вариант назван [StorageMode.defaultMode].
enum StorageMode {
  defaultMode('default'),
  portable('portable'),
  custom('custom');

  final String wire;
  const StorageMode(this.wire);

  static StorageMode? tryFromWire(String wire) {
    for (final s in values) {
      if (s.wire == wire) return s;
    }
    return null;
  }

  static StorageMode fromWire(String wire) =>
      tryFromWire(wire) ??
      (throw ArgumentError.value(wire, 'StorageMode', 'unknown wire value'));
}

class StorageSettings {
  final StorageMode mode;
  final String defaultDirectory;
  final String portableDirectory;
  final String? customPath;
  final bool isFirstRunSetupRequired;

  const StorageSettings({
    required this.mode,
    required this.defaultDirectory,
    required this.portableDirectory,
    required this.customPath,
    required this.isFirstRunSetupRequired,
  });

  factory StorageSettings.fromJson(Map<String, dynamic> json) =>
      StorageSettings(
        mode: StorageMode.fromWire(json['mode'] as String),
        defaultDirectory: json['defaultDirectory'] as String,
        portableDirectory: json['portableDirectory'] as String,
        customPath: _str(json['customPath']),
        isFirstRunSetupRequired: json['isFirstRunSetupRequired'] as bool,
      );

  @override
  bool operator ==(Object other) =>
      other is StorageSettings &&
      other.mode == mode &&
      other.defaultDirectory == defaultDirectory &&
      other.portableDirectory == portableDirectory &&
      other.customPath == customPath &&
      other.isFirstRunSetupRequired == isFirstRunSetupRequired;

  @override
  int get hashCode => Object.hash(mode, defaultDirectory, portableDirectory,
      customPath, isFirstRunSetupRequired);
}

/// Payload выбора/смены режима хранилища (отправляется на сервер).
class StorageRequest {
  final StorageMode mode;
  final String customPath;
  final bool migrateExistingData;

  const StorageRequest({
    required this.mode,
    required this.customPath,
    required this.migrateExistingData,
  });

  Map<String, dynamic> toJson() => <String, dynamic>{
        'mode': mode.wire,
        'customPath': customPath,
        'migrateExistingData': migrateExistingData,
      };

  @override
  bool operator ==(Object other) =>
      other is StorageRequest &&
      other.mode == mode &&
      other.customPath == customPath &&
      other.migrateExistingData == migrateExistingData;

  @override
  int get hashCode => Object.hash(mode, customPath, migrateExistingData);
}

class OfflineDatabaseStatusDto {
  final String name;
  final String fileName;
  final String type;
  final int totalTitles;
  final int fileSizeBytes;
  final String lastModified;
  final bool isActive;
  /// Raw dump (".jsonl"/".json"/".tsv") that produced the database, when it still exists.
  final String? sourceDumpFileName;

  const OfflineDatabaseStatusDto({
    required this.name,
    required this.fileName,
    required this.type,
    required this.totalTitles,
    required this.fileSizeBytes,
    required this.lastModified,
    required this.isActive,
    required this.sourceDumpFileName,
  });

  factory OfflineDatabaseStatusDto.fromJson(Map<String, dynamic> json) =>
      OfflineDatabaseStatusDto(
        name: json['name'] as String,
        fileName: json['fileName'] as String,
        type: json['type'] as String,
        totalTitles: (json['totalTitles'] as num).toInt(),
        fileSizeBytes: (json['fileSizeBytes'] as num).toInt(),
        lastModified: json['lastModified'] as String,
        isActive: json['isActive'] as bool,
        sourceDumpFileName: _str(json['sourceDumpFileName']),
      );

  @override
  bool operator ==(Object other) =>
      other is OfflineDatabaseStatusDto &&
      other.name == name &&
      other.fileName == fileName &&
      other.type == type &&
      other.totalTitles == totalTitles &&
      other.fileSizeBytes == fileSizeBytes &&
      other.lastModified == lastModified &&
      other.isActive == isActive &&
      other.sourceDumpFileName == sourceDumpFileName;

  @override
  int get hashCode => Object.hash(name, fileName, type, totalTitles,
      fileSizeBytes, lastModified, isActive, sourceDumpFileName);
}

class OfflineDatabasesSummaryDto {
  final List<OfflineDatabaseStatusDto> databases;
  final int totalIndexedTitles;
  final String offlineDirectoryPath;
  final List<String> pendingDumps;

  const OfflineDatabasesSummaryDto({
    required this.databases,
    required this.totalIndexedTitles,
    required this.offlineDirectoryPath,
    required this.pendingDumps,
  });

  factory OfflineDatabasesSummaryDto.fromJson(Map<String, dynamic> json) =>
      OfflineDatabasesSummaryDto(
        databases: (json['databases'] as List<Object?>? ?? const [])
            .map((e) => OfflineDatabaseStatusDto.fromJson(e as Map<String, dynamic>))
            .toList(),
        totalIndexedTitles: (json['totalIndexedTitles'] as num).toInt(),
        offlineDirectoryPath: json['offlineDirectoryPath'] as String,
        pendingDumps:
            (json['pendingDumps'] as List<Object?>? ?? const []).cast<String>().toList(),
      );

  @override
  bool operator ==(Object other) =>
      other is OfflineDatabasesSummaryDto &&
      other.databases == databases &&
      other.totalIndexedTitles == totalIndexedTitles &&
      other.offlineDirectoryPath == offlineDirectoryPath &&
      other.pendingDumps == pendingDumps;

  @override
  int get hashCode => Object.hash(databases, totalIndexedTitles,
      offlineDirectoryPath, pendingDumps);
}

/// Stats of the persistent external-search cache: SQLite DB + cached preview images.
class SearchCacheInfoDto {
  final int entryCount;
  final int fileSizeBytes;
  final int imageFileCount;
  final int imageFileSizeBytes;
  final String databasePath;

  const SearchCacheInfoDto({
    required this.entryCount,
    required this.fileSizeBytes,
    required this.imageFileCount,
    required this.imageFileSizeBytes,
    required this.databasePath,
  });

  factory SearchCacheInfoDto.fromJson(Map<String, dynamic> json) =>
      SearchCacheInfoDto(
        entryCount: (json['entryCount'] as num).toInt(),
        fileSizeBytes: (json['fileSizeBytes'] as num).toInt(),
        imageFileCount: (json['imageFileCount'] as num).toInt(),
        imageFileSizeBytes: (json['imageFileSizeBytes'] as num).toInt(),
        databasePath: json['databasePath'] as String,
      );

  @override
  bool operator ==(Object other) =>
      other is SearchCacheInfoDto &&
      other.entryCount == entryCount &&
      other.fileSizeBytes == fileSizeBytes &&
      other.imageFileCount == imageFileCount &&
      other.imageFileSizeBytes == imageFileSizeBytes &&
      other.databasePath == databasePath;

  @override
  int get hashCode => Object.hash(entryCount, fileSizeBytes, imageFileCount,
      imageFileSizeBytes, databasePath);
}
