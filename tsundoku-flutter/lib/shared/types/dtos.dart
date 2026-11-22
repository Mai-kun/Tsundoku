/// 1:1 port of `mediatracker-ui/src/shared/types/dtos.ts`.
///
/// Payload'ы запросов (TS interface, отправляемые на сервер) получают `toJson`;
/// read-only DTO — только `fromJson` (YAGNI, решение #4 в FLUTTER_MIGRATION.md).
library;

import 'enums.dart';
import 'models.dart' show ExternalMedia, MediaItem;

// ---------------------------------------------------------------------------
// Pending matches / duplicate conflicts (read-only).
// ---------------------------------------------------------------------------

/// Marker of a duplicate conflict (`PendingMatchesJson` object shape on the
/// server): the row was parked in review because the title being added matches
/// one already in the library, and the verdict — merge the sources or keep
/// both — is the user's to make.
class DuplicateConflictDto {
  final String conflictType;
  final String existingMediaId;
  final String existingTitle;
  final String? incomingSource;
  final String? incomingExternalId;
  final String? incomingTitle;

  const DuplicateConflictDto({
    required this.conflictType,
    required this.existingMediaId,
    required this.existingTitle,
    required this.incomingSource,
    required this.incomingExternalId,
    required this.incomingTitle,
  });

  factory DuplicateConflictDto.fromJson(Map<String, dynamic> json) =>
      DuplicateConflictDto(
        conflictType: json['conflictType'] as String,
        existingMediaId: json['existingMediaId'] as String,
        existingTitle: json['existingTitle'] as String,
        incomingSource: json['incomingSource'] as String?,
        incomingExternalId: json['incomingExternalId'] as String?,
        incomingTitle: json['incomingTitle'] as String?,
      );

  @override
  bool operator ==(Object other) =>
      other is DuplicateConflictDto &&
      other.conflictType == conflictType &&
      other.existingMediaId == existingMediaId &&
      other.existingTitle == existingTitle &&
      other.incomingSource == incomingSource &&
      other.incomingExternalId == incomingExternalId &&
      other.incomingTitle == incomingTitle;

  @override
  int get hashCode => Object.hash(conflictType, existingMediaId, existingTitle,
      incomingSource, incomingExternalId, incomingTitle);
}

/// One row of the "review ambiguous matches" screen
/// (`GET /api/media/pending-matches`). Mirrors `PendingMatchReviewDto` on the
/// server.
class PendingMatchItemDto {
  final String id;
  final String title;
  final String? romajiTitle;
  final String? originalTitle;
  final List<String>? altTitles;
  final String type;
  final bool? isAnime;
  final int? releaseYear;
  final String? author;
  final int? currentProgress;
  final int? totalCount;
  final String? countryOfOrigin;
  final String? mangaFormat;
  final List<ExternalMedia> candidates;
  /// Set when the row is a duplicate-conflict verdict instead of a candidate list.
  final DuplicateConflictDto? duplicate;

  const PendingMatchItemDto({
    required this.id,
    required this.title,
    required this.romajiTitle,
    required this.originalTitle,
    required this.altTitles,
    required this.type,
    required this.isAnime,
    required this.releaseYear,
    required this.author,
    required this.currentProgress,
    required this.totalCount,
    required this.countryOfOrigin,
    required this.mangaFormat,
    required this.candidates,
    required this.duplicate,
  });

  factory PendingMatchItemDto.fromJson(Map<String, dynamic> json) =>
      PendingMatchItemDto(
        id: json['id'] as String,
        title: json['title'] as String,
        romajiTitle: json['romajiTitle'] as String?,
        originalTitle: json['originalTitle'] as String?,
        altTitles:
            (json['altTitles'] as List<Object?>?)?.cast<String>().toList(),
        type: json['type'] as String,
        isAnime: json['isAnime'] as bool?,
        releaseYear: _int(json['releaseYear']),
        author: json['author'] as String?,
        currentProgress: _int(json['currentProgress']),
        totalCount: _int(json['totalCount']),
        countryOfOrigin: json['countryOfOrigin'] as String?,
        mangaFormat: json['mangaFormat'] as String?,
        candidates: (json['candidates'] as List<Object?>? ?? const [])
            .map((e) => ExternalMedia.fromJson(e as Map<String, dynamic>))
            .toList(),
        duplicate: json['duplicate'] == null
            ? null
            : DuplicateConflictDto.fromJson(
                json['duplicate'] as Map<String, dynamic>),
      );

  @override
  bool operator ==(Object other) =>
      other is PendingMatchItemDto &&
      other.id == id &&
      other.title == title &&
      other.candidates == candidates &&
      other.duplicate == duplicate;

  @override
  int get hashCode => Object.hash(id, title, candidates, duplicate);
}

int? _int(Object? v) => v == null ? null : (v as num).toInt();

/// Normalizes dates to full ISO8601 YYYY-MM-DD for backend DateTime? deserialization.
String? normalizeIsoDate(String? raw, [int? fallbackYear]) {
  if (raw == null) {
    return (fallbackYear != null && fallbackYear > 0) ? '$fallbackYear-01-01' : null;
  }
  final s = raw.trim();
  if (s.isEmpty) {
    return (fallbackYear != null && fallbackYear > 0) ? '$fallbackYear-01-01' : null;
  }
  final fullMatch = RegExp(r'^(\d{4})-(\d{2})-(\d{2})').firstMatch(s);
  if (fullMatch != null) {
    return '${fullMatch.group(1)}-${fullMatch.group(2)}-${fullMatch.group(3)}';
  }
  final ymMatch = RegExp(r'^(\d{4})-(\d{2})$').firstMatch(s);
  if (ymMatch != null) {
    return '${ymMatch.group(1)}-${ymMatch.group(2)}-01';
  }
  final yMatch = RegExp(r'^(\d{4})$').firstMatch(s);
  if (yMatch != null) {
    return '${yMatch.group(1)}-01-01';
  }
  final slashMatch = RegExp(r'^(\d{4})/(\d{1,2})/(\d{1,2})$').firstMatch(s);
  if (slashMatch != null) {
    final y = slashMatch.group(1)!;
    final m = slashMatch.group(2)!.padLeft(2, '0');
    final d = slashMatch.group(3)!.padLeft(2, '0');
    return '$y-$m-$d';
  }
  final parsed = DateTime.tryParse(s);
  if (parsed != null) {
    final y = parsed.year.toString().padLeft(4, '0');
    final m = parsed.month.toString().padLeft(2, '0');
    final d = parsed.day.toString().padLeft(2, '0');
    return '$y-$m-$d';
  }
  final anyYear = RegExp(r'\b(18\d\d|19\d\d|20\d\d|21\d\d)\b').firstMatch(s);
  if (anyYear != null) {
    return '${anyYear.group(1)}-01-01';
  }
  if (fallbackYear != null && fallbackYear > 0) {
    return '$fallbackYear-01-01';
  }
  return null;
}

// ---------------------------------------------------------------------------
// Custom lists.
// ---------------------------------------------------------------------------

class CustomListSummary {
  final String id;
  final String name;
  final String? description;
  final String? icon;
  final String? color;
  final int itemsCount;
  final String updatedAt;
  final List<String?> previewCovers;
  final bool isSmart;
  final String? smartQueryJson;

