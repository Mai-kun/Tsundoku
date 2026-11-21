import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:material_ui/material_ui.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tsundoku_flutter/shared/api/api.dart';
import 'package:tsundoku_flutter/widgets/media-detail/sections/linked_sources_section.dart';

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

/// Тесты `LinkedSourcesSection.svelte`: загрузка, добавление (ссылка →
/// источник по сайту), сделать основным/удалить, чипы полей.
void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
  });

  Future<ProviderContainer> pumpSources(
    WidgetTester tester, {
    required Map<String, ResponseBody Function(RequestOptions)> handlers,
  }) async {
    tester.view.physicalSize = const Size(1440, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    final dio = Dio()..options.baseUrl = 'http://127.0.0.1:5150';
    final adapter = StubAdapter((options) {
      for (final entry in handlers.entries) {
        if (options.path.contains(entry.key)) return entry.value(options);
      }
      return jsonBody([]);
    });
    dio.httpClientAdapter = adapter;
    final container = ProviderContainer(
      overrides: [apiClientProvider.overrideWithValue(TsundokuApi(dio))],
    );
    addTearDown(container.dispose);
    await tester.pumpWidget(UncontrolledProviderScope(
      container: container,
      child: const MaterialApp(
        home: Material(
          child: SingleChildScrollView(
            child: LinkedSourcesSection(
              mediaId: 'm1',
              mediaType: 'manga',
            ),
          ),
        ),
      ),
    ));
    await tester.pump();
    await tester.pumpAndSettle();
    return container;
  }

  testWidgets('пусто: приглашение «Привяжите MangaLib…»', (tester) async {
    await pumpSources(tester, handlers: {});
    expect(find.textContaining('Привяжите MangaLib'), findsOneWidget);
    expect(find.text('Внешние источники'), findsOneWidget);
  });

  testWidgets('загрузка: строки источников, crown у primary, чипы полей',
      (tester) async {
    await pumpSources(tester, handlers: {
      '/linked-sources': (options) => jsonBody([
            {
              'source': 'anilist',
              'externalId': '30002',
              'url': null,
              'isPrimary': true,
              'title': 'Frieren — AniList',
              'providedFields': ['title', 'cover', 'episodes'],
            },
            {
              'source': 'mangadex',
              'externalId': 'a1b2c3d4-12e5-4f6a-9b8c-1d2e3f4a5b6c',
              'isPrimary': false,
              'title': null,
              'providedFields': null,
            },
          ]),
    });

    expect(find.text('anilist'), findsOneWidget);
    expect(find.text('mangadex'), findsOneWidget);
    expect(find.text('3'), findsOneWidget); // счётчик полей
    expect(find.byIcon(LucideIcons.crown), findsNWidgets(2)); // primary + кнопка
  });

  testWidgets('добавление: вставленная ссылка mangadex → source по сайту',
      (tester) async {
    final bodies = <Map<String, Object?>>[];
    await pumpSources(tester, handlers: {
      '/api/settings/sources': (options) => jsonBody([
            {
              'id': 'mangadex', 'name': 'MangaDex', 'description': '',
              'mediaTypes': ['manga'],
              'requiresApiKey': false, 'optionalApiKey': false,
              'isConfigured': true, 'hasKey': false, 'maskedKey': null,
              'isEnabled': true, 'isScraper': false, 'isProxied': null,
            },
          ]),
      '/linked-sources': (options) {
        if (options.method == 'POST') {
          // dio-трансформер мог оставить тело Map'ой (stub-адаптер до сериализации).
          final raw = options.data;
          bodies.add(raw is String
              ? jsonDecode(raw) as Map<String, Object?>
              : Map<String, Object?>.from(raw as Map));
          return jsonBody([
            {
              'source': 'mangadex',
              'externalId': 'a1b2c3d4-12e5-4f6a-9b8c-1d2e3f4a5b6c',
              'isPrimary': false,
              'title': null,
              'providedFields': null,
            },
          ]);
        }
        return jsonBody([]);
      },
    });

    // Открыть форму.
    await tester.tap(find.bySemanticsLabel('Добавить'));
    await tester.pumpAndSettle();

    // Ввести ссылку mangadex в поле ID.
    await tester.enterText(find.byType(TextField), 'https://mangadex.org/title/a1b2c3d4-12e5-4f6a-9b8c-1d2e3f4a5b6c/frieren');
    await tester.pump();
    // ignore: avoid_print
    print('BTN: ${find.text('Привязать').evaluate().length}');
    await tester.tap(find.text('Привязать'));
    await tester.pumpAndSettle();
    // ignore: avoid_print
    print('BODIES: $bodies');

    // POST-тело: source mangadex (по сайту ссылки) + голый id.
    expect(bodies, isNotEmpty);
    expect(bodies.first['source'], 'mangadex');
    expect(bodies.first['externalId'], 'a1b2c3d4-12e5-4f6a-9b8c-1d2e3f4a5b6c');
  });
}
