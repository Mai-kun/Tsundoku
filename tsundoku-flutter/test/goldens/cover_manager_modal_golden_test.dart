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
import 'package:tsundoku_flutter/widgets/media-detail/cover_manager_modal.dart';



class _StubAdapter implements HttpClientAdapter {
  @override
  Future<ResponseBody> fetch(
      RequestOptions options,
      Stream<Uint8List>? requestStream,
      Future<void>? cancelFuture) async {
    return ResponseBody.fromString(jsonEncode(<String, Object?>{
      'id': 'm1',
      'type': 'manga',
      'title': 'Frieren',
      'status': 2,
      'createdAt': '2024-01-01T00:00:00Z',
      'coverUrl': '/media-assets/m1/covers/c1/thumb.webp',
      'covers': [
        {
          'id': 'c1',
          'thumbUrl': '/media-assets/m1/covers/c1/thumb.webp',
          'originalUrl': '/media-assets/m1/covers/c1/original.webp',
          'source': 'AniList',
          'addedAt': '2024-01-02T00:00:00Z',
        },
        {
          'id': 'c2',
          'thumbUrl': '/media-assets/m1/covers/c2/thumb.webp',
          'originalUrl': '/media-assets/m1/covers/c2/original.webp',
          'source': 'MangaDex',
          'addedAt': '2024-01-03T00:00:00Z',
        },
        {
          'id': 'c3',
          'thumbUrl': '/media-assets/m1/covers/c3/thumb.webp',
          'originalUrl': '/media-assets/m1/covers/c3/original.webp',
          'source': 'MangaLib',
          'addedAt': '2024-01-04T00:00:00Z',
        },
      ],
    }), 200, headers: {
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
  testWidgets('golden: cover_manager_modal', (tester) async {
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
          child: CoverManagerModal(
            isOpen: true,
            media: MediaDetail.fromJson(<String, Object?>{
              'id': 'm1',
              'type': 'manga',
              'title': 'Frieren',
              'status': 2,
              'createdAt': '2024-01-01T00:00:00Z',
              'coverUrl': '/media-assets/m1/covers/c1/thumb.webp',
              'covers': [
                {
                  'id': 'c1',
                  'thumbUrl': '/media-assets/m1/covers/c1/thumb.webp',
                  'originalUrl': '/media-assets/m1/covers/c1/original.webp',
                  'source': 'AniList',
                  'addedAt': '2024-01-02T00:00:00Z',
                },
                {
                  'id': 'c2',
                  'thumbUrl': '/media-assets/m1/covers/c2/thumb.webp',
                  'originalUrl': '/media-assets/m1/covers/c2/original.webp',
                  'source': 'MangaDex',
                  'addedAt': '2024-01-03T00:00:00Z',
                },
                {
                  'id': 'c3',
                  'thumbUrl': '/media-assets/m1/covers/c3/thumb.webp',
                  'originalUrl': '/media-assets/m1/covers/c3/original.webp',
                  'source': 'MangaLib',
                  'addedAt': '2024-01-04T00:00:00Z',
                },
              ],
            }),
            onClose: () {},
            onUpdate: (_) {},
          ),
        ),
      ),
    ));
    await tester.pump();
    await tester.pump();

    await expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile('goldens/cover_manager_modal.png'),
    );
  });
}
