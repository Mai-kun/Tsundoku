import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tsundoku_flutter/shared/api/api.dart';
import 'package:tsundoku_flutter/shared/types/index.dart';
import 'package:tsundoku_flutter/widgets/media-detail/relink_source_modal.dart';

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

/// Тесты `RelinkSourceModal.svelte`: провайдеры по mediaTypes (fallback на
/// все при пустом матче), prefill оригинальным заголовком, debounce-поиск
/// (source-параметр), link → relinkMedia payload → onRelinked, ошибка link.
void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
  });

  List<Map<String, Object?>> sourcesJson() => [
        {
          'id': 'tmdb',
          'name': 'TMDb',
          'description': '',
          'mediaTypes': ['movie', 'tvshow'],
          'requiresApiKey': false,
          'optionalApiKey': false,
          'isConfigured': true,
          'hasKey': true,
          'maskedKey': 'ab…',
          'isEnabled': true,
          'isScraper': false,
          'isProxied': null,
        },
        {
          'id': 'mangadex',
          'name': 'MangaDex',
          'description': '',
          'mediaTypes': ['manga'],
          'requiresApiKey': false,
          'optionalApiKey': false,
          'isConfigured': true,
          'hasKey': false,
          'maskedKey': null,
          'isEnabled': true,
          'isScraper': false,
          'isProxied': null,
        },
        {
          'id': 'disabled-one',
          'name': 'Disabled',
          'description': '',
          'mediaTypes': ['manga'],
          'requiresApiKey': false,
          'optionalApiKey': false,
          'isConfigured': true,
          'hasKey': false,
          'maskedKey': null,
          'isEnabled': false,
          'isScraper': false,
          'isProxied': null,
        },
      ];

  List<Map<String, Object?>> resultsJson() => [
        {
          'externalId': 'ext-1',
          'externalSource': 'mangadex',
          'type': 'manga',
          'title': 'Frieren (mangadex)',
          'coverUrl': 'https://cdn.example.com/frieren.jpg',
          'releaseYear': 2020,
        },
        {
          'externalId': 'ext-2',
          'externalSource': 'mangadex',
          'type': 'manga',
          'title': 'Frieren: Second',
        },
      ];

  Map<String, Object?> relinkedJson() => {
        'id': 'm1',
        'type': 'manga',
        'title': 'Frieren',
        'status': 1,
        'createdAt': '2024-01-01T00:00:00Z',
        'coverUrl': '/media-assets/m1/cover/thumb.webp',
      };

  Future<(ProviderContainer, StubAdapter)> pumpModal(
    WidgetTester tester, {
    String type = 'manga',
    String title = 'Frieren',
    String? originalTitle,
    String? currentSource,
    ResponseBody Function(RequestOptions options)? handler,
    void Function(MediaDetail payload)? onRelinked,
  }) async {
    tester.view.physicalSize = const Size(1440, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    final dio = Dio()..options.baseUrl = 'http://127.0.0.1:5150';
    final adapter = StubAdapter(handler ??
        (options) {
          if (options.uri.path.contains('/api/settings/sources')) {
            return jsonBody(sourcesJson());
          }
          if (options.uri.path.contains('/api/external/search')) {
            return jsonBody(resultsJson());
          }
          if (options.uri.path.contains('/relink')) {
            return jsonBody(relinkedJson());
          }
          return jsonBody(<String, Object?>{});
        });
    dio.httpClientAdapter = adapter;
    final container = ProviderContainer(
      overrides: [apiClientProvider.overrideWithValue(TsundokuApi(dio))],
    );
    addTearDown(container.dispose);
    await tester.pumpWidget(UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        home: Material(
          child: RelinkSourceModal(
            isOpen: true,
            mediaId: 'm1',
            title: title,
            originalTitle: originalTitle,
            type: type,
            currentSource: currentSource,
            onClose: () {},
            onRelinked: onRelinked ?? (_) {},
          ),
        ),
      ),
    ));
    await tester.pump();
    for (var i = 0; i < 6; i++) {
      await tester.pump(const Duration(milliseconds: 120));
    }
    return (container, adapter);
  }

  testWidgets('providers по mediaTypes: movie → только TMDb, disabled отфильтрован',
      (tester) async {
    await pumpModal(tester, type: 'movie');

    expect(find.text('TMDb'), findsOneWidget);
    expect(find.text('MangaDex'), findsNothing);
  });

  testWidgets('пустой матч mediaTypes → fallback на все включённые',
      (tester) async {
    await pumpModal(tester, type: 'book');

    // Триггер = выбранный (первый опций — TMDb).
    expect(find.text('TMDb'), findsOneWidget);
    // Опции списка видны в открытом поповере.
    await tester.tap(find.text('TMDb'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 250));
    expect(find.text('MangaDex'), findsOneWidget);
  });

  testWidgets('prefill оригинальным заголовком → авто-поиск с source-параметром',
      (tester) async {
    final (_, adapter) = await pumpModal(
      tester,
      type: 'manga',
      title: 'Фрирен (перевод)',
      originalTitle: 'Sousou no Frieren',
      currentSource: 'mangadex',
    );

    // Поле заполнено оригиналом.
    expect(find.text('Sousou no Frieren'), findsOneWidget);
    final searches = adapter.seen
        .where((o) => o.uri.path.contains('/api/external/search'))
        .toList();
    expect(searches, isNotEmpty);
    expect(searches.last.uri.queryParameters['query'], 'Sousou no Frieren');
    expect(searches.last.uri.queryParameters['type'], 'manga');
    expect(searches.last.uri.queryParameters['source'], 'mangadex');
    // Результаты отрендерены.
    expect(find.text('Frieren (mangadex)'), findsOneWidget);
    expect(find.text('2020'), findsOneWidget);
  });

  testWidgets('link: POST relink payload {externalId, source, type, title} → onRelinked',
      (tester) async {
    final requests = <RequestOptions>[];
    MediaDetail? relinked;
    await pumpModal(
      tester,
      type: 'manga',
      originalTitle: 'Sousou no Frieren',
      handler: (options) {
        requests.add(options);
        if (options.uri.path.contains('/relink')) {
          return jsonBody(relinkedJson());
        }
        if (options.uri.path.contains('/api/settings/sources')) {
          return jsonBody(sourcesJson());
        }
        if (options.uri.path.contains('/api/external/search')) {
          return jsonBody(resultsJson());
        }
        return jsonBody(<String, Object?>{});
      },
      onRelinked: (payload) => relinked = payload,
    );

    await tester.tap(find.text('Привязать').first);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 150));

    final relink = requests
        .where((o) => o.uri.path.contains('/relink'))
        .toList();
    expect(relink, hasLength(1));
    expect(relink.single.method, 'POST');
    final body = relink.single.data as Map<String, Object?>;
    expect(body['externalId'], 'ext-1');
    expect(body['source'], 'mangadex');
    expect(body['type'], 'manga');
    expect(body['title'], 'Frieren (mangadex)');
    expect(relinked, isNotNull);
  });

  testWidgets('link ошибка → inline rose-строка, linking сброшен',
      (tester) async {
    await pumpModal(
      tester,
      type: 'manga',
      originalTitle: 'Sousou no Frieren',
      handler: (options) {
        if (options.uri.path.contains('/relink')) {
          return jsonBody(
              <String, Object?>{'detail': 'relink failed'}, 500);
        }
        if (options.uri.path.contains('/api/settings/sources')) {
          return jsonBody(sourcesJson());
        }
        if (options.uri.path.contains('/api/external/search')) {
          return jsonBody(resultsJson());
        }
        return jsonBody(<String, Object?>{});
      },
    );

    await tester.tap(find.text('Привязать').first);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 150));

    expect(find.textContaining('relink failed'), findsOneWidget);
    // Кнопки снова активны (linkingId сброшен).
    expect(find.text('Привязать'), findsWidgets);
  });
}
