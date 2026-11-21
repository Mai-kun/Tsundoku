/// 1:1 port of `mediatracker-ui/src/entities/media/model/chronicleTimeline.ts`.
library;

import 'package:flutter/foundation.dart';
import '../../../shared/types/enums.dart';
import '../../../shared/types/models.dart';

// shortcut: local copy of MEDIA_STATUS to avoid runtime alias resolution in
// node checks.
const int _statusCompleted = 2;
const int _statusInProgress = 1;

/// `"months" | "years"` (шкала не используется самой группировкой; оставлен
/// для совместимости вызовов).
typedef TimelineScale = String;

/// `"all" | "game" | "anime" | "manga" | "movie" | "tvshow" | "book"`.
typedef TimelineCategoryFilter = String;

@immutable
class ChronicleEntry {
  final MediaItem item;
  final DateTime date;
  final String dateIso;
  final int year;
  final int month; // 0..11
  final bool isCompleted;

  const ChronicleEntry({
    required this.item,
    required this.date,
    required this.dateIso,
    required this.year,
    required this.month,
    required this.isCompleted,
  });
}

@immutable
class ChronicleMonthGroup {
  final int month; // 0..11
  final List<ChronicleEntry> entries;
  final double? averageScore;

  const ChronicleMonthGroup({
    required this.month,
    required this.entries,
    required this.averageScore,
  });
}

@immutable
class ChronicleYearGroup {
  final int year;
  final List<ChronicleMonthGroup> months;
  final List<ChronicleEntry> entries;
  final int totalCount;
  final double? averageScore;
  final MediaItem? topRatedItem;

  const ChronicleYearGroup({
    required this.year,
    required this.months,
    required this.entries,
    required this.totalCount,
    required this.averageScore,
    required this.topRatedItem,
  });
}

@immutable
class ChronicleResult {
  final List<ChronicleYearGroup> years;
  final List<MediaItem> undatedCompleted;
  final int totalDatedCount;

  const ChronicleResult({
    required this.years,
    required this.undatedCompleted,
    required this.totalDatedCount,
  });
}

bool _matchesCategory(MediaItem item, String category) {
  if (category == 'all') return true;
  if (category == 'anime') {
    return (item.type == MediaType.tvshow || item.type == MediaType.movie) &&
        (item.isAnime ?? false);
  }
  if (category == 'tvshow') {
    return item.type == MediaType.tvshow && !(item.isAnime ?? false);
  }
  if (category == 'movie') {
    return item.type == MediaType.movie && !(item.isAnime ?? false);
  }
  return item.type == MediaType.fromWire(category);
}

double? _avgScore(List<ChronicleEntry> entries) {
  final scored = entries.where((e) => (e.item.score ?? 0) > 0).toList();
  if (scored.isEmpty) return null;
  final sum = scored.fold<int>(0, (acc, e) => acc + e.item.score!);
  return ((sum / scored.length) * 10).roundToDouble() / 10;
}

MediaItem? _topRated(List<ChronicleEntry> entries) {
  final scored = entries.where((e) => (e.item.score ?? 0) > 0).toList();
  if (scored.isEmpty) return null;
  return scored.reduce((best, e) =>
      e.item.score! > best.item.score! ? e : best).item;
}

ChronicleResult buildChronicle(
  List<MediaItem> items, {
  required String category,
  required bool includeInProgress,
}) {
  final undatedCompleted = <MediaItem>[];
  final dated = <ChronicleEntry>[];

  for (final item in items) {
    if (!_matchesCategory(item, category)) continue;

    final isCompleted = item.status.value == _statusCompleted;
    final isInProgress = item.status.value == _statusInProgress;

    if (isCompleted) {
      final rawDate = item.finishedAt ?? item.startedAt;
      if (rawDate == null) {
        undatedCompleted.add(item);
        continue;
      }
      final date = DateTime.parse(rawDate);
      dated.add(ChronicleEntry(
        item: item,
        date: date,
        dateIso: rawDate,
        year: date.year,
        month: date.month - 1,
        isCompleted: true,
      ));
    } else if (includeInProgress && isInProgress && item.startedAt != null) {
      final date = DateTime.parse(item.startedAt!);
      dated.add(ChronicleEntry(
        item: item,
        date: date,
        dateIso: item.startedAt!,
        year: date.year,
        month: date.month - 1,
        isCompleted: false,
      ));
    }
  }

  // Group by year then month.
  final byYear = <int, Map<int, List<ChronicleEntry>>>{};
  for (final entry in dated) {
    final yearMap = byYear.putIfAbsent(entry.year, () => <int, List<ChronicleEntry>>{});
    yearMap.putIfAbsent(entry.month, () => <ChronicleEntry>[]).add(entry);
  }

  // Sort entries within each month newest → oldest.
  List<ChronicleEntry> sortEntries(List<ChronicleEntry> arr) {
    final copy = [...arr];
    copy.sort((a, b) => b.date.compareTo(a.date));
    return copy;
  }

  final years = <ChronicleYearGroup>[];
  final sortedYears = byYear.keys.toList()..sort((a, b) => b - a);

  for (final year in sortedYears) {
    final yearMap = byYear[year]!;
    final sortedMonths = yearMap.keys.toList()..sort((a, b) => b - a);

    final monthGroups = <ChronicleMonthGroup>[];
    for (final month in sortedMonths) {
      final entries = sortEntries(yearMap[month]!);
      monthGroups.add(ChronicleMonthGroup(
        month: month,
        entries: entries,
        averageScore: _avgScore(entries),
      ));
    }

    final allEntries = [for (final m in monthGroups) ...m.entries];
    years.add(ChronicleYearGroup(
      year: year,
      months: monthGroups,
      entries: allEntries,
      totalCount: allEntries.length,
      averageScore: _avgScore(allEntries),
      topRatedItem: _topRated(allEntries),
    ));
  }

  return ChronicleResult(
    years: years,
    undatedCompleted: undatedCompleted,
    totalDatedCount: dated.length,
  );
}
