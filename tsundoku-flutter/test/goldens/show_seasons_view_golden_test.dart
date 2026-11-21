import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:tsundoku_flutter/shared/api/api.dart';
import 'package:tsundoku_flutter/shared/theme/tsundoku_theme.dart';
import 'package:tsundoku_flutter/views/show_seasons_view.dart';

class StubAdapter implements HttpClientAdapter {
  @override
  Future<ResponseBody> fetch(
      RequestOptions options,
      Stream<Uint8List>? requestStream,
      Future<void>? cancelFuture) async {
    return ResponseBody.fromString(
        jsonEncode(<String, Object?>{
          'id': 'tv1',
          'type': 'tvshow',
          'title': 'Breaking Bad',
          'status': 1,
          'createdAt': '2024-01-01T00:00:00Z',
          'totalEpisodesWatched': 15,
          'totalEpisodesCount': 62,
          'seasonsCount': 2,
          'seasons': [
            {
              'id': 's1',
              'seasonNumber': 1,
              'title': 'Season 1',
              'status': 1,
              'currentEpisode': 7,
              'totalEpisodes': 7,
              'tvShowId': 'tv1',
            },
            {
              'id': 's2',
              'seasonNumber': 2,
              'title': 'Season 2',
              'status': 1,
              'currentEpisode': 8,
              'totalEpisodes': 13,
              'tvShowId': 'tv1',
            },
          ],
        }),
        200,
        headers: {
          Headers.contentTypeHeader: ['application/json'],
        });
  }

  @override
  void close({bool force = false}) {}
}

// Golden для ShowSeasonsView.svelte: header-карточка + строки сезонов.
// Эталонного Svelte-скриншота нет — self-backstop.
void main() {
  testWidgets('show_seasons_view golden', (tester) async {
    tester.view.physicalSize = const Size(1280, 900);
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
          child: ShowSeasonsView(
            mediaId: 'tv1',
            refreshKey: 0,
            onBack: () {},
            onMediaChanged: () {},
          ),
        ),
      ),
    ));
    for (var i = 0; i < 12; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
    await expectLater(
      find.byType(ShowSeasonsView),
      matchesGoldenFile('goldens/show_seasons_view.png'),
    );
  });
}
