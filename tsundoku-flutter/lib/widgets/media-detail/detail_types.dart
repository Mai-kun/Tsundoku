/// 1:1 port of `mediatracker-ui/src/widgets/media-detail/detailTypes.ts`.
///
/// Клиентские view-типы детальной страницы (сервер их не шлёт) — read-only
/// классы без toJson (конвенция models.dart, решение YAGNI).
library;

import '../../shared/types/models.dart';

/// Прогресс чтения/просмотра для карточек-секций детальной страницы.
class ProgressInfo {
  final int current;
  final int? total;
  final bool editable;
  final String label;

  const ProgressInfo({
    required this.current,
    required this.total,
    required this.editable,
    required this.label,
  });
}

class SpecRow {
  final String label;
  final String value;

  /// Absolute URL when the value is a link; the sidebar renders an anchor
  /// instead of plain text.
  final String? href;
  final List<String>? badges;
  final String? importSource;

  const SpecRow({
    required this.label,
    required this.value,
    this.href,
    this.badges,
    this.importSource,
  });
}

class EpisodeRow {
  final String id;
  final int number;
  final String title;
  final String? airDate;
  final String? description;
  final bool watched;

  const EpisodeRow({
    required this.id,
    required this.number,
    required this.title,
    required this.airDate,
    required this.description,
    required this.watched,
  });
}

/// The next unwatched episode of the series, not of one season. The season it
/// belongs to carries its own id so the caller can select and expand that
/// season before marking the episode, which is what makes the banner roll from
/// "S1 E7" over to "S2 E1" on its own.
class NextUp {
  final String seasonId;
  final int seasonNumber;
  final int episodeNumber;

  const NextUp({
    required this.seasonId,
    required this.seasonNumber,
    required this.episodeNumber,
  });
}

class RecommendationItem {
  final String id;
  final String title;
  final String? coverUrl;
  final double? rating;
  final String source;

  const RecommendationItem({
    required this.id,
    required this.title,
    required this.coverUrl,
    required this.rating,
    required this.source,
  });
}

class RelatedEntry {
  final String id;
  final String title;
  final String? originalTitle;
  final String? coverUrl;
  final String? bannerUrl;
  final String type;
  final String? format;
  final int? year;
  final String? relationType;
  final String? rawRelationType;
  final double? score;
  final List<RatingBadge>? ratings;
  final String? description;
  final String? trailerVideoId;
  final int? episodes;
  final int? chapters;
  final int? volumes;
  final String? studio;
  final String? author;
  final String? romajiTitle;
  final int? duration;
  final String? releaseDate;
  final String? endDate;
  final String? releaseStatus;
  final String? externalSource;
  final MediaItem? localItem;

  const RelatedEntry({
    required this.id,
    required this.title,
    this.originalTitle,
    this.coverUrl,
    this.bannerUrl,
    required this.type,
    this.format,
    this.year,
    this.relationType,
    this.rawRelationType,
    this.score,
    this.ratings,
    this.description,
    this.trailerVideoId,
    this.episodes,
    this.chapters,
    this.volumes,
    this.studio,
    this.author,
    this.romajiTitle,
    this.duration,
    this.releaseDate,
    this.endDate,
    this.releaseStatus,
    this.externalSource,
    this.localItem,
  });
}

class RatingBadge {
  final String source;
  final double? score;
  final int? votes;

  /// True when the source was actually asked and answered. The backend
  /// persists score 0 for "queried, this source has no rating", so the two
  /// states must not be collapsed: reading a known-absent rating as "missing"
  /// made every card open re-request the same external APIs.
  final bool queried;

  const RatingBadge({
    required this.source,
    required this.score,
    this.votes,
    this.queried = false,
  });
}

class RelationGroup {
  final String id;
  final String title;
  final List<RelatedEntry> items;

  const RelationGroup({
    required this.id,
    required this.title,
    required this.items,
  });
}

class TimelineEntry {
  final String id;
  final String title;
  final String? coverUrl;
  final int? year;
  final String formatDisplay;
  final String relationType;
  final bool isCurrent;
  final MediaItem? localItem;
  final RelatedEntry? rawItem;

  const TimelineEntry({
    required this.id,
    required this.title,
    required this.coverUrl,
    required this.year,
    required this.formatDisplay,
    required this.relationType,
    required this.isCurrent,
    this.localItem,
    this.rawItem,
  });
}

/// TS-union `SubTab` — закрытый набор строк → enum c wire (конвенция enums.dart).
enum SubTab {
  overview('overview'),
  episodes('episodes'),
  gallery('gallery'),
  related('related'),
  recommendations('recommendations');

  final String wire;

  const SubTab(this.wire);

  static SubTab fromWire(String wire) => values
      .firstWhere((v) => v.wire == wire, orElse: () => throw ArgumentError.value(wire, 'wire'));
}

/// TS-union `RelatedViewMode` — закрытый набор строк → enum c wire.
enum RelatedViewMode {
  grouped('grouped'),
  timeline('timeline'),
  grid('grid');

  final String wire;

  const RelatedViewMode(this.wire);

  static RelatedViewMode fromWire(String wire) => values.firstWhere(
      (v) => v.wire == wire,
      orElse: () => throw ArgumentError.value(wire, 'wire'));
}
