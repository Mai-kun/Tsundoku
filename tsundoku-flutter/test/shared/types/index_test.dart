import 'package:flutter_test/flutter_test.dart';
import 'package:tsundoku_flutter/shared/types/index.dart';

/// Barrel-тест: все ключевые типы доступны через единый import (1-в-1 с
/// `export *` в index.ts), без отдельных импортов enums/models/dtos.
void main() {
  test('barrel экспортирует enums', () {
    expect(MediaStatus.fromValue(2), MediaStatus.completed);
    expect(JobStatus.tryFromWire('Running'), JobStatus.running);
    expect(MediaType.fromWire('book'), MediaType.book);
  });

  test('barrel экспортирует models', () {
    final m = MediaItem.fromJson({
      'id': 'm1', 'type': 'book', 'title': 'Тест', 'status': 1,
      'createdAt': '2026-11-21T00:00:00Z', 'author': 'Автор',
      'currentPage': 3, 'totalPages': 100,
    });
    expect(m.author, 'Автор');
    expect(m.type, MediaType.book);
    expect(MediaStats, isNotNull);
    expect(ExternalMedia, isNotNull);
  });

  test('barrel экспортирует dtos', () {
    const p = CreateListPayload(
      name: 'x', description: null, icon: null, color: null,
      smartQueryJson: null,
    );
    expect(p.toJson()['name'], 'x');
    expect(MediaFilters, isNotNull);
    expect(CalendarEventKind.autoRefresh.wire, 'auto_refresh');
  });

  test('полный цикл: MediaFilters → query по barrel-import', () {
    const f = MediaFilters(
      type: MediaType.manga,
      status: MediaStatus.onHold,
      sortBy: SortBy.score,
      sortOrder: SortOrder.desc,
    );
    expect(f.toQueryParameters(), {
      'type': 'manga', 'status': 3, 'sortBy': 'score', 'sortOrder': 'desc',
    });
  });
}