  const CustomListSummary({
    required this.id,
    required this.name,
    required this.description,
    required this.icon,
    required this.color,
    required this.itemsCount,
    required this.updatedAt,
    required this.previewCovers,
    required this.isSmart,
    required this.smartQueryJson,
  });

  factory CustomListSummary.fromJson(Map<String, dynamic> json) =>
      CustomListSummary(
        id: json['id'] as String,
        name: json['name'] as String,
        description: json['description'] as String?,
        icon: json['icon'] as String?,
        color: json['color'] as String?,
        itemsCount: (json['itemsCount'] as num).toInt(),
        updatedAt: json['updatedAt'] as String,
        previewCovers:
            (json['previewCovers'] as List<Object?>? ?? const []).cast<String?>().toList(),
        isSmart: json['isSmart'] as bool,
        smartQueryJson: json['smartQueryJson'] as String?,
      );

  @override
  bool operator ==(Object other) =>
      other is CustomListSummary &&
      other.id == id &&
      other.name == name &&
      other.itemsCount == itemsCount &&
      other.updatedAt == updatedAt &&
      other.isSmart == isSmart;

  @override
  int get hashCode => Object.hash(id, name, itemsCount, updatedAt, isSmart);
}

/// `CustomListDetail extends Omit<CustomListSummary, "itemsCount" |
/// "previewCovers">` — самостоятельный класс (Dart не умеет Omit).
class CustomListDetail {
  final String id;
  final String name;
  final String? description;
  final String? icon;
  final String? color;
  final String createdAt;
  final List<MediaItem> items;
  final bool isSmart;
  final String? smartQueryJson;

  const CustomListDetail({
    required this.id,
    required this.name,
    required this.description,
    required this.icon,
    required this.color,
    required this.createdAt,
    required this.items,
    required this.isSmart,
    required this.smartQueryJson,
  });

  factory CustomListDetail.fromJson(Map<String, dynamic> json) =>
      CustomListDetail(
        id: json['id'] as String,
        name: json['name'] as String,
        description: json['description'] as String?,
        icon: json['icon'] as String?,
        color: json['color'] as String?,
        createdAt: json['createdAt'] as String,
        items: (json['items'] as List<Object?>? ?? const [])
            .map((e) => MediaItem.fromJson(e as Map<String, dynamic>))
            .toList(),
        isSmart: json['isSmart'] as bool,
        smartQueryJson: json['smartQueryJson'] as String?,
      );

  @override
  bool operator ==(Object other) =>
      other is CustomListDetail &&
      other.id == id &&
      other.name == name &&
      other.items == items &&
      other.isSmart == isSmart;

  @override
  int get hashCode => Object.hash(id, name, items, isSmart);
}

/// Payload создания списка (отправляется на сервер).
class CreateListPayload {
  final String name;
  final String? description;
  final String? icon;
  final String? color;
  final String? smartQueryJson;

  const CreateListPayload({
    required this.name,
    required this.description,
    required this.icon,
    required this.color,
    required this.smartQueryJson,
  });

  Map<String, dynamic> toJson() => <String, dynamic>{
        'name': name,
        'description': description,
        'icon': icon,
        'color': color,
        'smartQueryJson': smartQueryJson,
      };

  @override
  bool operator ==(Object other) =>
      other is CreateListPayload && other.toJson() == toJson();

  @override
  int get hashCode => toJson().hashCode;
}

/// `type UpdateListPayload = CreateListPayload`.
typedef UpdateListPayload = CreateListPayload;

/// Smart-фильтр пользовательского списка (отправляется на сервер как JSON).
class SmartListQuery {
  final List<String>? categories;
  final List<int>? statuses;
  final int? minScore;
  final int? maxScore;
  final bool? onlyUnrated;
  final double? minExternalRating;
  final List<String>? genres;
  final int? releaseYearFrom;
  final int? releaseYearTo;
  final int? maxDurationMinutes;
  final int? maxEpisodes;
  final int? maxPages;
  final int? maxChapters;
  final String? creatorContains;
  /// Release status of the work itself: "FINISHED" | "RELEASING" | "NOT_YET_RELEASED".
  final String? releaseStatus;
  final String? sortBy;
  final String? sortOrder;
  final int? limit;

  const SmartListQuery({
    this.categories,
    this.statuses,
    this.minScore,
    this.maxScore,
    this.onlyUnrated,
    this.minExternalRating,
    this.genres,
    this.releaseYearFrom,
    this.releaseYearTo,
    this.maxDurationMinutes,
    this.maxEpisodes,
    this.maxPages,
    this.maxChapters,
    this.creatorContains,
    this.releaseStatus,
    this.sortBy,
    this.sortOrder,
    this.limit,
  });

  factory SmartListQuery.fromJson(Map<String, dynamic> json) => SmartListQuery(
        categories:
            (json['categories'] as List<dynamic>?)?.cast<String>().toList(),
        statuses: (json['statuses'] as List<dynamic>?)
            ?.map((e) => (e as num).toInt())
            .toList(),
        minScore: (json['minScore'] as num?)?.toInt(),
        maxScore: (json['maxScore'] as num?)?.toInt(),
        onlyUnrated: json['onlyUnrated'] as bool?,
        minExternalRating: (json['minExternalRating'] as num?)?.toDouble(),
        genres: (json['genres'] as List<dynamic>?)?.cast<String>().toList(),
        releaseYearFrom: (json['releaseYearFrom'] as num?)?.toInt(),
        releaseYearTo: (json['releaseYearTo'] as num?)?.toInt(),
        maxDurationMinutes: (json['maxDurationMinutes'] as num?)?.toInt(),
        maxEpisodes: (json['maxEpisodes'] as num?)?.toInt(),
        maxPages: (json['maxPages'] as num?)?.toInt(),
        maxChapters: (json['maxChapters'] as num?)?.toInt(),
        creatorContains: json['creatorContains'] as String?,
        releaseStatus: json['releaseStatus'] as String?,
        sortBy: json['sortBy'] as String?,
        sortOrder: json['sortOrder'] as String?,
        limit: (json['limit'] as num?)?.toInt(),
      );

  SmartListQuery copyWith({
    List<String>? categories,
    List<int>? statuses,
    int? minScore,
    int? maxScore,
    bool? onlyUnrated,
    double? minExternalRating,
    List<String>? genres,
    int? releaseYearFrom,
    int? releaseYearTo,
    int? maxDurationMinutes,
    int? maxEpisodes,
    int? maxPages,
    int? maxChapters,
    String? creatorContains,
    String? releaseStatus,
    String? sortBy,
    String? sortOrder,
    int? limit,
  }) =>
      SmartListQuery(
        categories: categories ?? this.categories,
        statuses: statuses ?? this.statuses,
        minScore: minScore ?? this.minScore,
        maxScore: maxScore ?? this.maxScore,
        onlyUnrated: onlyUnrated ?? this.onlyUnrated,
        minExternalRating: minExternalRating ?? this.minExternalRating,
        genres: genres ?? this.genres,
        releaseYearFrom: releaseYearFrom ?? this.releaseYearFrom,
        releaseYearTo: releaseYearTo ?? this.releaseYearTo,
        maxDurationMinutes: maxDurationMinutes ?? this.maxDurationMinutes,
        maxEpisodes: maxEpisodes ?? this.maxEpisodes,
        maxPages: maxPages ?? this.maxPages,
        maxChapters: maxChapters ?? this.maxChapters,
        creatorContains: creatorContains ?? this.creatorContains,
        releaseStatus: releaseStatus ?? this.releaseStatus,
        sortBy: sortBy ?? this.sortBy,
        sortOrder: sortOrder ?? this.sortOrder,
        limit: limit ?? this.limit,
      );

