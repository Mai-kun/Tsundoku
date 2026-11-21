import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:tsundoku_flutter/shared/api/api.dart';
import 'package:tsundoku_flutter/shared/theme/tsundoku_theme.dart';
import 'package:tsundoku_flutter/views/media_detail_view.dart';

class StubAdapter implements HttpClientAdapter {
  @override
  Future<ResponseBody> fetch(
      RequestOptions options,
      Stream<Uint8List>? requestStream,
      Future<void>? cancelFuture) async {
    if (options.uri.path.contains('/api/media/m1')) {
      return ResponseBody.fromString(
          jsonEncode(<String, Object?>{
            'id': 'm1',
            'type': 'manga',
            'title': 'Frieren',
            'status': 1,
            'createdAt': '2024-01-01T00:00:00Z',
            'startedAt': '2024-01-05T00:00:00Z',
            'description': 'Подробное описание тайтла.',
            'totalChapters': 100,
            'currentChapter': 42,
            'score': 8,
            'detailedScoreJson': jsonEncode(<String, int>{'story': 8, 'visuals': 6}),
            'externalSource': 'anilist',
            'externalRating': 8.7,
            'externalRatingsJson':
                jsonEncode(<Object?>[
                  {'source': 'AniList', 'rating': 8.7},
                ]),
            'releaseDate': '2020-09-23',
          }),
          200,
          headers: {
            Headers.contentTypeHeader: ['application/json'],
          });
    }
    return ResponseBody.fromString(
        jsonEncode(<Object?>[]), 200,
        headers: {Headers.contentTypeHeader: ['application/json']});
  }

  @override
  void close({bool force = false}) {}
}

// Golden для MediaDetailView.svelte: обзорная вкладка (sidebar + header +
// overview-панель). Эталонного Svelte-скриншота нет — self-backstop.
void main() {
  testWidgets('media_detail_view golden', (tester) async {
    tester.view.physicalSize = const Size(1440, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final dio = Dio()..options.baseUrl = 'http://127.0.0.1:5150';
    dio.httpClientAdapter = StubAdapter();
    final container = ProviderContainer(
      overrides: [apiClientProvider.overrideWithValue(TsundokuApi(dio))],
    );
    addTearDown(container.dispose);

    await tester.pumpWidget(UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        theme: buildTsundokuTheme(),
        home: Material(
          child: SingleChildScrollView(
            child: MediaDetailView(
              mediaId: 'm1',
              refreshKey: 0,
              onBack: () {},
              onUpdate: () {},
              onDelete: (_) async {},
              onEdit: (_) {},
              onOpenRelated: (_) {},
              onSearch: (_) {},
              onOpenLists: () {},
            ),
          ),
        ),
      ),
    ));
    for (var i = 0; i < 12; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
    await expectLater(
      find.byType(MediaDetailView),
      matchesGoldenFile('goldens/media_detail_view.png'),
    );
  });
}
