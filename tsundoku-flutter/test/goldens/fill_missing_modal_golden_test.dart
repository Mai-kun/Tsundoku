import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tsundoku_flutter/shared/api/api.dart';
import 'package:tsundoku_flutter/shared/theme/tsundoku_theme.dart';
import 'package:tsundoku_flutter/shared/types/index.dart';
import 'package:tsundoku_flutter/widgets/media-detail/fill_missing_modal.dart';



class _StubAdapter implements HttpClientAdapter {
  @override
  Future<ResponseBody> fetch(
      RequestOptions options,
      Stream<Uint8List>? requestStream,
      Future<void>? cancelFuture) async {
    // sources → детали AniList: happy-path предпросмотра.
    if (options.uri.path.contains('/api/settings/sources')) {
      return ResponseBody.fromString(jsonEncode(<dynamic>[
        <String, Object?>{
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
        <String, Object?>{
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
      ]), 200, headers: {
        Headers.contentTypeHeader: ['application/json'],
      });
    }
    if (options.uri.path.contains('/api/external/details')) {
      return ResponseBody.fromString(jsonEncode(<String, Object?>{
        'externalId': 'ext-1',
        'externalSource': 'anilist',
        'type': 'manga',
        'title': 'Frieren',
        'description': 'Synopsis from AniList',
        'genres': ['Фэнтези', 'Драма', 'Приключения', 'Комедия'],
        'releaseYear': 2023,
        'chapters': 60,
      }), 200, headers: {
        Headers.contentTypeHeader: ['application/json'],
      });
    }
    return ResponseBody.fromString(jsonEncode(<String, Object?>{}), 200,
        headers: {
      Headers.contentTypeHeader: ['application/json'],
    });
  }

  @override
  void close({bool force = false}) {}
}

void main() {
  setUpAll(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
  });

  // Backstop-golden модалки обложек (Svelte-скриншота нет — node сломан,
  // см. Заметки окружения #2): 1440×900 @ dpr 1.0, open-стейт, manga с
  // тремя обложками. Обновление: `flutter test --update-goldens test/goldens`.
  testWidgets('golden: fill_missing_modal', (tester) async {
    tester.view.devicePixelRatio = 1.0;
    tester.view.physicalSize = const Size(1440, 900);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);

    final dio = Dio()..options.baseUrl = 'http://127.0.0.1:5150';
    dio.httpClientAdapter = _StubAdapter();
    final container = ProviderContainer(
      overrides: [apiClientProvider.overrideWithValue(TsundokuApi(dio))],
    );
    addTearDown(container.dispose);

    await tester.pumpWidget(UncontrolledProviderScope(
      container: container,
      // buildTsundokuTheme: Inter + obsidian — 1-в-1 с TsundokuApp.
      child: MaterialApp(
        theme: buildTsundokuTheme(),
        home: Material(
          child: FillMissingModal(
            isOpen: true,
            busy: false,
            media: MediaDetail.fromJson(<String, Object?>{
              'id': 'm1',
              'type': 'manga',
              'title': 'Frieren',
              'status': 2,
              'createdAt': '2024-01-01T00:00:00Z',
              'coverUrl': '/media-assets/m1/covers/c1/thumb.webp',
            }),
            mediaType: 'manga',
            currentSource: null,
            onFill: (_) {},
            onClose: () {},
          ),
        ),
      ),
    ));
    await tester.pump();
    // Прогрев: getSources → details завершаются в fake-async, pending-таймеры
    // dio рассасываются (аналог postPumpFrames из app_scaffold).
    for (var i = 0; i < 12; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }

    await expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile('goldens/fill_missing_modal.png'),
    );
  });
}