  Map<String, dynamic> toJson() => <String, dynamic>{
        'categories': categories,
        'statuses': statuses,
        'minScore': minScore,
        'maxScore': maxScore,
        'onlyUnrated': onlyUnrated,
        'minExternalRating': minExternalRating,
        'genres': genres,
        'releaseYearFrom': releaseYearFrom,
        'releaseYearTo': releaseYearTo,
        'maxDurationMinutes': maxDurationMinutes,
        'maxEpisodes': maxEpisodes,
        'maxPages': maxPages,
        'maxChapters': maxChapters,
        'creatorContains': creatorContains,
        'releaseStatus': releaseStatus,
        'sortBy': sortBy,
        'sortOrder': sortOrder,
        'limit': limit,
      };

  @override
  bool operator ==(Object other) =>
      other is SmartListQuery && other.toJson() == toJson();

  @override
  int get hashCode => toJson().hashCode;
}

// ---------------------------------------------------------------------------
// Import.
// ---------------------------------------------------------------------------

class ImportResultDto {
  final int totalFound;
  final int importedCount;
  final int skippedDuplicates;
  final String? targetListId;
  final String? targetListName;
  final List<String>? skippedTitles;
  final String? dumpUrl;
  final String? dumpFileName;

  const ImportResultDto({
    required this.totalFound,
    required this.importedCount,
    required this.skippedDuplicates,
    required this.targetListId,
    required this.targetListName,
    required this.skippedTitles,
    required this.dumpUrl,
    required this.dumpFileName,
  });

  factory ImportResultDto.fromJson(Map<String, dynamic> json) =>
      ImportResultDto(
        totalFound: (json['totalFound'] as num).toInt(),
        importedCount: (json['importedCount'] as num).toInt(),
        skippedDuplicates: (json['skippedDuplicates'] as num).toInt(),
        targetListId: json['targetListId'] as String?,
        targetListName: json['targetListName'] as String?,
        skippedTitles:
            (json['skippedTitles'] as List<Object?>?)?.cast<String>().toList(),
        dumpUrl: json['dumpUrl'] as String?,
        dumpFileName: json['dumpFileName'] as String?,
      );

  @override
  bool operator ==(Object other) =>
      other is ImportResultDto &&
      other.totalFound == totalFound &&
      other.importedCount == importedCount &&
      other.skippedDuplicates == skippedDuplicates &&
      other.targetListId == targetListId &&
      other.dumpFileName == dumpFileName;

  @override
  int get hashCode => Object.hash(totalFound, importedCount, skippedDuplicates,
      targetListId, dumpFileName);
}

/// Payload Steam-импорта.
class SteamImportPayload {
  final String? steamId;
  final String? profileUrl;
  final String? steamApiKey;
  final bool skipDuplicates;
  final String? targetListId;
  final String? newListName;
  /// Drop games under this many played minutes (random launches, refund-bait).
  final int? minPlaytimeMinutes;
  /// Pull the player's unlocked achievements per game (needs the Steam Web API key).
  final bool? syncAchievements;

  const SteamImportPayload({
    required this.steamId,
    required this.profileUrl,
    required this.steamApiKey,
    required this.skipDuplicates,
    required this.targetListId,
    required this.newListName,
    required this.minPlaytimeMinutes,
    required this.syncAchievements,
  });

  Map<String, dynamic> toJson() => <String, dynamic>{
        'steamId': steamId,
        'profileUrl': profileUrl,
        'steamApiKey': steamApiKey,
        'skipDuplicates': skipDuplicates,
        'targetListId': targetListId,
        'newListName': newListName,
        'minPlaytimeMinutes': minPlaytimeMinutes,
        'syncAchievements': syncAchievements,
      };

  @override
  bool operator ==(Object other) =>
      other is SteamImportPayload && other.toJson() == toJson();

  @override
  int get hashCode => toJson().hashCode;
}

/// Payload AniList-импорта.
class AniListProfilePayload {
  final String username;
  final bool? createList;
  final String? targetListId;
  final String? newListName;
  final bool? skipDuplicates;

  const AniListProfilePayload({
    required this.username,
    required this.createList,
    required this.targetListId,
    required this.newListName,
    required this.skipDuplicates,
  });

  Map<String, dynamic> toJson() => <String, dynamic>{
        'username': username,
        'createList': createList,
        'targetListId': targetListId,
        'newListName': newListName,
        'skipDuplicates': skipDuplicates,
      };

  @override
  bool operator ==(Object other) =>
      other is AniListProfilePayload && other.toJson() == toJson();

  @override
  int get hashCode => toJson().hashCode;
}

/// Payload MangaLib-импорта.
class MangaLibProfilePayload {
  final String profileUrlOrId;
  final List<int>? siteIds;
  final String? bearerToken;
  /// Standard SocialLib folder ids (1..6) to import; omitted means all.
  final List<int>? statusIds;
  /// Include the user's custom folder ids returned by bookmarks/folder/{userId}.
  final bool? includeCustomFolders;
  final bool? skipDuplicates;
  final String? targetListId;
  final String? newListName;

  const MangaLibProfilePayload({
    required this.profileUrlOrId,
    required this.siteIds,
    required this.bearerToken,
    required this.statusIds,
    required this.includeCustomFolders,
    required this.skipDuplicates,
    required this.targetListId,
    required this.newListName,
  });

  Map<String, dynamic> toJson() => <String, dynamic>{
        'profileUrlOrId': profileUrlOrId,
        'siteIds': siteIds,
        'bearerToken': bearerToken,
        'statusIds': statusIds,
        'includeCustomFolders': includeCustomFolders,
        'skipDuplicates': skipDuplicates,
        'targetListId': targetListId,
        'newListName': newListName,
      };

  @override
  bool operator ==(Object other) =>
      other is MangaLibProfilePayload && other.toJson() == toJson();

  @override
  int get hashCode => toJson().hashCode;
}

// ---------------------------------------------------------------------------
// Create / Update media payload'ы.
// ---------------------------------------------------------------------------

/// Базовые поля `CreateMediaBase`; `type` задают подклассы.
class CreateMediaBase {
  final String type;
  final String title;
  final MediaStatus status;
  final List<String>? altTitles;
  final int? score;
  final String? coverUrl;
  final String? notes;
  final String? description;
  final String? trailerVideoId;
  final String? franchiseId;
  final String? franchiseName;
  final int? franchiseOrder;
  final String? externalId;
  final String? externalSource;
  final String? importSource;
  final double? externalRating;
  final int? externalRatingVotes;
  final String? externalRatingsJson;
  final String? releaseDate;
  final String? endDate;
  final String? releaseStatus;
  final List<String>? genres;
  final List<String>? tags;
  final String? unlockedAchievements;
  final String? userPlatform;

