import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:tsundoku_flutter/shared/api/api.dart';
import 'package:tsundoku_flutter/shared/types/index.dart';
import 'package:tsundoku_flutter/widgets/media-detail/detail_types.dart';
import 'package:tsundoku_flutter/widgets/media-detail/tabs/related_tab.dart';
import 'package:tsundoku_flutter/widgets/media-detail/tabs/recommendations_tab.dart';

/// Тесты `RecommendationsTab.svelte` + `RelatedTab.svelte`.
class HttpClientAdapterStub implements HttpClientAdapter {
  @override
  Future<ResponseBody> fetch(
      RequestOptions options,
      Stream<Uint8List>? requestStream,
      Future<void>? cancelFuture) async {
    return ResponseBody.fromString(jsonEncode([]), 200, headers: {
      Headers.contentTypeHeader: ['application/json'],
    });
  }

  @override
  void close({bool force = false}) {}
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
  });

  testWidgets('recommendations: пусто → «Рекомендации отсутствуют»',
      (tester) async {
    tester.view.physicalSize = const Size(1440, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(ProviderScope(
      child: const MaterialApp(home: Material(child: RecommendationsTab(items: []))),
    ));
    await tester.pump();
    expect(find.textContaining('Рекомендации отсутствуют'), findsOneWidget);
  });

  testWidgets('recommendations: карточки с рейтингом и источником',
      (tester) async {
    tester.view.physicalSize = const Size(1440, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(ProviderScope(
      child: MaterialApp(
        home: Material(
          child: SingleChildScrollView(
            child: RecommendationsTab(
              items: [
                const RecommendationItem(
                    id: 'r1',
                    title: 'Frieren',
                    coverUrl: null,
                    rating: 8.65,
                    source: 'anilist'),
                const RecommendationItem(
                    id: 'r2',
                    title: 'Mushoku Tensei',
                    coverUrl: null,
                    rating: null,
                    source: 'kitsu'),
              ],
            ),
          ),
        ),
      ),
    ));
    await tester.pump();
    await tester.pump();

    expect(find.text('Frieren'), findsOneWidget);
    expect(find.text('Mushoku Tensei'), findsOneWidget);
    expect(find.text('★ 8.7'), findsOneWidget); // toFixed(1)
    expect(find.text('anilist'), findsOneWidget);
    // Без рейтинга звезда не рендерится.
    expect(find.text('★ 8.7'), findsOneWidget);
    expect(find.textContaining('★ 0'), findsNothing);
  });

  testWidgets('related: обёртка передаёт пропсы в RelatedPanel',
      (tester) async {
    tester.view.physicalSize = const Size(1440, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    // Stub-API: авто-загрузка панели дергает getSources (таймеры dio).
    final dio = Dio()..options.baseUrl = 'http://127.0.0.1:5150';
    dio.httpClientAdapter = HttpClientAdapterStub();
    final container = ProviderContainer(
      overrides: [apiClientProvider.overrideWithValue(TsundokuApi(dio))],
    );
    addTearDown(container.dispose);
    await tester.pumpWidget(UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        home: Material(
          child: RelatedTab(
            media: MediaItem.fromJson({
              'id': 'm1',
              'type': 'manga',
              'title': 'Frieren',
              'status': 1,
              'createdAt': '2024-01-01T00:00:00Z',
            }),
            related: [
              RelatedEntry(
                id: '103',
                title: 'Prequel Story',
                type: 'anime',
              ),
            ],
            loading: false,
            viewMode: RelatedViewMode.grouped,
            onRetry: () {},
            onSelectViewMode: (_) {},
            onOpen: (_) {},
            onLoadFrom: (_, {force = false}) {},
          ),
        ),
      ),
    ));
    await tester.pump();
    await tester.pump();
    // 0ms-таймер dio/секций — флаш перед teardown.
    await tester.pump(const Duration(milliseconds: 10));

    // RelatedPanel-контент (детали — в тестах панели); здесь — не падает.
    expect(tester.takeException(), isNull);
  });
}
