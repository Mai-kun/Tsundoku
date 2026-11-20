/// 1:1 port of `mediatracker-ui/src/shared/types/enums.ts`.
///
/// Стратегия портирования union-типов (зафиксировано в FLUTTER_MIGRATION.md,
/// «⚖️ Спорные решения и развилки» #1/#2):
/// - числовые const-объекты TS (`SYNC_STATUS`, `MEDIA_STATUS`) → enum с полем
///   `value`; `tryValue`/`tryFromWire` возвращают null для неизвестных wire-значений
///   (в Svelte неизвестные числа свободно проходят дальше по логике), `fromValue`/
///   `fromWire` бросают [ArgumentError];
/// - строковые union (`JobStatus`, `HistoryEventType`, `SettingsTab`, `SortBy`,
///   `SortOrder`, `MediaType`) → enum с полем `wire` (точная строка сервера);
/// - открытые union (`AppView`, `SearchMediaType`, `SearchScope`, `StatusFilter`)
///   → `String`-typedef с набором известных значений / nullable-обёртка.
library;

/// Mirrors `SYNC_STATUS` (numeric const object).
enum SyncStatus {
  ready(0),
  syncing(1),
  failed(2),
  /// Ambiguous matches found; the user has to pick one or skip.
  needsReview(3);

  final int value;
  const SyncStatus(this.value);

  static SyncStatus? tryValue(int value) {
    for (final s in values) {
      if (s.value == value) return s;
    }
    return null;
  }

  static SyncStatus fromValue(int value) =>
      tryValue(value) ??
      (throw ArgumentError.value(value, 'SyncStatus', 'unknown value'));
}

/// Mirrors JobStatus on the server, which serialises the enum by name.
enum JobStatus {
  queued('Queued'),
  running('Running'),
  completed('Completed'),
  failed('Failed'),
  cancelled('Cancelled');

  final String wire;
  const JobStatus(this.wire);

  static JobStatus? tryFromWire(String wire) {
    for (final s in values) {
      if (s.wire == wire) return s;
    }
    return null;
  }

  static JobStatus fromWire(String wire) =>
      tryFromWire(wire) ??
      (throw ArgumentError.value(wire, 'JobStatus', 'unknown wire value'));
}

/// 1:1 port of the `JobProgress` interface from enums.ts.
///
/// `startedAt` остаётся wire-строкой ISO-8601 (1-в-1); парсинг в [DateTime] —
/// у потребителей (YAGNI).
class JobProgress {
  final String jobId;
  final String? mediaId;
  final String title;
  final double progressPercent;
  final String currentStep;
  final JobStatus status;
  final String startedAt;
  final String? errorMessage;

  const JobProgress({
    required this.jobId,
    required this.mediaId,
    required this.title,
    required this.progressPercent,
    required this.currentStep,
    required this.status,
    required this.startedAt,
    required this.errorMessage,
  });

  factory JobProgress.fromJson(Map<String, dynamic> json) => JobProgress(
        jobId: json['jobId'] as String,
        mediaId: json['mediaId'] as String?,
        title: json['title'] as String,
        progressPercent: (json['progressPercent'] as num).toDouble(),
        currentStep: json['currentStep'] as String,
        status: JobStatus.fromWire(json['status'] as String),
        startedAt: json['startedAt'] as String,
        errorMessage: json['errorMessage'] as String?,
      );

  Map<String, dynamic> toJson() => <String, dynamic>{
        'jobId': jobId,
        'mediaId': mediaId,
        'title': title,
        'progressPercent': progressPercent,
        'currentStep': currentStep,
        'status': status.wire,
        'startedAt': startedAt,
        'errorMessage': errorMessage,
      };

  @override
  bool operator ==(Object other) =>
      other is JobProgress &&
      other.jobId == jobId &&
      other.mediaId == mediaId &&
      other.title == title &&
      other.progressPercent == progressPercent &&
      other.currentStep == currentStep &&
      other.status == status &&
      other.startedAt == startedAt &&
      other.errorMessage == errorMessage;

  @override
  int get hashCode => Object.hash(jobId, mediaId, title, progressPercent,
      currentStep, status, startedAt, errorMessage);

  @override
  String toString() =>
      'JobProgress(${toJson()})';
}

/// Mirrors `MEDIA_STATUS` (numeric const object).
enum MediaStatus {
  planned(0),
  inProgress(1),
  completed(2),
  onHold(3),
  dropped(4);

  final int value;
  const MediaStatus(this.value);

  static MediaStatus? tryValue(int value) {
    for (final s in values) {
      if (s.value == value) return s;
    }
    return null;
  }

  static MediaStatus fromValue(int value) =>
      tryValue(value) ??
      (throw ArgumentError.value(value, 'MediaStatus', 'unknown value'));
}

/// `type StatusFilter = "all" | MediaStatus`.
///
/// null = "all"; числовой статус — как в API.
class StatusFilter {
  /// null означает `all`.
  final int? status;