  const CreateMediaBase({
    required this.type,
    required this.title,
    required this.status,
    required this.altTitles,
    required this.score,
    required this.coverUrl,
    required this.notes,
    required this.description,
    required this.trailerVideoId,
    required this.franchiseId,
    required this.franchiseName,
    required this.franchiseOrder,
    required this.externalId,
    required this.externalSource,
    required this.importSource,
    required this.externalRating,
    required this.externalRatingVotes,
    required this.externalRatingsJson,
    required this.releaseDate,
    required this.endDate,
    required this.releaseStatus,
    required this.genres,
    required this.tags,
    required this.unlockedAchievements,
    required this.userPlatform,
  });

  /// Полиморфная сериализация `CreateMediaPayload`: подклассы переопределяют,
  /// добавляя вариантные поля.
  Map<String, dynamic> toJson() => baseToJson();

  static final _uuidRegex = RegExp(
    r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$',
  );

  static String? _cleanStr(String? v) =>
      (v != null && v.trim().isNotEmpty) ? v.trim() : null;

  static String? _cleanGuid(String? v) {
    if (v == null) return null;
    final trimmed = v.trim();
    return _uuidRegex.hasMatch(trimmed) ? trimmed : null;
  }

  static int? _cleanScore(int? score) {
    if (score == null) return null;
    if (score >= 1 && score <= 10) return score;
    return null;
  }

  static int? _cleanNonNegative(int? v) => (v != null && v >= 0) ? v : null;

  Map<String, dynamic> baseToJson() => <String, dynamic>{
        'type': type,
        'title': title,
        'status': status.value,
        'altTitles': altTitles,
        'score': _cleanScore(score),
        'coverUrl': _cleanStr(coverUrl),
        'notes': _cleanStr(notes),
        'description': _cleanStr(description),
        'trailerVideoId': _cleanStr(trailerVideoId),
        'franchiseId': _cleanGuid(franchiseId),
        'franchiseName': _cleanStr(franchiseName),
        'franchiseOrder': franchiseOrder,
        'externalId': _cleanStr(externalId),
        'externalSource': _cleanStr(externalSource),
        'importSource': _cleanStr(importSource),
        'externalRating': externalRating,
        'externalRatingVotes': externalRatingVotes,
        'externalRatingsJson': _cleanStr(externalRatingsJson),
        'releaseDate': normalizeIsoDate(releaseDate),
        'endDate': normalizeIsoDate(endDate),
        'releaseStatus': _cleanStr(releaseStatus),
        'genres': (genres != null && genres!.isNotEmpty) ? genres!.join(', ') : null,
        'tags': (tags != null && tags!.isNotEmpty) ? tags!.join(', ') : null,
        'unlockedAchievements': _cleanStr(unlockedAchievements),
        'userPlatform': _cleanStr(userPlatform),
      };
}

class CreateGamePayload extends CreateMediaBase {
  final String platform;
  final int? hoursPlayed;

  const CreateGamePayload({
    required this.platform,
    required this.hoursPlayed,
    required super.title,
    required super.status,
    required super.altTitles,
    required super.score,
    required super.coverUrl,
    required super.notes,
    required super.description,
    required super.trailerVideoId,
    required super.franchiseId,
    required super.franchiseName,
    required super.franchiseOrder,
    required super.externalId,
    required super.externalSource,
    required super.importSource,
    required super.externalRating,
    required super.externalRatingVotes,
    required super.externalRatingsJson,
    required super.releaseDate,
    required super.endDate,
    required super.releaseStatus,
    required super.genres,
    required super.tags,
    required super.unlockedAchievements,
    required super.userPlatform,
  }) : super(type: 'game');

  @override
  Map<String, dynamic> toJson() => <String, dynamic>{
        ...baseToJson(),
        'platform': platform.trim().isNotEmpty ? platform.trim() : 'PC',
        'hoursPlayed': CreateMediaBase._cleanNonNegative(hoursPlayed),
      };

  @override
  bool operator ==(Object other) =>
      other is CreateGamePayload && other.toJson() == toJson();

  @override
  int get hashCode => toJson().hashCode;
}

class CreateBookPayload extends CreateMediaBase {
  final String author;
  final String? studio;
  final String? isbn;
  final int? totalPages;
  final String? format;
  final int? currentChapter;
  final int? totalChapters;
  final int? currentVolume;
  final int? totalVolumes;

  const CreateBookPayload({
    required this.author,
    required this.studio,
    required this.isbn,
    required this.totalPages,
    required this.format,
    required this.currentChapter,
    required this.totalChapters,
    required this.currentVolume,
    required this.totalVolumes,
    required super.title,
    required super.status,
    required super.altTitles,
    required super.score,
    required super.coverUrl,
    required super.notes,
    required super.description,
    required super.trailerVideoId,
    required super.franchiseId,
    required super.franchiseName,
    required super.franchiseOrder,
    required super.externalId,
    required super.externalSource,
    required super.importSource,
    required super.externalRating,
    required super.externalRatingVotes,
    required super.externalRatingsJson,
    required super.releaseDate,
    required super.endDate,
    required super.releaseStatus,
    required super.genres,
    required super.tags,
    required super.unlockedAchievements,
    required super.userPlatform,
  }) : super(type: 'book');

  @override
  Map<String, dynamic> toJson() => <String, dynamic>{
        ...baseToJson(),
        'author': author.trim().isNotEmpty ? author.trim() : 'Unknown Author',
        'studio': CreateMediaBase._cleanStr(studio),
        'isbn': CreateMediaBase._cleanStr(isbn),
        'totalPages': CreateMediaBase._cleanNonNegative(totalPages),
        'format': CreateMediaBase._cleanStr(format),
        'currentChapter': CreateMediaBase._cleanNonNegative(currentChapter),
        'totalChapters': CreateMediaBase._cleanNonNegative(totalChapters),
        'currentVolume': CreateMediaBase._cleanNonNegative(currentVolume),
        'totalVolumes': CreateMediaBase._cleanNonNegative(totalVolumes),
      };

  @override
  bool operator ==(Object other) =>
      other is CreateBookPayload && other.toJson() == toJson();

  @override
  int get hashCode => toJson().hashCode;
}

/// Payload создания тома манги.
class CreateVolumePayload {
  final int volumeNumber;
  final String title;
  final String? coverUrl;
  final int? totalPages;
  final int? currentPage;
  final int? totalChapters;
  final int? currentChapter;
  final MediaStatus? status;
  final int? score;
  final String? notes;
  final String? releaseDate;

  const CreateVolumePayload({
    required this.volumeNumber,
    required this.title,
    required this.coverUrl,
    required this.totalPages,
    required this.currentPage,
    required this.totalChapters,
    required this.currentChapter,
    required this.status,
    required this.score,
    required this.notes,
    required this.releaseDate,
  });

  Map<String, dynamic> toJson() => <String, dynamic>{
        'volumeNumber': volumeNumber >= 1 ? volumeNumber : 1,
        'title': (title.trim().isNotEmpty) ? title.trim() : 'Volume 1',
        'coverUrl': CreateMediaBase._cleanStr(coverUrl),
        'totalPages': CreateMediaBase._cleanNonNegative(totalPages),
        'currentPage': CreateMediaBase._cleanNonNegative(currentPage),
        'totalChapters': CreateMediaBase._cleanNonNegative(totalChapters),
        'currentChapter': CreateMediaBase._cleanNonNegative(currentChapter),
        'status': status?.value ?? MediaStatus.planned.value,
        'score': CreateMediaBase._cleanScore(score),
        'notes': CreateMediaBase._cleanStr(notes),
        'releaseDate': normalizeIsoDate(releaseDate),
      };

