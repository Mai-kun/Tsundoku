import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tsundoku_flutter/shared/api/api.dart';
import 'package:tsundoku_flutter/views/show_seasons_view.dart';
import 'package:tsundoku_flutter/widgets/media-detail/season_row.dart';

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

/// Тесты `ShowSeasonsView.svelte`: скелетон загрузки, error-box с retry
/// (sequence-гвард), header-карточка (счётчик, seasonsCount), пустые
/// сезоны, список SeasonRow.
void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
  });

  Map<String, Object?> showPayload({
    List<Map<String, Object?>> seasons = const [],
  }) =>
      {
        'id': 'tv1',
        'type': 'tvshow',
        'title': 'Breaking Bad',
        'status': 1,
        'createdAt': '2024-01-01T00:00:00Z',
        'coverUrl': '/img/tv1.jpg',
        'totalEpisodesWatched': 15,
        'totalEpisodesCount': 62,
        'seasonsCount': seasons.length,
        'seasons': seasons,
      };

  Future<(ProviderContainer, StubAdapter)> pumpView(
    WidgetTester tester, {
    required ResponseBody Function(RequestOptions options) handler,
    int refreshKey = 0,
  }) async {
    tester.view.physicalSize = const Size(1280, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    final dio = Dio()..options.baseUrl = 'http://127.0.0.1:5150';
    final adapter = StubAdapter(handler);
    dio.httpClientAdapter = adapter;
    final container = ProviderContainer(
      overrides: [apiClientProvider.overrideWithValue(TsundokuApi(dio))],
    );
    addTearDown(container.dispose);

    await tester.pumpWidget(UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        home: Material(
          child: ShowSeasonsView(
            mediaId: 'tv1',
            refreshKey: refreshKey,
            onBack: () {},
            onMediaChanged: () {},
          ),
        ),
      ),
    ));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    return (container, adapter);
  }

  testWidgets('загрузка: скелетон → header-карточка + heading + сезоны',
      (tester) async {
    await pumpView(
      tester,
      handler: (options) => jsonBody(showPayload(seasons: [
        {
          'id': 's1',
          'seasonNumber': 1,
          'title': 'Season 1',
          'status': 1,
          'currentEpisode': 7,
          'totalEpisodes': 7,
          'tvShowId': 'tv1',
        },
      ])),
    );

    expect(find.text('Breaking Bad'), findsOneWidget);
    expect(find.text('Сериалы'), findsOneWidget); // navigation.tvshow
    expect(find.text('15 / 62 · 1'), findsOneWidget);
    expect(find.text('Сезоны: Breaking Bad'), findsOneWidget);
    expect(find.byType(SeasonRow), findsOneWidget);
  });

  testWidgets('ошибка: error-box с errorMessage + retry', (tester) async {
    await pumpView(
      tester,
      handler: (options) => jsonBody(
          <String, Object?>{'detail': 'Internal error'}, 500),
    );

    expect(find.text('Internal error'), findsOneWidget); // role=alert
    expect(find.text('Повторить'), findsOneWidget);
    expect(find.byIcon(LucideIcons.refreshCw), findsOneWidget);
  });

  testWidgets('retry: клик «Повторить» → повторный GET → успех', (tester) async {
    var fail = true;
    final (_, adapter) = await pumpView(
      tester,
      handler: (options) => fail
          ? jsonBody(<String, Object?>{'detail': 'boom'}, 500)
          : jsonBody(showPayload()),
    );

    expect(find.text('boom'), findsOneWidget);
    final callsBefore =
        adapter.seen.where((o) => o.uri.path.contains('/api/media/tv1')).length;

    fail = false;
    await tester.tap(find.text('Повторить'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    final callsAfter =
        adapter.seen.where((o) => o.uri.path.contains('/api/media/tv1')).length;
    expect(callsAfter, greaterThan(callsBefore));
    expect(find.text('Breaking Bad'), findsOneWidget);
  });

  testWidgets('не-tvshow: StateError → error-box (guard isTvShowDetail)',
      (tester) async {
    await pumpView(
      tester,
      handler: (options) => jsonBody(<String, Object?>{
        'id': 'tv1',
        'type': 'manga',
        'title': 'Not a show',
        'status': 1,
        'createdAt': '2024-01-01T00:00:00Z',
      }),
    );

    expect(find.byType(SeasonRow), findsNothing);
    // error-box рендерится (повторить доступен).
    expect(find.text('Повторить'), findsOneWidget);
  });

  testWidgets('пустые сезоны: «У этого сериала пока нет сезонов.»',
      (tester) async {
    await pumpView(
      tester,
      handler: (options) => jsonBody(showPayload()),
    );

    expect(find.text('У этого сериала пока нет сезонов.'), findsOneWidget);
    expect(find.byType(SeasonRow), findsNothing);
  });

  testWidgets('несколько сезонов: строки по ключу id', (tester) async {
    await pumpView(
      tester,
      handler: (options) => jsonBody(showPayload(seasons: [
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
          'currentEpisode': 3,
          'totalEpisodes': 13,
          'tvShowId': 'tv1',
        },
      ])),
    );

    expect(find.byType(SeasonRow), findsNWidgets(2));
    expect(find.text('СЕЗОН 2'), findsOneWidget);
  });
}
