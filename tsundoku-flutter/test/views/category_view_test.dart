import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tsundoku_flutter/shared/api/api.dart';
import 'package:tsundoku_flutter/shared/api/jobs_client.dart';
import 'package:tsundoku_flutter/shared/types/models.dart';
import 'package:tsundoku_flutter/views/category_view.dart';

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

/// Перенос vitest-кейса `CategoryView.test.ts`: смена категории рендерит
/// элементы новой категории (game → manga, фильтр type в запросе).
void main() {
  late ProviderContainer container;
  late StubAdapter adapter;

  List<MediaItem> gameItems() => List.generate(
      18,
      (i) => MediaItem.fromJson({
            'id': 'game-$i',
            'title': 'Game $i',
            'type': 'game',
            'status': 0,
            'createdAt': '2026-01-01T00:00:00Z',
          }));

  List<MediaItem> mangaItems() => List.generate(
      18,
      (i) => MediaItem.fromJson({
            'id': 'manga-$i',
            'title': 'Manga $i',
            'type': 'manga',
            'status': 0,
            'createdAt': '2026-01-01T00:00:00Z',
          }));

  Future<void> pumpView(WidgetTester tester, String category) async {
    tester.view.physicalSize = const Size(1440, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        home: Scaffold(
          body: CustomScrollView(
            slivers: [
              // App монтирует с {#key activeCategory} → ValueKey форсирует
              // настоящий ремоунт при смене категории.
              CategoryView(
                key: ValueKey(category),
                category: category,
                refreshKey: 0,
                onOpen: (_) {},
                onMediaChanged: () {},
              ),
            ],
          ),
        ),
      ),
    ));
    // Загрузка списков (dio + sequence + debounce).
    await tester.pumpAndSettle(const Duration(milliseconds: 600));
  }

  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    adapter = StubAdapter((options) {
      // type-фильтр в query: game → games, manga → mangas.
      final type = options.queryParameters['type'];
      if (options.path.contains('/api/media')) {
        final items = type == 'manga'
            ? mangaItems().map((m) => m.toJson()).toList()
            : gameItems().map((m) => m.toJson()).toList();
        // getMediaWithCount читает голый массив + x-total-count header.
        return ResponseBody.fromString(jsonEncode(items), 200, headers: {
          Headers.contentTypeHeader: ['application/json'],
          'x-total-count': ['${items.length}'],
        });
      }
      // navigation-categories: пустой конфиг.
      return jsonBody([]);
    });
    final dio = Dio()..options.baseUrl = 'http://127.0.0.1:5150';
    dio.httpClientAdapter = adapter;
    final api = TsundokuApi(dio);
    container = ProviderContainer(overrides: [
      apiClientProvider.overrideWithValue(api),
    ]);
    addTearDown(container.dispose);
  });

  testWidgets('рендерит элементы новой категории после переключения',
      (tester) async {
    await pumpView(tester, 'game');
    expect(find.text('Game 0'), findsOneWidget);
    // Нативная слайвер-виртуализация: хвост прокручивается в окно.
    await tester.scrollUntilVisible(
      find.text('Game 17'),
      500,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('Game 17'), findsOneWidget);
    expect(find.text('Manga 0'), findsNothing);

    // App ремоунтит CategoryView при каждом переключении категории —
    // монтируем новый инстанс для «manga».
    await pumpView(tester, 'manga');
    expect(find.text('Manga 0'), findsOneWidget);
    await tester.scrollUntilVisible(
      find.text('Manga 17'),
      500,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('Manga 17'), findsOneWidget);
    expect(find.text('Game 0'), findsNothing);
    // Флаш dio/sequence-таймеров (invariant pending timers).
    await tester.pump(const Duration(seconds: 1));
  });

  testWidgets('фильтр type попадает в запрос (game → tvshow-исключение нет)',
      (tester) async {
    await pumpView(tester, 'game');
    // Запрос с type=Game (первая категория game).
    expect(
      adapter.seen
          .any((o) => o.path.contains('/api/media') && o.queryParameters['type'] == 'game'),
      isTrue,
      reason: 'categoryFilters(game) → type=Game в query',
    );
  });

  testWidgets('CategoryView обновляет карточку в середине списка при завершении задачи в jobsClient',
      (tester) async {
    var enriched = false;
    adapter = StubAdapter((options) {
      if (options.path.contains('/api/media')) {
        final items = [
          {
            'id': 'a1', 'title': 'Alpha', 'type': 'tvshow', 'isAnime': true, 'status': 1,
            'createdAt': '2026-01-01T00:00:00Z', 'updatedAt': '2026-01-01T00:00:00Z',
          },
          {
            'id': 'a2', 'title': 'Middle Syncing', 'type': 'tvshow', 'isAnime': true, 'status': 1,
            'syncStatus': enriched ? 0 : 1,
            'createdAt': '2026-01-01T00:00:00Z',
            'updatedAt': enriched ? '2026-01-01T00:05:00Z' : '2026-01-01T00:00:00Z',
          },
          {
            'id': 'a3', 'title': 'Omega', 'type': 'tvshow', 'isAnime': true, 'status': 1,
            'createdAt': '2026-01-01T00:00:00Z', 'updatedAt': '2026-01-01T00:00:00Z',
          },
        ];
        return ResponseBody.fromString(jsonEncode(items), 200, headers: {
          Headers.contentTypeHeader: ['application/json'],
          'x-total-count': ['3'],
        });
      }
      return jsonBody([]);
    });
    final dio = Dio()..options.baseUrl = 'http://127.0.0.1:5150';
    dio.httpClientAdapter = adapter;
    final api = TsundokuApi(dio);
    container = ProviderContainer(overrides: [
      apiClientProvider.overrideWithValue(api),
    ]);
    addTearDown(container.dispose);

    final jobs = container.read(jobsClientProvider.notifier);
    jobs.attachApi(api);
    jobs.applyJson(jsonEncode({
      'jobId': 'job-cat-1',
      'mediaId': 'a2',
      'title': 'Middle Syncing',
      'progressPercent': 40,
      'currentStep': 'Обогащение',
      'status': 'Running',
      'startedAt': '2026-01-01T00:00:00Z',
    }));

    categoryCache.invalidate('anime');
    await tester.pumpWidget(UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        home: Scaffold(
          body: CustomScrollView(
            slivers: [
              CategoryView(
                key: const ValueKey('anime'),
                category: 'anime',
                refreshKey: 0,
                onOpen: (_) {},
                onMediaChanged: () {},
              ),
            ],
          ),
        ),
      ),
    ));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));
    expect(find.text('Middle Syncing'), findsOneWidget);
    expect(find.text('Синхронизация'), findsOneWidget);

    enriched = true;
    jobs.applyJson(jsonEncode({
      'jobId': 'job-cat-1',
      'mediaId': 'a2',
      'title': 'Middle Syncing',
      'progressPercent': 100,
      'currentStep': 'Готово',
      'status': 'Completed',
      'startedAt': '2026-01-01T00:00:00Z',
    }));

    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    await tester.pumpAndSettle(const Duration(seconds: 5));

    expect(find.text('Middle Syncing'), findsOneWidget);
    expect(find.text('Синхронизация'), findsNothing);
  });
}