  @override
  bool operator ==(Object other) =>
      other is CreateVolumePayload && other.toJson() == toJson();

  @override
  int get hashCode => toJson().hashCode;
}

/// Payload частичного обновления тома манги.
class UpdateVolumePayload {
  final String? title;
  final String? coverUrl;
  final int? totalPages;
  final int? currentPage;
  final int? totalChapters;
  final int? currentChapter;
  final MediaStatus? status;
  final int? score;
  final String? notes;

  const UpdateVolumePayload({
    required this.title,
    required this.coverUrl,
    required this.totalPages,
    required this.currentPage,
    required this.totalChapters,
    required this.currentChapter,
    required this.status,
    required this.score,
    required this.notes,
  });

  Map<String, dynamic> toJson() => <String, dynamic>{
        'title': CreateMediaBase._cleanStr(title),
        'coverUrl': CreateMediaBase._cleanStr(coverUrl),
        'totalPages': CreateMediaBase._cleanNonNegative(totalPages),
        'currentPage': CreateMediaBase._cleanNonNegative(currentPage),
        'totalChapters': CreateMediaBase._cleanNonNegative(totalChapters),
        'currentChapter': CreateMediaBase._cleanNonNegative(currentChapter),
        'status': status?.value,
        'score': CreateMediaBase._cleanScore(score),
        'notes': CreateMediaBase._cleanStr(notes),
      };

  @override
  bool operator ==(Object other) =>
      other is UpdateVolumePayload && other.toJson() == toJson();

  @override
  int get hashCode => toJson().hashCode;
}

class CreateMangaPayload extends CreateMediaBase {
  final String? author;
  final String? romajiTitle;
  final int? totalVolumes;
  final int? totalChapters;
  final int? currentVolume;
  final String? format;
  final List<CreateVolumePayload>? volumes;

  const CreateMangaPayload({
    required this.author,
    required this.romajiTitle,
    required this.totalVolumes,
    required this.totalChapters,
    required this.currentVolume,
    this.format,
    required this.volumes,
    required super.title,
    required super.status,
    required super.altTitles,
    required super.score,
    required super.coverUrl,
    required super.notes,
    required super.description,
    required super.trailerVideoId,
    required super.franchiseId,
    required super.franchiseName,
    required super.franchiseOrder,
    required super.externalId,
    required super.externalSource,
    required super.importSource,
    required super.externalRating,
    required super.externalRatingVotes,
    required super.externalRatingsJson,
    required super.releaseDate,
    required super.endDate,
    required super.releaseStatus,
    required super.genres,
    required super.tags,
    required super.unlockedAchievements,
    required super.userPlatform,
  }) : super(type: 'manga');

  @override
  Map<String, dynamic> toJson() => <String, dynamic>{
        ...baseToJson(),
        'author': CreateMediaBase._cleanStr(author),
        'romajiTitle': CreateMediaBase._cleanStr(romajiTitle),
        'format': CreateMediaBase._cleanStr(format),
        'totalVolumes': CreateMediaBase._cleanNonNegative(totalVolumes),
        'totalChapters': CreateMediaBase._cleanNonNegative(totalChapters),
        'currentVolume': CreateMediaBase._cleanNonNegative(currentVolume),
        'volumes': volumes?.map((v) => v.toJson()).toList(),
      };

  @override
  bool operator ==(Object other) =>
      other is CreateMangaPayload && other.toJson() == toJson();

  @override
  int get hashCode => toJson().hashCode;
}

class CreateMoviePayload extends CreateMediaBase {
  final int? durationMinutes;
  final String? director;
  final bool? isAnime;
  final String? studio;
  final String? romajiTitle;

  const CreateMoviePayload({
    required this.durationMinutes,
    required this.director,
    required this.isAnime,
    required this.studio,
    required this.romajiTitle,
    required super.title,
    required super.status,
    required super.altTitles,
    required super.score,
    required super.coverUrl,
    required super.notes,
    required super.description,
    required super.trailerVideoId,
    required super.franchiseId,
    required super.franchiseName,
    required super.franchiseOrder,
    required super.externalId,
    required super.externalSource,
    required super.importSource,
    required super.externalRating,
    required super.externalRatingVotes,
    required super.externalRatingsJson,
    required super.releaseDate,
    required super.endDate,
    required super.releaseStatus,
    required super.genres,
    required super.tags,
    required super.unlockedAchievements,
    required super.userPlatform,
  }) : super(type: 'movie');

  @override
  Map<String, dynamic> toJson() => <String, dynamic>{
        ...baseToJson(),
        'durationMinutes': CreateMediaBase._cleanNonNegative(durationMinutes),
        'director': CreateMediaBase._cleanStr(director),
        'isAnime': isAnime,
        'studio': CreateMediaBase._cleanStr(studio),
        'romajiTitle': CreateMediaBase._cleanStr(romajiTitle),
      };

  @override
  bool operator ==(Object other) =>
      other is CreateMoviePayload && other.toJson() == toJson();

  @override
  int get hashCode => toJson().hashCode;
}

/// Payload создания сезона сериала.
class CreateSeasonPayload {
  final int seasonNumber;
  final String title;
  final String? coverUrl;
  final int totalEpisodes;
  final MediaStatus? status;
  final int? score;
  final String? notes;
  final String? airDate;
  final String? episodesData;

  const CreateSeasonPayload({
    required this.seasonNumber,
    required this.title,
    required this.coverUrl,
    required this.totalEpisodes,
    required this.status,
    required this.score,
    required this.notes,
    required this.airDate,
    required this.episodesData,
  });

  Map<String, dynamic> toJson() => <String, dynamic>{
        'seasonNumber': seasonNumber >= 1 ? seasonNumber : 1,
        'title': (title.trim().isNotEmpty) ? title.trim() : 'Season 1',
        'coverUrl': CreateMediaBase._cleanStr(coverUrl),
        'totalEpisodes': CreateMediaBase._cleanNonNegative(totalEpisodes) ?? 0,
        'status': status?.value ?? MediaStatus.planned.value,
        'score': CreateMediaBase._cleanScore(score),
        'notes': CreateMediaBase._cleanStr(notes),
        'airDate': normalizeIsoDate(airDate),
        'episodesData': CreateMediaBase._cleanStr(episodesData),
      };

  @override
  bool operator ==(Object other) =>
      other is CreateSeasonPayload && other.toJson() == toJson();

  @override
  int get hashCode => toJson().hashCode;
}

class CreateTvShowPayload extends CreateMediaBase {
  final bool? isAnime;
  final String? studio;
  final String? romajiTitle;
  final String? network;
  final int? durationMinutes;
  final int? episodeDurationMinutes;
  final List<CreateSeasonPayload>? seasons;

