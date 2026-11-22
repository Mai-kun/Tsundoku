import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:tsundoku_flutter/features/drop-reason/drop_reason_prompt.dart';
import 'package:tsundoku_flutter/features/stale-triage/stale_backlog_modal.dart';
import 'package:tsundoku_flutter/shared/api/api.dart';
import 'package:tsundoku_flutter/shared/types/index.dart';

class _FakeTriageAdapter implements HttpClientAdapter {
  final List<RequestOptions> requests = [];

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    requests.add(options);

    return ResponseBody.fromString(
      jsonEncode({'success': true}),
      200,
      headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

MediaItem _makeStaleItem({
  required String id,
  required String title,
  required MediaType type,
  required int daysInactive,
  int? totalEpisodesCount,
  int? totalEpisodesWatched,
}) {
  final date = DateTime.now()
      .subtract(Duration(days: daysInactive))
      .toUtc()
      .toIso8601String();

  return MediaItem.fromJson({
    'id': id,
    'title': title,
    'type': type.wire,
    'status': 1, // inProgress
    'createdAt': date,
    'updatedAt': date,
    'lastActivityAt': date,
    'totalEpisodesCount': totalEpisodesCount,
    'totalEpisodesWatched': totalEpisodesWatched,
  });
}

Widget _buildSubject({
  bool isOpen = true,
  List<MediaItem>? items,
  VoidCallback? onClose,
  VoidCallback? onMediaChanged,
  _FakeTriageAdapter? adapter,
}) {
  final dio = Dio();
  dio.httpClientAdapter = adapter ?? _FakeTriageAdapter();
  final api = TsundokuApi(dio);

  return ProviderScope(
    overrides: [
      apiClientProvider.overrideWithValue(api),
    ],
    child: MaterialApp(
      home: Scaffold(
        body: StaleBacklogModal(
          isOpen: isOpen,
          onClose: onClose ?? () {},
          items: items,
          onMediaChanged: onMediaChanged,
        ),
      ),
    ),
  );
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  testWidgets('hides when isOpen is false', (tester) async {
    await tester.pumpWidget(_buildSubject(isOpen: false));
    await tester.pumpAndSettle();

    expect(find.text('Ревизия заброшенного бэклога'), findsNothing);
  });

  testWidgets('shows celebration state when no stale items exist',
      (tester) async {
    await tester.pumpWidget(_buildSubject(
      isOpen: true,
      items: [],
    ));
    await tester.pumpAndSettle();

    expect(find.text('Ревизия заброшенного бэклога'), findsOneWidget);
    expect(find.text('🎉 Отличная работа!'), findsOneWidget);
  });

  testWidgets('renders stale items with progress and days inactive',
      (tester) async {
    final item = _makeStaleItem(
      id: 'item-1',
      title: 'Steins;Gate',
      type: MediaType.tvshow,
      daysInactive: 200,
      totalEpisodesCount: 24,
      totalEpisodesWatched: 12,
    );

    await tester.pumpWidget(_buildSubject(
      isOpen: true,
      items: [item],
    ));
    await tester.pumpAndSettle();

    expect(find.text('Steins;Gate'), findsOneWidget);
    expect(find.textContaining('12 / 24'), findsOneWidget);
    expect(find.textContaining('200 дн.'), findsOneWidget);
    expect(find.text('В фокус'), findsOneWidget);
    expect(find.text('На паузу'), findsOneWidget);
    expect(find.text('Бросить'), findsOneWidget);
    expect(find.text('В планы'), findsOneWidget);
  });

  testWidgets('threshold buttons filter items and update count',
      (tester) async {
    final item1 = _makeStaleItem(
      id: 'item-1',
      title: 'Active item',
      type: MediaType.game,
      daysInactive: 100, // Stale only for 90d, not 180d
    );
    final item2 = _makeStaleItem(
      id: 'item-2',
      title: 'Very stale item',
      type: MediaType.game,
      daysInactive: 200, // Stale for 90d and 180d
    );

    await tester.pumpWidget(_buildSubject(
      isOpen: true,
      items: [item1, item2],
    ));
    await tester.pumpAndSettle();

    // Default threshold is 180d: only item2 is found
    expect(find.text('Найдено висяков: 1'), findsOneWidget);
    expect(find.text('Very stale item'), findsOneWidget);
    expect(find.text('Active item'), findsNothing);

    // Switch to 90d threshold
    await tester.tap(find.text('90 дней (3 мес)'));
    await tester.pumpAndSettle();

    expect(find.text('Найдено висяков: 2'), findsOneWidget);
    expect(find.text('Active item'), findsOneWidget);
    expect(find.text('Very stale item'), findsOneWidget);
  });

  testWidgets('clicking Focus updates media and removes from list',
      (tester) async {
    final adapter = _FakeTriageAdapter();
    final item = _makeStaleItem(
      id: 'item-1',
      title: 'Steins;Gate',
      type: MediaType.tvshow,
      daysInactive: 200,
    );

    await tester.pumpWidget(_buildSubject(
      isOpen: true,
      items: [item],
      adapter: adapter,
    ));
    await tester.pumpAndSettle();

    await tester.tap(find.text('В фокус'));
    await tester.pumpAndSettle();

    expect(find.text('Steins;Gate'), findsNothing);
    expect(adapter.requests.any((r) => r.path.contains('/api/media/item-1')),
        isTrue);
  });

  testWidgets('clicking Pause pauses media status', (tester) async {
    final adapter = _FakeTriageAdapter();
    final item = _makeStaleItem(
      id: 'item-1',
      title: 'Steins;Gate',
      type: MediaType.tvshow,
      daysInactive: 200,
    );

    await tester.pumpWidget(_buildSubject(
      isOpen: true,
      items: [item],
      adapter: adapter,
    ));
    await tester.pumpAndSettle();

    await tester.tap(find.text('На паузу'));
    await tester.pumpAndSettle();

    expect(find.text('Steins;Gate'), findsNothing);
    expect(
        adapter.requests.any((r) =>
            r.path.contains('/api/media/item-1/status') &&
            r.data['status'] == 3),
        isTrue);
  });

  testWidgets('clicking Drop drops media status and opens drop prompt',
      (tester) async {
    final adapter = _FakeTriageAdapter();
    final item = _makeStaleItem(
      id: 'item-1',
      title: 'Steins;Gate',
      type: MediaType.tvshow,
      daysInactive: 200,
    );

    final container = ProviderContainer(
      overrides: [
        apiClientProvider.overrideWithValue(TsundokuApi(Dio()..httpClientAdapter = adapter)),
      ],
    );

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          home: Scaffold(
            body: StaleBacklogModal(
              isOpen: true,
              onClose: () {},
              items: [item],
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Бросить'));
    await tester.pumpAndSettle();

    expect(find.text('Steins;Gate'), findsNothing);
    expect(container.read(dropPromptStateProvider)?.id, 'item-1');
  });
}
