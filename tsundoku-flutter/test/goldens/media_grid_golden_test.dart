import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:tsundoku_flutter/shared/theme/tsundoku_theme.dart';
import 'package:tsundoku_flutter/shared/types/models.dart';
import 'package:tsundoku_flutter/widgets/media-grid/media_grid.dart';

import 'golden_test_helper.dart';

/// Golden сетки MediaGrid (поведение окна удаления virtualGrid ⏭️ +
/// визуальный паритет с Svelte backstop desktop 1440×900).
void main() {
  MediaItem book(String id, {int progress = 0}) => MediaItem.fromJson({
        'id': id,
        'type': 'book',
        'title': 'Норагами $id',
        'status': 1,
        'score': 8,
        'currentPage': progress,
        'totalPages': 200,
        'coverUrl': null,
        'createdAt': '2024-01-01T00:00:00Z',
        'syncStatus': 0,
      });

  // 12 карточек (плоский режим < FLAT_LIMIT 15): timeHint-чипы, бейджи
  // статуса/оценки, градиентные заголовки.
  final grid = MediaGrid(
    items: List.generate(12, (i) => book('m$i', progress: 20 + i * 7)),
    timeBudget: 60,
  );

  tsundokuGoldenTest(
    'media_grid_books',
    ProviderScope(
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: buildTsundokuTheme(), // Inter + obsidian — 1-в-1 с Svelte
        home: Scaffold(
          body: Padding(
            padding: const EdgeInsets.all(32),
            child: MediaGridView(grid: grid),
          ),
        ),
      ),
    ),
  );
}
