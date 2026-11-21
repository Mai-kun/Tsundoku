/// 1:1 port of `mediatracker-ui/src/entities/media/model/staleTriage.ts`.
library;

import '../../../shared/types/enums.dart';
import '../../../shared/types/models.dart';

/// `type StaleThresholdDays = 90 | 180 | 365` — открытый int (типизированных
/// ограничений в runtime нет).
int getDaysInactive({
  String? lastActivityAt,
  String? startedAt,
  String? createdAt,
}) {
  final rawDate = lastActivityAt ?? startedAt ?? createdAt;
  if (rawDate == null || rawDate.isEmpty) return 0;
  final diffMs =
      DateTime.now().millisecondsSinceEpoch - DateTime.parse(rawDate).millisecondsSinceEpoch;
  final days = diffMs ~/ (1000 * 60 * 60 * 24);
  return days < 0 ? 0 : days;
}

bool isStaleInProgress(MediaItem item, {int thresholdDays = 180}) {
  if (item.status != MediaStatus.inProgress) return false; // in-progress
  return getDaysInactive(
        lastActivityAt: item.lastActivityAt,
        startedAt: item.startedAt,
        createdAt: item.createdAt,
      ) >=
      thresholdDays;
}
