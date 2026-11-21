import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tsundoku_flutter/shared/api/api.dart';
import 'package:tsundoku_flutter/shared/theme/tsundoku_theme.dart';
import 'package:tsundoku_flutter/widgets/media-detail/relink_source_modal.dart';



class _StubAdapter implements HttpClientAdapter {
  @override
  Future<ResponseBody> fetch(
      RequestOptions options,
      Stream<Uint8List>? requestStream,
      Future<void>? cancelFuture) async {
    // sources → поиск: happy-path результатов.
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
    if (options.uri.path.contains('/api/external/search')) {
      return ResponseBody.fromString(jsonEncode(<dynamic>[
        <String, Object?>{
          'externalId': 'ext-1',
          'externalSource': 'mangadex',
          'type': 'manga',
          'title': 'Sousou no Frieren',
          'releaseYear': 2020,
        },
        <String, Object?>{
          'externalId': 'ext-2',
          'externalSource': 'anilist',
          'type': 'manga',
          'title': 'Frieren: Beyond Journey\'s End',
          'releaseYear': 2023,
        },
      ]), 200, headers: {
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
  testWidgets('golden: relink_source_modal', (tester) async {
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
          child: RelinkSourceModal(
            isOpen: true,
            mediaId: 'm1',
            title: 'Frieren',
            originalTitle: 'Sousou no Frieren',
            type: 'manga',
            currentSource: 'MangaDex',
            onClose: () {},
            onRelinked: (_) {},

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
      matchesGoldenFile('goldens/relink_source_modal.png'),
    );
  });
}