  const CreateTvShowPayload({
    required this.isAnime,
    required this.studio,
    required this.romajiTitle,
    required this.network,
    required this.durationMinutes,
    required this.episodeDurationMinutes,
    required this.seasons,
    required super.title,
    required super.status,
    required super.altTitles,
    required super.score,
    required super.coverUrl,
    required super.notes,
    required super.description,
    required super.trailerVideoId,
    required super.franchiseId,
    required super.franchiseName,
    required super.franchiseOrder,
    required super.externalId,
    required super.externalSource,
    required super.importSource,
    required super.externalRating,
    required super.externalRatingVotes,
    required super.externalRatingsJson,
    required super.releaseDate,
    required super.endDate,
    required super.releaseStatus,
    required super.genres,
    required super.tags,
    required super.unlockedAchievements,
    required super.userPlatform,
  }) : super(type: 'tvshow');

  @override
  Map<String, dynamic> toJson() => <String, dynamic>{
        ...baseToJson(),
        'isAnime': isAnime,
        'studio': CreateMediaBase._cleanStr(studio),
        'romajiTitle': CreateMediaBase._cleanStr(romajiTitle),
        'network': CreateMediaBase._cleanStr(network),
        'durationMinutes': CreateMediaBase._cleanNonNegative(durationMinutes),
        'episodeDurationMinutes': CreateMediaBase._cleanNonNegative(episodeDurationMinutes),
        'seasons': seasons?.map((s) => s.toJson()).toList(),
      };

  @override
  bool operator ==(Object other) =>
      other is CreateTvShowPayload && other.toJson() == toJson();

  @override
  int get hashCode => toJson().hashCode;
}

/// `CreateMediaPayload` — union из 5 вариантов: в Dart общий supertype
/// [CreateMediaBase]; у всех подклассов есть `toJson()`, сериализующийся ровно
/// как соответствующий TS-вариант.

/// Payload частичного обновления медиа.
class UpdateMediaPayload {
  final String? title;
  final List<String>? altTitles;
  final int? score;
  final bool? clearScore;
  final String? detailedScoreJson;
  final bool? clearDetailedScore;
  final MediaStatus? status;
  final String? notes;
  final String? quotesJson;
  final String? coverUrl;
  final String? startedAt;
  final String? finishedAt;
  final String? lastActivityAt;
  final String? franchiseId;
  final String? franchiseName;
  final int? franchiseOrder;
  final String? author;
  final String? isbn;
  final String? format;
  final String? romajiTitle;
  final int? totalVolumes;
  final int? currentVolume;
  final int? totalChapters;
  final int? currentChapter;
  final int? totalPages;
  final int? currentPage;
  final String? translatedSynopsis;
  final String? translationLanguage;
  final String? platform;
  final String? userPlatform;
  /// Explicit null means "not supplied"; these flags are what actually clear the value.
  final bool? clearUserPlatform;
  final bool? clearWatchedOn;
  final bool? clearDropReason;
  final String? dropReason;
  final String? dropNotes;
  final String? watchedOn;
  final int? releaseYear;
  final String? genres;
  final String? tags;
  final String? unlockedAchievements;
  /// Cached Related-tab payload plus the source it came from; written after a successful load.
  final String? relatedMediaJson;
  final String? relatedSource;
  final String? achievementsJson;
  final String? recommendationsJson;
  /// Set once the user edits a field by hand; drives the refresh overwrite prompt.
  final bool? isCustomEdited;

  const UpdateMediaPayload({
    this.title,
    this.altTitles,
    this.score,
    this.clearScore,
    this.detailedScoreJson,
    this.clearDetailedScore,
    this.status,
    this.notes,
    this.quotesJson,
    this.coverUrl,
    this.startedAt,
    this.finishedAt,
    this.lastActivityAt,
    this.franchiseId,
    this.franchiseName,
    this.franchiseOrder,
    this.author,
    this.isbn,
    this.format,
    this.romajiTitle,
    this.totalVolumes,
    this.currentVolume,
    this.totalChapters,
    this.currentChapter,
    this.totalPages,
    this.currentPage,
    this.translatedSynopsis,
    this.translationLanguage,
    this.platform,
    this.userPlatform,
    this.clearUserPlatform,
    this.clearWatchedOn,
    this.clearDropReason,
    this.dropReason,
    this.dropNotes,
    this.watchedOn,
    this.releaseYear,
    this.genres,
    this.tags,
    this.unlockedAchievements,
    this.relatedMediaJson,
    this.relatedSource,
    this.achievementsJson,
    this.recommendationsJson,
    this.isCustomEdited,
  });

  Map<String, dynamic> toJson() => <String, dynamic>{
        'title': title,
        'altTitles': altTitles,
        'score': score,
        'clearScore': clearScore,
        'detailedScoreJson': detailedScoreJson,
        'clearDetailedScore': clearDetailedScore,
        'status': status?.value,
        'notes': notes,
        'quotesJson': quotesJson,
        'coverUrl': coverUrl,
        'startedAt': startedAt,
        'finishedAt': finishedAt,
        'lastActivityAt': lastActivityAt,
        'franchiseId': franchiseId,
        'franchiseName': franchiseName,
        'franchiseOrder': franchiseOrder,
        'author': author,
        'isbn': isbn,
        'format': format,
        'romajiTitle': romajiTitle,
        'totalVolumes': totalVolumes,
        'currentVolume': currentVolume,
        'totalChapters': totalChapters,
        'currentChapter': currentChapter,
        'totalPages': totalPages,
        'currentPage': currentPage,
        'translatedSynopsis': translatedSynopsis,
        'translationLanguage': translationLanguage,
        'platform': platform,
        'userPlatform': userPlatform,
        'clearUserPlatform': clearUserPlatform,
        'clearWatchedOn': clearWatchedOn,
        'clearDropReason': clearDropReason,
        'dropReason': dropReason,
        'dropNotes': dropNotes,
        'watchedOn': watchedOn,
        'releaseYear': releaseYear,
        'genres': genres,
        'tags': tags,
        'unlockedAchievements': unlockedAchievements,
        'relatedMediaJson': relatedMediaJson,
        'relatedSource': relatedSource,
        'achievementsJson': achievementsJson,
        'recommendationsJson': recommendationsJson,
        'isCustomEdited': isCustomEdited,
      };

  @override
  bool operator ==(Object other) =>
      other is UpdateMediaPayload && other.toJson() == toJson();

  @override
  int get hashCode => toJson().hashCode;
}

// ---------------------------------------------------------------------------
// Sources / search / api tokens (read-only).
// ---------------------------------------------------------------------------

class SourceInfo {
  final String id;
  final String name;
  final String description;
  final List<String> mediaTypes;
  final bool requiresApiKey;
  /// True when the source works without a key but can still use one (Steam).
  final bool optionalApiKey;
  final bool isConfigured;
  final bool hasKey;
  final String? maskedKey;
  final bool isEnabled;
  /// True for site scrapers (no public API) — the settings list splits on this flag.
  final bool isScraper;
  /// Источник отмечен в ProxiedSources — его запросы идут через настроенный прокси.
  final bool? isProxied;

  const SourceInfo({
    required this.id,
    required this.name,
    required this.description,
    required this.mediaTypes,
    required this.requiresApiKey,
    required this.optionalApiKey,
    required this.isConfigured,
    required this.hasKey,
    required this.maskedKey,
    required this.isEnabled,
    required this.isScraper,
    required this.isProxied,
  });

