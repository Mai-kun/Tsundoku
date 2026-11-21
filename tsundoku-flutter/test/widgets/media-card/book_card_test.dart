import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/gestures.dart' show PointerDeviceKind;
import 'package:flutter_test/flutter_test.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:material_ui/material_ui.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tsundoku_flutter/shared/api/api.dart';
import 'package:tsundoku_flutter/shared/types/models.dart';
import 'package:tsundoku_flutter/widgets/media-card/book_card.dart';
import 'package:tsundoku_flutter/widgets/media-card/card_types.dart';

class StubAdapter implements HttpClientAdapter {
  final ResponseBody Function(RequestOptions options) handler;
  final List<RequestOptions> seen = <RequestOptions>[];
  StubAdapter(this.handler);

  @override
  Future<ResponseBody> fetch(
      RequestOptions options,
      Stream<Uint8List>? requestStream,
      Future<void>? cancelFuture) async {
    seen.add(options);
    return handler(options);
  }

  @override
  void close({bool force = false}) {}
}

ResponseBody jsonBody(Object? json, [int status = 200]) =>
    ResponseBody.fromString(jsonEncode(json), status, headers: {
      Headers.contentTypeHeader: ['application/json'],
    });

/// Widget-тесты `BookCard.svelte`: подзаголовок (автор/формат/тип), полный
/// цикл шага прогресса — hover → «+» → оптимистичный текст → PUT после
/// дебаунса (3s).
void main() {
  late ProviderContainer container;
  late StubAdapter adapter;

  Future<void> pumpBook(WidgetTester tester, MediaItem item) async {
    await tester.pumpWidget(UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        home: Center(
          child: SizedBox(
            width: 300,
            height: 450,
            child: BookCard(props: MediaCardProps(
              item: item,
              // Колбеки родителя (grid) — без них степпер no-op (1-в-1).
              onProgress: (id, value) =>
                  container.read(apiClientProvider).setProgress(id, value),
              onProgressCommitted: () {},
              onStatusChange: (item, status) {},
            )),
          ),
        ),
      ),
    ));
    await tester.pump();
  }

  MediaItem item(Map<String, Object?> extra) => MediaItem.fromJson({
        'id': 'm1',
        'type': 'book',
        'title': 'Норагами',
        'status': 2,
        'createdAt': '2024-01-01T00:00:00Z',
        ...extra,
      });

  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    adapter = StubAdapter((options) => jsonBody(<String, Object?>{}));
    final dio = Dio()..options.baseUrl = 'http://127.0.0.1:5150';
    dio.httpClientAdapter = adapter;
    final api = TsundokuApi(dio);
    container = ProviderContainer(overrides: [
      apiClientProvider.overrideWithValue(api),
    ]);
    addTearDown(container.dispose);
  });

  testWidgets('подзаголовок: автор приоритетен над форматом', (tester) async {
    await pumpBook(tester, item({'author': 'Adachitoka'}));
    expect(find.text('Adachitoka'), findsOneWidget);
  });

  testWidgets('ранобэ без автора → «Ранобэ»; обычная книга → «Книга»',
      (tester) async {
    await pumpBook(
        tester, item({'format': 'light_novel', 'currentPage': 1}));
    expect(find.text('Ранобэ'), findsOneWidget);
    await pumpBook(tester, item({}));
    expect(find.text('Книга'), findsOneWidget);
  });

  testWidgets('hover → «+» → оптимистичный шаг «4 / 12 гл.» → PUT после 3s',
      (tester) async {
    await pumpBook(tester, item({
      'format': 'light_novel',
      'currentChapter': 3,
      'totalChapters': 12,
    }));

    final center = tester.getCenter(find.byType(BookCard));
    final gesture = await tester.createGesture(
        kind: PointerDeviceKind.mouse, pointer: 7);
    await gesture.addPointer(location: center);
    addTearDown(gesture.removePointer);
    await gesture.moveTo(center);
    await tester.pumpAndSettle();

    // До шага: «3 / 12 гл.» (card.chapters fn).
    expect(find.text('3 / 12 гл.'), findsOneWidget);

    await tester.tap(find.byIcon(LucideIcons.plus));
    await tester.pump();

    // Оптимистично: мгновенный пересчёт текста.
    expect(find.text('4 / 12 гл.'), findsOneWidget);

    // Дебаунс 3s → PUT /api/media/m1/progress {currentProgress: 4}.
    await tester.pump(const Duration(seconds: 3, milliseconds: 200));
    await tester.pumpAndSettle();

    final progressCalls = adapter.seen
        .where((o) => o.path.contains('/api/media/m1/progress'))
        .toList();
    expect(progressCalls, hasLength(1));
    expect(progressCalls.first.method, 'PUT');
  });

  testWidgets('обычная книга: текст в страницах', (tester) async {
    await pumpBook(tester, item({'currentPage': 100, 'totalPages': 300}));
    final center = tester.getCenter(find.byType(BookCard));
    final gesture = await tester.createGesture(
        kind: PointerDeviceKind.mouse, pointer: 7);
    await gesture.addPointer(location: center);
    addTearDown(gesture.removePointer);
    await gesture.moveTo(center);
    await tester.pumpAndSettle();
    expect(find.text('100 / 300 стр.'), findsOneWidget);
  });
}
