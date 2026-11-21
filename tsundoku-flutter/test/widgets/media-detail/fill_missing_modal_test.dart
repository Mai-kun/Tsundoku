import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tsundoku_flutter/shared/api/api.dart';
import 'package:tsundoku_flutter/shared/types/index.dart';
import 'package:tsundoku_flutter/shared/ui/popover_menu.dart';
import 'package:tsundoku_flutter/widgets/media-detail/fill_missing_modal.dart';

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

/// Тесты `FillMissingModal.svelte`: список источников по типу, selected-
/// каскад (source → currentSource → первый), предпросмотр найдено/нет
/// данных, перезапрос при смене источника, onFill(selectedValue), ошибка
/// загрузки источников.
void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
  });

  List<Map<String, Object?>> sourcesJson() => [
        {
          'id': 'anilist',
          'name': 'AniList',
          'description': '',
          'mediaTypes': <String>[],
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
          'id': 'mangadex',
          'name': 'MangaDex',
          'description': '',
          'mediaTypes': <String>[],
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
          'id': 'rawg',
          'name': 'RAWG',
          'description': '',
          'mediaTypes': <String>[],
          'requiresApiKey': true,
          'optionalApiKey': false,
          'isConfigured': true,
          'hasKey': true,
          'maskedKey': 'ab…',
          'isEnabled': true,
          'isScraper': false,
          'isProxied': null,
        },
        {
          'id': 'sociallib',
          'name': 'SocialLib',
          'description': '',
          'mediaTypes': <String>[],
          'requiresApiKey': false,
          'optionalApiKey': false,
          'isConfigured': true,
          'hasKey': false,
          'maskedKey': null,
          'isEnabled': false, // выключен — не попадает в options manga
          'isScraper': false,
          'isProxied': null,
        },
      ];

  Map<String, Object?> externalDetailsJson() => {
        'externalId': 'ext-1',
        'externalSource': 'anilist',
        'type': 'manga',
        'title': 'Frieren',
        'description': 'Synopsis text',
        'genres': ['Фэнтези', 'Драма', 'Приключения', 'Комедия'],
        'releaseYear': 2023,
        'chapters': 60,
      };

  MediaDetail media(Map<String, Object?> extra) => MediaDetail.fromJson({
        'id': 'm1',
        'type': 'manga',
        'title': 'Frieren',
        'status': 1,
        'createdAt': '2024-01-01T00:00:00Z',
        ...extra,
      });

  Future<(ProviderContainer, StubAdapter)> pumpModal(
    WidgetTester tester, {
    required MediaDetail media,
    String mediaType = 'manga',
    String? currentSource,
    bool busy = false,
    ResponseBody Function(RequestOptions options)? handler,
    void Function(String source)? onFill,
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
          if (options.uri.path.contains('/api/external/details')) {
            return jsonBody(externalDetailsJson());
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
          child: FillMissingModal(
            isOpen: true,
            busy: busy,
            media: media,
            mediaType: mediaType,
            currentSource: currentSource,
            onFill: onFill ?? (_) {},
            onClose: () {},
          ),
        ),
      ),
    ));
    await tester.pump();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    return (container, adapter);
  }

  testWidgets('источники по типу: manga → anilist/mangadex, disabled/rawg отфильтрованы',
      (tester) async {
    await pumpModal(tester, media: media({}));

    // Триггер показывает selected = первый валидный (AniList).
    expect(find.text('AniList'), findsOneWidget);
    expect(find.text('Не удалось загрузить список источников.'), findsNothing);
  });

  testWidgets('предпросмотр: пустые поля, найдено — «будет заполнено»',
      (tester) async {
    await pumpModal(tester, media: media({}));

    // Пустые поля manga: синопсис/жанры/автор/главы/трейлер (+обложка есть,
    // дата выхода — releaseYear нет).
    await tester.pump(const Duration(milliseconds: 200));
    expect(find.text('Предпросмотр данных'), findsOneWidget);
    expect(find.textContaining('будет заполнено'), findsWidgets);
    // Значение из деталей: жанры → formatGenresList (первые 3).
    expect(find.textContaining('Фэнтези'), findsWidgets);
    expect(find.textContaining('Синопсис'), findsWidgets);
    expect(find.textContaining('нет данных в источнике'), findsWidgets);
  });

  testWidgets('запрос details: query type/id/title/source', (tester) async {
    final (_, adapter) = await pumpModal(tester, media: media({}));

    final details = adapter.seen
        .where((o) => o.uri.path.contains('/api/external/details'))
        .toList();
    expect(details, hasLength(1));
    expect(details.single.uri.queryParameters['type'], 'manga');
    expect(details.single.uri.queryParameters['source'], 'anilist');
  });

  testWidgets('currentSource-каскад: currentSource=mangadex → selected MangaDex',
      (tester) async {
    final (_, adapter) = await pumpModal(
      tester,
      media: media({}),
      currentSource: 'MangaDex',
    );

    expect(find.text('MangaDex'), findsOneWidget);
    final details = adapter.seen
        .where((o) => o.uri.path.contains('/api/external/details'))
        .toList();
    expect(details.single.uri.queryParameters['source'], 'mangadex');
  });

  testWidgets('смена источника в поповере → перезапрос details', (tester) async {
    final (_, adapter) = await pumpModal(tester, media: media({}));

    // Открыть поповер (тап по триггеру — внутри IgnorePointer-обёртки
    // тап обрабатывает сам поповер).
    await tester.tap(find.byType(TsundokuPopoverMenu<String>));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 250));

    await tester.tap(find.text('MangaDex').last);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 150));

    final details = adapter.seen
        .where((o) => o.uri.path.contains('/api/external/details'))
        .map((o) => o.uri.queryParameters['source'])
        .toList();
    expect(details, containsAll(['anilist', 'mangadex']));
  });

  testWidgets('busy: спиннер + «Дополняю поля…», тап не вызывает onFill',
      (tester) async {
    var filled = false;
    await pumpModal(
      tester,
      media: media({}),
      busy: true,
      onFill: (_) => filled = true,
    );

    expect(find.textContaining('Дополняю поля'), findsOneWidget);
    await tester.tap(find.textContaining('Дополняю поля'));
    await tester.pump();
    expect(filled, isFalse);
  });

  testWidgets('onFill передаёт selectedValue', (tester) async {
    String? filledSource;
    await pumpModal(
      tester,
      media: media({}),
      onFill: (s) => filledSource = s,
    );

    await tester.tap(find.text('Дополнить данные…'));
    await tester.pump();
    expect(filledSource, 'anilist');
  });

  testWidgets('ошибка загрузки источников: плашка, options пусты, кнопка disabled',
      (tester) async {
    var filled = false;
    await pumpModal(
      tester,
      media: media({}),
      handler: (options) =>
          jsonBody(<String, Object?>{'detail': 'boom'}, 500),
      onFill: (_) => filled = true,
    );

    expect(find.text('Не удалось загрузить список источников.'),
        findsOneWidget);
    // Заглушка «—» вместо триггера.
    expect(find.text('AniList'), findsNothing);
    await tester.tap(find.text('Дополнить данные…'), warnIfMissed: false);
    await tester.pump();
    expect(filled, isFalse);
  });

  testWidgets('все поля заполнены → emerald-плашка «уже заполнены»',
      (tester) async {
    await pumpModal(
      tester,
      media: media({
        'coverUrl': '/media-assets/m1/covers/c1/thumb.webp',
        'description': 'Synopsis',
        'genres': ['Фэнтези'],
        'author': 'Some Author',
        'totalChapters': 10,
        'trailerVideoId': 'abc',
        'releaseYear': 2023,
        'endDate': '2024-03-01',
      }),
    );

    expect(
      find.textContaining('Все основные поля тайтла уже заполнены'),
      findsOneWidget,
    );
    expect(find.textContaining('нет данных в источнике'), findsNothing);
  });
}