  factory SourceInfo.fromJson(Map<String, dynamic> json) => SourceInfo(
        id: json['id'] as String,
        name: json['name'] as String,
        description: json['description'] as String,
        mediaTypes:
            (json['mediaTypes'] as List<Object?>? ?? const []).cast<String>().toList(),
        requiresApiKey: json['requiresApiKey'] as bool,
        optionalApiKey: json['optionalApiKey'] as bool,
        isConfigured: json['isConfigured'] as bool,
        hasKey: json['hasKey'] as bool,
        maskedKey: json['maskedKey'] as String?,
        isEnabled: json['isEnabled'] as bool,
        isScraper: json['isScraper'] as bool,
        isProxied: json['isProxied'] as bool?,
      );

  SourceInfo copyWith({
    String? id,
    String? name,
    String? description,
    List<String>? mediaTypes,
    bool? requiresApiKey,
    bool? optionalApiKey,
    bool? isConfigured,
    bool? hasKey,
    String? maskedKey,
    bool? isEnabled,
    bool? isScraper,
    bool? isProxied,
  }) =>
      SourceInfo(
        id: id ?? this.id,
        name: name ?? this.name,
        description: description ?? this.description,
        mediaTypes: mediaTypes ?? this.mediaTypes,
        requiresApiKey: requiresApiKey ?? this.requiresApiKey,
        optionalApiKey: optionalApiKey ?? this.optionalApiKey,
        isConfigured: isConfigured ?? this.isConfigured,
        hasKey: hasKey ?? this.hasKey,
        maskedKey: maskedKey ?? this.maskedKey,
        isEnabled: isEnabled ?? this.isEnabled,
        isScraper: isScraper ?? this.isScraper,
        isProxied: isProxied ?? this.isProxied,
      );

  @override
  bool operator ==(Object other) =>
      other is SourceInfo &&
      other.id == id &&
      other.name == name &&
      other.isEnabled == isEnabled &&
      other.isScraper == isScraper;

  @override
  int get hashCode => Object.hash(id, name, isEnabled, isScraper);
}

/// Context the creator card passes into the search modal: the query is a
/// studio/author name, the type is the category it belongs to and byCreator
/// asks the sources for that creator's works.
class SearchModalContext {
  final String query;
  final String? type;
  final String? source;
  final bool? byCreator;

  const SearchModalContext({
    required this.query,
    required this.type,
    required this.source,
    required this.byCreator,
  });

  @override
  bool operator ==(Object other) =>
      other is SearchModalContext &&
      other.query == query &&
      other.type == type &&
      other.source == source &&
      other.byCreator == byCreator;

  @override
  int get hashCode => Object.hash(query, type, source, byCreator);
}

class ConnectionTestResult {
  final bool success;
  final int latencyMs;
  final String message;

  const ConnectionTestResult({
    required this.success,
    required this.latencyMs,
    required this.message,
  });

  factory ConnectionTestResult.fromJson(Map<String, dynamic> json) =>
      ConnectionTestResult(
        success: json['success'] as bool,
        latencyMs: (json['latencyMs'] as num).toInt(),
        message: json['message'] as String,
      );

  @override
  bool operator ==(Object other) =>
      other is ConnectionTestResult &&
      other.success == success &&
      other.latencyMs == latencyMs &&
      other.message == message;

  @override
  int get hashCode => Object.hash(success, latencyMs, message);
}

class ApiTokenSummary {
  final String id;
  final String name;
  final String tokenPrefix;
  final String createdAt;
  final String? lastUsedAt;
  final String? expiresAt;

  const ApiTokenSummary({
    required this.id,
    required this.name,
    required this.tokenPrefix,
    required this.createdAt,
    required this.lastUsedAt,
    required this.expiresAt,
  });

  factory ApiTokenSummary.fromJson(Map<String, dynamic> json) =>
      ApiTokenSummary(
        id: json['id'] as String,
        name: json['name'] as String,
        tokenPrefix: json['tokenPrefix'] as String,
        createdAt: json['createdAt'] as String,
        lastUsedAt: json['lastUsedAt'] as String?,
        expiresAt: json['expiresAt'] as String?,
      );

  @override
  bool operator ==(Object other) =>
      other is ApiTokenSummary &&
      other.id == id &&
      other.name == name &&
      other.tokenPrefix == tokenPrefix;

  @override
  int get hashCode => Object.hash(id, name, tokenPrefix);
}

class CreateApiTokenResponse {
  final String id;
  final String name;
  final String tokenPrefix;
  final String rawToken;

  const CreateApiTokenResponse({
    required this.id,
    required this.name,
    required this.tokenPrefix,
    required this.rawToken,
  });

  factory CreateApiTokenResponse.fromJson(Map<String, dynamic> json) =>
      CreateApiTokenResponse(
        id: json['id'] as String,
        name: json['name'] as String,
        tokenPrefix: json['tokenPrefix'] as String,
        rawToken: json['rawToken'] as String,
      );

  @override
  bool operator ==(Object other) =>
      other is CreateApiTokenResponse &&
      other.id == id &&
      other.name == name &&
      other.rawToken == rawToken;

  @override
  int get hashCode => Object.hash(id, name, rawToken);
}

/// `"auto_refresh" | "air_date" | "release"`.
enum CalendarEventKind {
  autoRefresh('auto_refresh'),
  airDate('air_date'),
  release('release');

  final String wire;
  const CalendarEventKind(this.wire);

  static CalendarEventKind? tryFromWire(String wire) {
    for (final s in values) {
      if (s.wire == wire) return s;
    }
    return null;
  }

  static CalendarEventKind fromWire(String wire) =>
      tryFromWire(wire) ??
      (throw ArgumentError.value(wire, 'CalendarEventKind', 'unknown wire value'));
}

class CalendarItemDto {
  final String mediaId;
  final String title;
  final String type;
  final String? coverUrl;
  final int? currentProgress;
  final int? totalCount;
  final CalendarEventKind kind;
  final String? details;
  final int? episodeNumber;
  final int? seasonNumber;
  final bool? isAnime;

  const CalendarItemDto({
    required this.mediaId,
    required this.title,
    required this.type,
    required this.coverUrl,
    required this.currentProgress,
    required this.totalCount,
    required this.kind,
    required this.details,
    required this.episodeNumber,
    required this.seasonNumber,
    required this.isAnime,
  });

  factory CalendarItemDto.fromJson(Map<String, dynamic> json) =>
      CalendarItemDto(
        mediaId: json['mediaId'] as String,
        title: json['title'] as String,
        type: json['type'] as String,
        coverUrl: json['coverUrl'] as String?,
        currentProgress: _int(json['currentProgress']),
        totalCount: _int(json['totalCount']),
        kind: CalendarEventKind.fromWire(json['kind'] as String),
        details: json['details'] as String?,
        episodeNumber: _int(json['episodeNumber']),
        seasonNumber: _int(json['seasonNumber']),
        isAnime: json['isAnime'] as bool?,
      );

  @override
  bool operator ==(Object other) =>
      other is CalendarItemDto &&
      other.mediaId == mediaId &&
      other.title == title &&
      other.kind == kind &&
      other.episodeNumber == episodeNumber;

  @override
  int get hashCode => Object.hash(mediaId, title, kind, episodeNumber);
}

/// `date` — "YYYY-MM-DD".
class CalendarDayDto {
  final String date;
  final List<CalendarItemDto> items;