  const StatusFilter.all() : status = null;

  const StatusFilter.status(int value) : status = value;

  StatusFilter.of(MediaStatus mediaStatus) : status = mediaStatus.value;

  bool get isAll => status == null;

  @override
  bool operator ==(Object other) =>
      other is StatusFilter && other.status == status;

  @override
  int get hashCode => status.hashCode;

  @override
  String toString() =>
      isAll ? 'StatusFilter.all' : 'StatusFilter(${MediaStatus.tryValue(status!)})';
}

/// `type MediaType = "game" | "movie" | "tvshow" | "book" | "manga"`.
enum MediaType {
  game('game'),
  movie('movie'),
  tvshow('tvshow'),
  book('book'),
  manga('manga');

  final String wire;
  const MediaType(this.wire);

  static MediaType? tryFromWire(String wire) {
    for (final s in values) {
      if (s.wire == wire) return s;
    }
    return null;
  }

  static MediaType fromWire(String wire) =>
      tryFromWire(wire) ??
      (throw ArgumentError.value(wire, 'MediaType', 'unknown wire value'));
}

/// `type SearchMediaType = MediaType | "anime"` — открытый строковый union,
/// представлен wire-строкой (см. решение #2).
typedef SearchMediaType = String;

const String searchTypeAnime = 'anime';

/// `type SearchScope = SearchMediaType | "all"`.
typedef SearchScope = String;

const String searchScopeAll = 'all';

/// Известные значения `SearchMediaType` (MediaType + anime).
final Set<String> knownSearchMediaTypes = <String>{
  ...MediaType.values.map((m) => m.wire),
  searchTypeAnime,
};

/// Известные значения `SearchScope` (SearchMediaType + all).
final Set<String> knownSearchScopes = <String>{
  ...knownSearchMediaTypes,
  searchScopeAll,
};

/// `type AppView = "home" | MediaType | <slug категории> | "stats" | ...` —
/// открытый union, представлен wire-строкой (см. решение #2); slug'и
/// пользовательских категорий свободно проходят.
typedef AppView = String;

abstract final class AppViews {
  static const String home = 'home';
  static const String stats = 'stats';
  static const String lists = 'lists';
  static const String history = 'history';
  static const String calendar = 'calendar';
  static const String goals = 'goals';
  static const String seasons = 'seasons';
  static const String settings = 'settings';
  static const String detail = 'detail';

  /// Встроенные (не-slug) значения `AppView`.
  static final Set<String> builtin = <String>{
    ...MediaType.values.map((m) => m.wire),
    stats,
    lists,
    history,
    calendar,
    goals,
    seasons,
    settings,
    detail,
    home,
  };
}

/// Settings sections, deep-linkable through the view.
enum SettingsTab {
  sources('sources'),
  search('search'),
  backup('backup'),
  import('import'),
  reading('reading'),
  apiTokens('apiTokens'),
  update('update'),
  storage('storage'),
  desktop('desktop'),
  appearance('appearance');

  final String wire;
  const SettingsTab(this.wire);

  static SettingsTab? tryFromWire(String wire) {
    for (final s in values) {
      if (s.wire == wire) return s;
    }
    return null;
  }

  static SettingsTab fromWire(String wire) =>
      tryFromWire(wire) ??
      (throw ArgumentError.value(wire, 'SettingsTab', 'unknown wire value'));
}

enum SortBy {
  createdAt('createdAt'),
  score('score'),
  title('title');

  final String wire;
  const SortBy(this.wire);

  static SortBy? tryFromWire(String wire) {
    for (final s in values) {
      if (s.wire == wire) return s;
    }
    return null;
  }

  static SortBy fromWire(String wire) =>
      tryFromWire(wire) ??
      (throw ArgumentError.value(wire, 'SortBy', 'unknown wire value'));
}

enum SortOrder {
  asc('asc'),
  desc('desc');

  final String wire;
  const SortOrder(this.wire);

  static SortOrder? tryFromWire(String wire) {
    for (final s in values) {
      if (s.wire == wire) return s;
    }
    return null;
  }

  static SortOrder fromWire(String wire) =>
      tryFromWire(wire) ??
      (throw ArgumentError.value(wire, 'SortOrder', 'unknown wire value'));
}

enum HistoryEventType {
  added('Added'),
  statusChanged('StatusChanged'),
  scoreChanged('ScoreChanged'),
  progressChanged('ProgressChanged'),
  deleted('Deleted'),
  achievementUnlocked('AchievementUnlocked');

  final String wire;
  const HistoryEventType(this.wire);

  static HistoryEventType? tryFromWire(String wire) {
    for (final s in values) {
      if (s.wire == wire) return s;
    }
    return null;
  }

  static HistoryEventType fromWire(String wire) =>
      tryFromWire(wire) ??
      (throw ArgumentError.value(wire, 'HistoryEventType', 'unknown wire value'));
}
