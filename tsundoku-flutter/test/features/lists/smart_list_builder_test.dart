import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:tsundoku_flutter/features/lists/smart_list_builder.dart';
import 'package:tsundoku_flutter/shared/theme/tsundoku_theme.dart';
import 'package:tsundoku_flutter/shared/types/dtos.dart';
import 'package:tsundoku_flutter/shared/types/models.dart';

List<MediaItem> _sampleMedia() {
  return [
    MediaItem.fromJson(<String, dynamic>{
      'id': 'm1',
      'title': 'Elden Ring',
      'type': 'game',
      'status': 2, // completed
      'score': 10,
      'createdAt': '2024-01-01T00:00:00Z',
    }),
    MediaItem.fromJson(<String, dynamic>{
      'id': 'm2',
      'title': 'Cyberpunk 2077',
      'type': 'game',
      'status': 1, // in progress
      'score': 8,
      'createdAt': '2024-02-01T00:00:00Z',
    }),
    MediaItem.fromJson(<String, dynamic>{
      'id': 'm3',
      'title': 'Spirited Away',
      'type': 'movie',
      'status': 2,
      'score': 9,
      'isAnime': true,
      'durationMinutes': 125,
      'createdAt': '2024-03-01T00:00:00Z',
    }),
    MediaItem.fromJson(<String, dynamic>{
      'id': 'm4',
      'title': 'Berserk',
      'type': 'manga',
      'status': 0, // planned
      'score': 10,
      'totalChapters': 364,
      'author': 'Kentaro Miura',
      'createdAt': '2024-04-01T00:00:00Z',
    }),
  ];
}

Widget _buildSubject({
  SmartListQuery query = const SmartListQuery(),
  ValueChanged<SmartListQuery>? onQueryChange,
  List<MediaItem>? allMedia,
  ValueChanged<List<MediaItem>>? onMatchesChange,
}) {
  return ProviderScope(
    child: MaterialApp(
      theme: buildTsundokuTheme(),
      home: Scaffold(
        body: SingleChildScrollView(
          child: Padding(
            padding: const EdgeInsets.all(16.0),
            child: SmartListBuilder(
              query: query,
              onQueryChange: onQueryChange ?? (_) {},
              allMedia: allMedia ?? _sampleMedia(),
              onMatchesChange: onMatchesChange,
            ),
          ),
        ),
      ),
    ),
  );
}

void main() {
  testWidgets('renders all 5 presets', (tester) async {
    await tester.pumpWidget(_buildSubject());
    await tester.pumpAndSettle();

    expect(find.textContaining('Шедевры'), findsOneWidget);
    expect(find.textContaining('на вечер'), findsOneWidget);
    expect(find.textContaining('Короткое аниме'), findsOneWidget);
    expect(find.textContaining('Высокий рейтинг'), findsOneWidget);
    expect(find.textContaining('Быстрые книги'), findsOneWidget);
  });

  testWidgets('clicking preset applies filter', (tester) async {
    SmartListQuery? applied;

    await tester.pumpWidget(_buildSubject(
      onQueryChange: (q) => applied = q,
    ));
    await tester.pumpAndSettle();

    await tester.tap(find.textContaining('Шедевры'));
    await tester.pumpAndSettle();

    expect(applied, isNotNull);
    expect(applied!.minScore, 9);
    expect(applied!.sortBy, 'score');
    expect(applied!.sortOrder, 'desc');
  });

  testWidgets('toggles category filter and reports query change',
      (tester) async {
    SmartListQuery? applied;

    await tester.pumpWidget(_buildSubject(
      onQueryChange: (q) => applied = q,
    ));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Игры'));
    await tester.pumpAndSettle();

    expect(applied?.categories, contains('game'));
  });

  testWidgets('evaluates matches locally and notifies onMatchesChange',
      (tester) async {
    List<MediaItem>? matched;

    await tester.pumpWidget(_buildSubject(
      query: const SmartListQuery(
        minScore: 9,
      ),
      onMatchesChange: (m) => matched = m,
    ));
    await tester.pumpAndSettle();

    expect(matched, isNotNull);
    // Should match Elden Ring (10), Spirited Away (9), Berserk (10)
    expect(matched!.length, 3);
    expect(matched!.any((m) => m.title == 'Elden Ring'), isTrue);
    expect(matched!.any((m) => m.title == 'Cyberpunk 2077'), isFalse);
  });

  testWidgets('evaluateLocally filters categories, author, and sorts',
      (tester) async {
    final media = _sampleMedia();

    // Filter manga by author
    final res = evaluateLocally(
      media,
      const SmartListQuery(
        categories: ['manga'],
        creatorContains: 'Miura',
      ),
    );

    expect(res.length, 1);
    expect(res.first.title, 'Berserk');
  });
}