  const CalendarDayDto({required this.date, required this.items});

  factory CalendarDayDto.fromJson(Map<String, dynamic> json) => CalendarDayDto(
        date: json['date'] as String,
        items: (json['items'] as List<Object?>? ?? const [])
            .map((e) => CalendarItemDto.fromJson(e as Map<String, dynamic>))
            .toList(),
      );

  @override
  bool operator ==(Object other) =>
      other is CalendarDayDto && other.date == date && other.items == items;

  @override
  int get hashCode => Object.hash(date, items);
}

class CalendarScheduleDto {
  final String from;
  final String to;
  final List<CalendarDayDto> days;

  const CalendarScheduleDto({
    required this.from,
    required this.to,
    required this.days,
  });

  factory CalendarScheduleDto.fromJson(Map<String, dynamic> json) =>
      CalendarScheduleDto(
        from: json['from'] as String,
        to: json['to'] as String,
        days: (json['days'] as List<Object?>? ?? const [])
            .map((e) => CalendarDayDto.fromJson(e as Map<String, dynamic>))
            .toList(),
      );

  @override
  bool operator ==(Object other) =>
      other is CalendarScheduleDto &&
      other.from == from &&
      other.to == to &&
      other.days == days;

  @override
  int get hashCode => Object.hash(from, to, days);
}

/// A release within the next 30 days the user is behind on;
/// see /calendar/backlog-deadlines.
class BacklogDeadlineDto {
  final String mediaId;
  final String title;
  final String type;
  final String? coverUrl;
  /// "air_date" — behind on an ongoing; "release" — franchise sequel with an unfinished previous part.
  final CalendarEventKind kind;
  /// "YYYY-MM-DD"
  final String deadlineDate;
  final int daysLeft;
  final int? episodeNumber;
  final int? seasonNumber;
  /// Episodes/chapters left to catch up; null for franchise sequels.
  final int? behindCount;
  /// The previous franchise part to finish first; null for ongoing catch-ups.
  final String? blockerTitle;
  final int? blockerProgress;
  final int? blockerTotalCount;

  const BacklogDeadlineDto({
    required this.mediaId,
    required this.title,
    required this.type,
    required this.coverUrl,
    required this.kind,
    required this.deadlineDate,
    required this.daysLeft,
    required this.episodeNumber,
    required this.seasonNumber,
    required this.behindCount,
    required this.blockerTitle,
    required this.blockerProgress,
    required this.blockerTotalCount,
  });

  factory BacklogDeadlineDto.fromJson(Map<String, dynamic> json) =>
      BacklogDeadlineDto(
        mediaId: json['mediaId'] as String,
        title: json['title'] as String,
        type: json['type'] as String,
        coverUrl: json['coverUrl'] as String?,
        kind: CalendarEventKind.fromWire(json['kind'] as String),
        deadlineDate: json['deadlineDate'] as String,
        daysLeft: (json['daysLeft'] as num).toInt(),
        episodeNumber: _int(json['episodeNumber']),
        seasonNumber: _int(json['seasonNumber']),
        behindCount: _int(json['behindCount']),
        blockerTitle: json['blockerTitle'] as String?,
        blockerProgress: _int(json['blockerProgress']),
        blockerTotalCount: _int(json['blockerTotalCount']),
      );

  @override
  bool operator ==(Object other) =>
      other is BacklogDeadlineDto &&
      other.mediaId == mediaId &&
      other.kind == kind &&
      other.deadlineDate == deadlineDate &&
      other.daysLeft == daysLeft;

  @override
  int get hashCode => Object.hash(mediaId, kind, deadlineDate, daysLeft);
}

/// One yearly/thematic goal with its live progress; see GET /api/goals?year=.
class GoalDto {
  final String id;
  final String title;
  final String? description;
  /// Emoji or icon key shown on the card.
  final String icon;
  final int year;
  final int targetCount;
  final int currentCount;
  final bool isCompleted;
  /// "all" | "book" | "movie" | "anime" | "manga" | "game" | "tvshow".
  final String? category;
  final String? smartQueryJson;
  /// Up to 6 most recent completed titles counting toward the goal (cover strip).
  final List<MediaItem> completedItems;

  const GoalDto({
    required this.id,
    required this.title,
    required this.description,
    required this.icon,
    required this.year,
    required this.targetCount,
    required this.currentCount,
    required this.isCompleted,
    required this.category,
    required this.smartQueryJson,
    required this.completedItems,
  });

  factory GoalDto.fromJson(Map<String, dynamic> json) => GoalDto(
        id: json['id'] as String,
        title: json['title'] as String,
        description: json['description'] as String?,
        icon: json['icon'] as String,
        year: (json['year'] as num).toInt(),
        targetCount: (json['targetCount'] as num).toInt(),
        currentCount: (json['currentCount'] as num).toInt(),
        isCompleted: json['isCompleted'] as bool,
        category: json['category'] as String?,
        smartQueryJson: json['smartQueryJson'] as String?,
        completedItems: (json['completedItems'] as List<Object?>? ?? const [])
            .map((e) => MediaItem.fromJson(e as Map<String, dynamic>))
            .toList(),
      );

  @override
  bool operator ==(Object other) =>
      other is GoalDto &&
      other.id == id &&
      other.title == title &&
      other.currentCount == currentCount &&
      other.isCompleted == isCompleted;

  @override
  int get hashCode => Object.hash(id, title, currentCount, isCompleted);
}

/// Payload создания цели (отправляется на сервер).
class CreateGoalPayload {
  final String title;
  final String? description;
  final String? icon;
  final int year;
  final int targetCount;
  final String? category;
  final String? smartQueryJson;

  const CreateGoalPayload({
    required this.title,
    required this.description,
    required this.icon,
    required this.year,
    required this.targetCount,
    required this.category,
    required this.smartQueryJson,
  });

  Map<String, dynamic> toJson() => <String, dynamic>{
        'title': title,
        'description': description,
        'icon': icon,
        'year': year,
        'targetCount': targetCount,
        'category': category,
        'smartQueryJson': smartQueryJson,
      };

  @override
  bool operator ==(Object other) =>
      other is CreateGoalPayload && other.toJson() == toJson();

  @override
  int get hashCode => toJson().hashCode;
}

class ApiRateLimitStatus {
  final String provider;
  final int remaining;
  final int limit;
  final int resetSecondsRemaining;
  final String updatedAt;

  const ApiRateLimitStatus({
    required this.provider,
    required this.remaining,
    required this.limit,
    required this.resetSecondsRemaining,
    required this.updatedAt,
  });

  factory ApiRateLimitStatus.fromJson(Map<String, dynamic> json) =>
      ApiRateLimitStatus(
        provider: json['provider'] as String,
        remaining: (json['remaining'] as num).toInt(),
        limit: (json['limit'] as num).toInt(),
        resetSecondsRemaining: (json['resetSecondsRemaining'] as num).toInt(),
        updatedAt: json['updatedAt'] as String,
      );

  @override
  bool operator ==(Object other) =>
      other is ApiRateLimitStatus &&
      other.provider == provider &&
      other.remaining == remaining &&
      other.limit == limit &&
      other.resetSecondsRemaining == resetSecondsRemaining;

  @override
  int get hashCode => Object.hash(provider, remaining, limit,
      resetSecondsRemaining);
}
