import 'package:flutter_test/flutter_test.dart';
import 'package:tsundoku_flutter/entities/media/model/stale_triage.dart';
import 'package:tsundoku_flutter/shared/types/models.dart';

MediaItem createItem({
  required int status,
  String? lastActivityAt,
  String? startedAt,
  String? createdAt,
}) {
  return MediaItem.fromJson({
    'id': 'test-item-1',
    'type': 'game',
    'title': 'Test Item',
    'status': status,
    'score': null,
    'startedAt': startedAt,
    'finishedAt': null,
    'lastActivityAt': lastActivityAt,
    'coverUrl': null,
    'createdAt': createdAt ?? '2025-01-01T00:00:00Z',
    'franchiseId': null,
    'franchiseOrder': null,
    'platform': 'PC',
    'hoursPlayed': null,
  });
}

const msPerDay = 24 * 60 * 60 * 1000;

/// Прямой перенос vitest-кейсов `staleTriage.test.ts`.
void main() {
  test('getDaysInactive для дат и fallbacks', () {
    final date30 =
        DateTime.now().subtract(const Duration(milliseconds: 30 * msPerDay)).toIso8601String();
    final date200 =
        DateTime.now().subtract(const Duration(milliseconds: 200 * msPerDay)).toIso8601String();

    expect(getDaysInactive(lastActivityAt: date30), 30);
    expect(getDaysInactive(lastActivityAt: date200), 200);

    // Fallbacks
    expect(getDaysInactive(startedAt: date200), 200);
    expect(getDaysInactive(createdAt: date200), 200);
    expect(getDaysInactive(), 0);
  });

  test('isStaleInProgress: InProgress с порогом', () {
    final date50 =
        DateTime.now().subtract(const Duration(milliseconds: 50 * msPerDay)).toIso8601String();
    final date200 =
        DateTime.now().subtract(const Duration(milliseconds: 200 * msPerDay)).toIso8601String();

    final staleInProgress = createItem(status: 1, lastActivityAt: date200);
    final freshInProgress = createItem(status: 1, lastActivityAt: date50);

    expect(isStaleInProgress(staleInProgress, thresholdDays: 180), isTrue);
    expect(isStaleInProgress(freshInProgress, thresholdDays: 180), isFalse);
  });

  test('isStaleInProgress: false для не-InProgress статусов', () {
    final date200 =
        DateTime.now().subtract(const Duration(milliseconds: 200 * msPerDay)).toIso8601String();

    expect(isStaleInProgress(createItem(status: 0, lastActivityAt: date200)),
        isFalse);
    expect(isStaleInProgress(createItem(status: 2, lastActivityAt: date200)),
        isFalse);
    expect(isStaleInProgress(createItem(status: 3, lastActivityAt: date200)),
        isFalse);
    expect(isStaleInProgress(createItem(status: 4, lastActivityAt: date200)),
        isFalse);
  });

  test('кастомные пороги (90/365)', () {
    final date200 =
        DateTime.now().subtract(const Duration(milliseconds: 200 * msPerDay)).toIso8601String();
    final staleInProgress = createItem(status: 1, lastActivityAt: date200);

    expect(isStaleInProgress(staleInProgress, thresholdDays: 90), isTrue);
    expect(isStaleInProgress(staleInProgress, thresholdDays: 365), isFalse);
  });
}
