import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tsundoku_flutter/shared/api/api.dart';
import 'package:tsundoku_flutter/shared/types/models.dart';
import 'package:tsundoku_flutter/widgets/media-detail/external_detail_modal.dart';

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

/// Тесты полного цикла `ExternalDetailModal.svelte`: loading → загрузка
/// деталей (stub HTTP) → merge stripEmpty → рендер; ошибка → hit остаётся,
/// rose-текст; рейтинги (дедуп + fallback); перевод синопсиса.
void main() {
  late StubAdapter adapter;
  late ProviderContainer container;

  ExternalMedia hit(Map<String, Object?> extra) => ExternalMedia.fromJson({
        'externalId': 'ext-1',
        'externalSource': 'anilist',
        'title': 'Frieren',
        'type': 'anime',
        ...extra,
      });

  Future<void> pumpModal(
    WidgetTester tester, {
    ExternalMedia? item,
    String type = 'anime',
  }) async {
    final dio = Dio()..options.baseUrl = 'http://127.0.0.1:5150';
    dio.httpClientAdapter = adapter;
    container = ProviderContainer(overrides: [
      apiClientProvider.overrideWithValue(TsundokuApi(dio)),
    ]);
    addTearDown(container.dispose);
    await tester.pumpWidget(UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        home: ExternalDetailModal(
          item: item ?? hit({}),
          type: type,
          onClose: () {},
          actions: const Text('ACTIONS'),
        ),
      ),
    ));
    await tester.pump(); // postFrame → _loadDetails стартовал
  }

  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    adapter = StubAdapter((options) => jsonBody(<String, Object?>{}));
  });

  testWidgets('loading: спиннер + текст, actions скрыты до ответа',
      (tester) async {
    await pumpModal(tester);

    expect(find.text('Загрузка…'), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    expect(find.text('ACTIONS'), findsNothing); // {#if !(loading && !details)}

    await tester.pumpAndSettle();
  });

  testWidgets('полный цикл: детали смержены поверх hit (stripEmpty), '
      'рейтинги/эпизоды/статус отрисованы', (tester) async {
    adapter = StubAdapter((options) {
      if (options.path == '/api/external/details') {
        expect(options.queryParameters['type'], 'anime');
        expect(options.queryParameters['id'], 'ext-1');
        return jsonBody({
          'externalId': 'ext-1',
          'externalSource': 'anilist',
          'title': 'Frieren',
          'type': 'anime',
          'description': 'Полный синопсис от провайдера',
          'releaseStatus': 'FINISHED',
          'studio': 'Madhouse',
          'totalCount': 28,
          'genres': ['Fantasy', 'Adventure'],
          'ratings': [
            {'source': 'AniList', 'rating': 9.0, 'votes': 1250},
            {'source': 'anilist', 'rating': 8.0, 'votes': 5}, // дедуп по lowercase
            {'source': '  ', 'rating': 7.0}, // пустой источник — пропуск
          ],
          'episodes': [
            {'number': 1, 'title': 'The Journey\'s End'},
            {'number': 2, 'title': ''},
          ],
        });
      }
      return jsonBody(<String, Object?>{});
    });

    await pumpModal(tester, item: hit({'description': ''}));
    await tester.pumpAndSettle();

    // Merge: description '' из hit перекрыт непустым от деталей.
    expect(find.text('Полный синопсис от провайдера'), findsOneWidget);
    // Статус: FINISHED → detail.releaseStatuses.finished (ru).
    expect(find.text('Завершён'), findsOneWidget);
    // Студия: spec-строка + тег (1-в-1 с Svelte — studio и в тегах, и в спеках).
    expect(find.text('Madhouse'), findsNWidgets(2));
    // Рейтинги: дедуп — один ANILIST-бейдж 9.0.
    expect(find.text('ANILIST'), findsOneWidget);
    expect(find.text('9.0'), findsOneWidget);
    expect(find.text('8.0'), findsNothing);
    // Эпизоды: заголовок со счётчиком + эпизод с фолбэком пустого тайтла.
    expect(find.text('СПИСОК ЭПИЗОДОВ (2)'), findsOneWidget); // uppercase из Svelte
    expect(find.text('The Journey\'s End'), findsOneWidget);
    expect(find.text('Серия 2'), findsOneWidget); // detail.episodeTitle(2)
    // Actions появились после загрузки.
    expect(find.text('ACTIONS'), findsOneWidget);
  });

  testWidgets('fallback: один score без массива рейтингов → бейдж источника',
      (tester) async {
    adapter = StubAdapter((options) {
      if (options.path == '/api/external/details') {
        return jsonBody({
          'externalId': 'ext-1',
          'externalSource': 'steam',
          'title': 'Hollow Knight',
          'rating': 8.7,
          'ratingVotes': 320,
          'type': 'game',
        });
      }
      return jsonBody(<String, Object?>{});
    });

    await pumpModal(tester, item: hit({'title': 'Hollow Knight'}), type: 'game');
    await tester.pumpAndSettle();

    expect(find.text('STEAM'), findsOneWidget);
    expect(find.text('8.7'), findsOneWidget);
  });

  testWidgets('ошибка загрузки: hit остаётся, rose-текст, actions видны',
      (tester) async {
    adapter = StubAdapter((options) {
      if (options.path == '/api/external/details') {
        return ResponseBody.fromString(
            jsonEncode({'detail': 'provider down'}), 500,
            headers: {
              Headers.contentTypeHeader: ['application/json'],
            });
      }
      return jsonBody(<String, Object?>{});
    });

    await pumpModal(tester, item: hit({'description': 'Короткое описание'}));
    await tester.pumpAndSettle();

    // Hit отрисован несмотря на ошибку.
    expect(find.text('Frieren'), findsOneWidget);
    expect(find.text('Короткое описание'), findsOneWidget);
    // Ошибка: getExternalDetails глотает transport/ApiError → null →
    // StateError → errors.unexpected (1-в-1 с Svelte loadExternalDetails).
    expect(find.text('Произошла непредвиденная ошибка.'), findsOneWidget);
    // Actions не блокированы ошибкой.
    expect(find.text('ACTIONS'), findsOneWidget);
  });

  testWidgets('перевод синопсиса: POST translate → текст заменён, кнопка '
      '«Оригинал», повторный тап возвращает исходник', (tester) async {
    adapter = StubAdapter((options) {
      if (options.path == '/api/external/details') {
        return jsonBody({
          'externalId': 'ext-1',
          'externalSource': 'anilist',
          'title': 'Frieren',
          'type': 'anime',
          'description': 'Original synopsis text',
        });
      }
      if (options.path == '/api/external/translate') {
        expect(options.method, 'POST');
        return jsonBody({'translatedText': 'Переведённый текст'});
      }
      return jsonBody(<String, Object?>{});
    });

    await pumpModal(tester);
    await tester.pumpAndSettle();

    expect(find.text('Original synopsis text'), findsOneWidget);
    await tester.ensureVisible(find.text('Перевести'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Перевести'));
    await tester.pumpAndSettle();

    expect(find.text('Переведённый текст'), findsOneWidget);
    expect(find.text('Original synopsis text'), findsNothing);
    expect(find.text('Оригинал'), findsOneWidget); // showOriginal

    await tester.ensureVisible(find.text('Оригинал'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Оригинал'));
    await tester.pumpAndSettle();

    expect(find.text('Original synopsis text'), findsOneWidget);
    expect(find.text('Перевести'), findsOneWidget);
  });

  testWidgets('короткий синопсис: кнопки разворота нет (>280 символов — есть)',
      (tester) async {
    adapter = StubAdapter((options) {
      if (options.path == '/api/external/details') {
        return jsonBody({
          'externalId': 'ext-1',
          'externalSource': 'anilist',
          'title': 'Frieren',
          'type': 'anime',
          'description': 'Короткое описание.',
        });
      }
      return jsonBody(<String, Object?>{});
    });

    await pumpModal(tester);
    await tester.pumpAndSettle();

    expect(find.textContaining('Читать далее'), findsNothing);

    // Длинный синопсис → expandable (новый externalId: тот же hit-key
    // переиспользовал бы State с кэшем первой загрузки).
    adapter = StubAdapter((options) {
      if (options.path == '/api/external/details') {
        return jsonBody({
          'externalId': 'ext-2',
          'externalSource': 'anilist',
          'title': 'Frieren',
          'type': 'anime',
          'description': 'Длинное описание синопсиса. ' * 30,
        });
      }
      return jsonBody(<String, Object?>{});
    });
    await pumpModal(
      tester,
      item: hit({'externalId': 'ext-2'}),
    );
    await tester.pumpAndSettle();

    expect(find.textContaining('Читать далее'), findsOneWidget);
  });
}
